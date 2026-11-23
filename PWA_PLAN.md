# PWA plan: installable app + real push notifications

Goal: people install family-status from their browser onto their phone, it
behaves like an app (icon, full screen, no browser chrome), and they get push
notifications on the lock screen even when the app is closed. No Android or
iOS native apps.

This file has three parts: what's true today, the work for the coding agent
(phased, each phase shippable on its own), and the steps only the owner can
do.

## 1. Where things stand

- Rails 8.1, SQLite, Solid Queue inside Puma (`config/recurring.yml` already
  runs `ScheduleTickJob` every minute), Kamal behind `proxy: ssl: true`.
- `app/views/pwa/manifest.json.erb` and `service-worker.js` are the Rails
  defaults: the manifest says `theme_color: red` and "FamilyStatus", the
  service worker is entirely commented out. **Neither is linked** from
  `layouts/application.html.erb`, and `config/routes.rb` has no `pwa` routes
  (verify; the Rails default is `get "manifest" => "rails/pwa#manifest"`).
- The layout already has the `apple-mobile-web-app-capable` and
  `mobile-web-app-capable` tags, a viewport tag, `/icon.png` (512px) and an
  apple-touch-icon pointing at the same file.
- Notifications today: three code paths broadcast a hidden
  `shared/_notification` partial on `[user, :notifications]`:
  `TaskAssigner#notify` (assigned / asked, clash), `Task#notify_people`
  (status changes, follow-ups), `PetCheckIn#notify_subscribers` (followed
  pets moved or fed). `notification_controller.js` turns it into
  `new Notification(...)` **only while a tab is open**. There is no Web Push.
- `notifications_controller.js` is an opt-in banner shown on the dashboard
  and pet pages. It never auto-prompts, which is correct and should stay.
- CSP is strict: `default_src :self`, `script_src :self`, `connect_src`
  `:self` plus the websocket. A service worker served from our own origin and
  push messages (delivered to the worker, not fetched by the page) need no
  CSP changes. Check that `worker-src` falls back to `script-src 'self'`
  (it does).
- No automated way to send a reminder before something happens; every
  notification fires on a change, not on the clock.
- Mobile CSS: one breakpoint (`max-width: 719px`), no safe-area handling, no
  bottom navigation, nav wraps to several rows on a phone.

## 2. Decisions already made (don't relitigate)

1. **PWA + Web Push, not native apps.**
2. **One notifier, many channels.** Replace the three copy-pasted
   `broadcast_append_to ... notifications` blocks with a single
   `Notifier.notify(user, title:, body:, path:, tag:, kind:, urgency:)` that
   (a) keeps the existing in-app stream for open tabs and (b) queues a push
   per subscription. In-app stream stays so the open-tab experience doesn't
   regress, but must not double-notify (see Phase 3).
3. **Dependency-free Web Push, per the repo convention** (AGENTS.md: "no auth
   gems beyond Devise; keep it that way unless the lockfile can be
   regenerated"). Write `lib/web_push/` (RFC 8030 delivery, RFC 8291
   `aes128gcm` encryption, RFC 8292 VAPID ES256 JWT) on OpenSSL + `Net::HTTP`,
   with tests in `test/lib`, like `lib/web_authn`. The `web-push` gem is the
   acceptable fallback if the agent finds that hand-rolling is taking
   disproportionately long; the latest commit shows the lockfile can be
   regenerated, so it's allowed, but say so in the PR.
4. **Notification preferences are part of "done".** Pushing every pet
   feeding to every follower would get the app muted within a week.
5. **Email is the fallback channel**, not a separate product (Phase 6).

## 3. Phased work for the coding agent

Each phase ends with `bin/rails test` green and a short manual check. Keep
commits per phase. Follow AGENTS.md: tokens-only CSS, reuse the existing
class vocabulary, household scoping on every query, no user text interpolated
into HTML, register new Stimulus controllers in
`app/javascript/controllers/index.js`, add icons to `IconsHelper::ICONS`.

### Phase 1: Installable app shell

Make it a real PWA with no push yet.

- Routes: `get "manifest" => "rails/pwa#manifest", as: :pwa_manifest` and
  `get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker`.
  Both must be reachable **without signing in** and must be excluded from the
  first-run gate redirect in `ApplicationController` (a browser fetches them
  before it has a session). Check the setup gate and Devise's authenticate
  don't redirect them.
- Layout (both `application` and `wall`): `<link rel="manifest">`,
  `<meta name="theme-color">` (with light/dark variants via `media`
  attributes, values from the CSS tokens, not new hexes), `viewport-fit=cover`
  on the viewport tag.
- Manifest: make it an ERB that uses `app_name` (`AppSettings`), a real
  `description`, `start_url: "/?source=pwa"` (so the dashboard knows it's
  running installed), `scope: "/"`, `display: "standalone"`, `id: "/"`,
  `theme_color`/`background_color` matching the app's tokens (not `red`).
- Icons: 192, 512, a **maskable** 512 with proper safe-zone padding (the
  current manifest reuses one image for both, which gets cropped), plus a
  180px `apple-touch-icon`. Generate from `public/icon.svg`. Check whether
  an image tool is installed; if not, ask the owner to supply the PNGs (see
  owner steps) rather than adding a gem.
- Service worker: minimal and **safe**. Precache only an offline fallback
  page (`/offline.html` in `public/`, styled with inline CSS). Network-first
  for navigations, fall back to the offline page. Never cache HTML of
  authenticated pages, `/cable`, or anything under `/h/` (the wall must
  always be live). No runtime caching of API/Turbo responses. Version the
  worker (a constant) and call `skipWaiting` / `clients.claim` deliberately.
- Register the worker from `application.js` after `load`, only in a secure
  context, only when `navigator.serviceWorker` exists. Not on the wall layout.
- Offline behaviour of actions: do **not** build offline queues. When the
  network is down show the offline page; say so in the UI instead of
  pretending.
- Tests: manifest and worker are served unauthenticated with the right
  content types; manifest JSON parses and has required keys; layout contains
  the link tags.
- Manual check: Chrome DevTools > Application > Manifest shows no errors and
  "installable"; Lighthouse PWA audit passes.

### Phase 2: Push plumbing (server)

- Migration `push_subscriptions`: `user_id` (FK, index), `endpoint` (text,
  unique index), `p256dh`, `auth` (encrypted with `encrypts`, like TOTP
  secrets), `user_agent` (string, for the "your devices" list), `last_used_at`,
  `last_error`, `failed_at` (nullable), timestamps. A user has many.
- VAPID keys: generate a P-256 keypair on first use and persist it the way
  `entrypoint.sh` persists `.secret_key_base` (file under `storage/`), with
  ENV override (`VAPID_PRIVATE_KEY`, `VAPID_PUBLIC_KEY`). Never put the
  private key in the DB unencrypted or in git. Add `rake push:keys`
  (prints the public key) next to `setup:code`. The subject claim comes from
  the app's mail-from address or `APP_URL`, from `AppSettings`.
- `lib/web_push/`: `Vapid` (ES256 JWT, 12h expiry, audience from endpoint
  origin), `Encryption` (RFC 8291: ECDH, HKDF, `aes128gcm`, 4096-byte record,
  padding), `Client` (POST with `TTL`, `Urgency`, `Topic`, `Content-Encoding`,
  `Authorization: vapid t=..., k=...`; returns a result object: ok /
  gone (404, 410) / retry (429, 5xx, timeouts) / failed). Include the RFC
  8291 appendix test vector in `test/lib` so the encryption is proven correct
  against a known answer, not just self-consistent.
- Endpoint safety: only POST to `https` endpoints, and refuse hosts that
  resolve to private, loopback or link-local addresses (SSRF: a user could
  otherwise register `http://169.254.169.254/...`). Optionally allowlist known
  push hosts (`fcm.googleapis.com`, `*.push.apple.com`,
  `*.notify.windows.com`, `updates.push.services.mozilla.com`) and log
  others.
- `PushSubscriptionsController` (`create`, `destroy`, `test`), sign-in
  required, scoped to `current_user`. `create` upserts by endpoint so a phone
  that re-subscribes doesn't duplicate, and so one endpoint can't remain
  attached to a previous user on a shared phone (re-home it to the current
  user). Rate-limit like the existing resets.
- `SendPushJob(subscription_id, payload, urgency, ttl)`: sends, on `gone`
  deletes the subscription, on `retry` retries with backoff (a few attempts),
  on other failure records `last_error`/`failed_at` and stops. Never raises
  into the request that caused it. Queue `background`.
- `Notifier` (see decision 2) fans out to subscriptions. Payload is small
  JSON: `title`, `body`, `path` (same-origin path only), `tag`, `icon`,
  `badge`. No secrets or full task contents; private tasks must use
  `Task#title_for` so a private item never leaks into a lock screen. Add a
  test for that.
- Tests: encryption vector, VAPID signature verifies, job deletes on 410,
  controller scoping (can't touch another user's subscription), endpoint
  SSRF rejection, private-task title redaction.

### Phase 3: Push plumbing (client) and the opt-in flow

- Service worker: add `push` (parse JSON, always call `showNotification`,
  because iOS revokes subscriptions that receive a push without showing one,
  even if the payload is malformed: fall back to a generic message) and
  `notificationclick` (focus an existing window and navigate to
  `data.path`, else `openWindow`; validate the path is same-origin and
  starts with `/`). Use `tag` + `renotify` so repeats collapse.
  `pushsubscriptionchange`: resubscribe and POST the new subscription.
- Replace `notifications_controller.js` with a `push` controller that:
  - detects the platform state and renders the right instruction:
    1. unsupported browser,
    2. **iOS Safari not installed to the Home Screen** (detect iOS + not
       `display-mode: standalone` + no `PushManager`): show "Tap Share, then
       Add to Home Screen, then open it from your Home Screen and turn
       notifications on" with a small illustration or the icon,
    3. permission `default`: an **Enable notifications** button (user
       gesture required; never auto-prompt),
    4. permission `denied`: explain how to re-enable in system settings,
    5. subscribed: show on, with a **Send me a test** button.
  - subscribes with `pushManager.subscribe({ userVisibleOnly: true,
    applicationServerKey })`, the public key delivered in a data attribute,
    and POSTs the subscription to the server.
  - verifies on every app load that the browser's subscription still exists
    server-side and re-registers if not (self-healing).
- Dedupe: when a tab is open **and visible**, the in-app stream already
  shows the notification; the server must not also push. Simplest rule:
  `Notifier` always pushes, and the service worker's `push` handler checks
  `clients.matchAll({ type: "window" })` for a **focused** client and skips
  `showNotification` only if it posts a message to that client instead.
  But because iOS requires a visible notification on every push, on iOS
  always show it. Pick the approach, write down why, test both.
  (Alternative: drop the in-app `new Notification` path entirely and have
  open tabs show a small in-page toast; simpler and consistent.
  Recommended.)
- Account page section **Notifications**: this device's state and toggle, a
  list of the user's registered devices (parsed `user_agent` -> "iPhone,
  Safari", last used) each with Remove, and the test button.
- Tests: controller flow with stubbed `Notifier`; JS is verified manually
  (see checks).
- Manual check on a real Android phone first, then a real iPhone.

### Phase 4: Notification preferences

- Table or columns for per-user settings, defaults chosen sensibly:
  - `assigned_to_me` (assignments and clash requests): on, urgent
  - `status_changes` (changes on items I'm on or follow up): on
  - `followed_pets` (moved or fed): on
  - `reminders` (Phase 5): on
  - `quiet_hours_start` / `quiet_hours_end` (household time zone): off by
    default. During quiet hours, non-urgent pushes are **held and delivered as
    one summary** when it ends, or simply dropped if that proves too complex
    (decide and say which in the PR). Clash requests that need action are
    never held.
  - Master switch: pause everything for N hours ("I'm on a plane").
- `Notifier` consults the preferences by `kind`. Add the settings UI to the
  same account Notifications section, using the existing `inline-check` /
  chip styles.
- Per pet follow (`PetSubscription`) keeps working as today; the
  `followed_pets` toggle is the global gate on top of it.
- Tests per kind and per quiet-hours boundary, in the household time zone.

### Phase 5: Reminders (notifications on the clock)

This is the part that makes the feature actually useful, and it doesn't
exist at all today.

- Extend `ScheduleTickJob` (or add a sibling recurring job) to find events
  starting in N minutes (default 15, per-user setting 5/15/30/60/off) and
  to-dos due today that aren't done (one morning digest at a user-chosen
  hour, off by default), for **accepted** assignees only.
- Idempotency is the whole game: a `reminders_sent` record keyed by
  (task, user, kind, occurrence start) with a unique index so a retry or a
  double tick never sends twice. Recurring events must key on the occurrence,
  not the task id.
- Respect private tasks (`title_for`), declined or pending assignments (no
  reminders), and the household time zone.
- Optional later: "pet not fed by <time>" nudge, driven by `meals_per_day`.
  Don't build until asked.
- Tests with time travel: boundary at exactly N minutes, double tick,
  recurring occurrence, declined assignee, DST change day.

### Phase 6: Email fallback

- For people who never install or who denied permission: optional per-user
  daily digest email and an "important only" email (clash request) using the
  existing mailer and SMTP settings. Off by default; one-click unsubscribe
  link (signed token, no login) in every message. Links come from
  `AppSettings.url_options`, per AGENTS.md.
- Skip entirely if SMTP isn't configured; hide the toggles then.

### Phase 7: Phone UX pass

The site "works" on mobile CSS-wise; this phase makes it good in a thumb.

- Audit on real devices and in Chrome device mode at 360x640, 390x844 and
  a small-phone 320 width, writing findings in the PR before fixing.
- Likely work: a bottom tab bar (Home, Schedule, Pets, Account) shown only
  below the breakpoint and only when installed/standalone is **not** a
  requirement (works in the browser too), replacing the 3-row wrapping nav;
  safe-area insets (`env(safe-area-inset-*)`) for the notch and home
  indicator, including the sticky action bars; 44px minimum tap targets;
  `input` font size at least 16px to stop iOS zoom on focus;
  `overscroll-behavior` and tap highlight tuning; standalone-mode
  (`@media (display-mode: standalone)`) tweaks such as hiding anything that
  tells people to "install the app".
- The fast actions are the phone's job: confirm "I'm at...", **Fed**, mark
  done and accept/decline are reachable in one or two taps from the home
  screen, and that Turbo/Action Cable reconnect cleanly when the app returns
  from the background (listen for `visibilitychange` and refresh).
- Dark/light follows the OS (already tokenised); verify the theme-color meta
  matches in both.
- No horizontal scroll anywhere at 320px.

### Phase 8: Deploy, docs and hardening

- README and AGENTS.md: new files, new tables, new env vars (`VAPID_*`),
  the iOS Home Screen requirement, HTTPS requirement, and the updated
  "Gotchas" line (currently says there's no Web Push).
- Admin > Settings: a small "Notifications" status block (VAPID configured?
  public key, count of subscriptions, last send error) so the owner can
  diagnose without logs.
- Make sure `storage/` persistence covers the VAPID key (it's in the Kamal
  volume already). Losing it invalidates **all** subscriptions: devices must
  re-subscribe. Document this; the self-healing client check in Phase 3
  means they re-subscribe the next time the app opens, which is acceptable.
- `config/deploy.yml`: nothing new expected beyond the correct real
  `proxy.host` and `APP_URL` (owner step). The service worker path must be
  served by the app, not Thruster's static cache with long max-age: confirm
  `service-worker` and `manifest` responses are sent with
  `Cache-Control: no-cache` so updates ship.
- Brakeman and rubocop clean. `bin/rails test` green.

## 4. Test plan summary

| Layer | How |
| --- | --- |
| Encryption and VAPID | Known-answer vectors in `test/lib` |
| Server flow | Integration tests with a fake push endpoint (local `TCPServer` or stubbed `Client`) |
| Preferences, reminders | Model tests with `travel_to` |
| Install and push on devices | Manual, on real hardware (checklist below) |

Manual device checklist (run for Android Chrome and iPhone Safari):

1. Open the site, sign in, confirm the install prompt or the Add to Home
   Screen path works and the icon and name look right.
2. Open from the Home Screen icon: no browser chrome, status bar colour is
   right, back and forward feel normal.
3. Enable notifications, send the test: arrives with the app in the
   foreground, in the background, and with the phone locked.
4. Have another account assign a task: push arrives, tap opens the task.
5. Mark the phone Do Not Disturb: arrives silently in the shade, no sound.
6. Turn off Wi-Fi: offline page, not a blank screen. Turn back on: recovers.
7. Remove the device from the Notifications list on the account page: pushes
   stop. Re-enable: they resume.
8. Sign out and sign in as a different user on the same phone: the first
   user's pushes stop arriving there.

## 5. What you (the owner) need to do

These can't be done by the agent. Roughly in the order you'll hit them.

1. **Pick a real domain with HTTPS before anything else.** Service workers,
   push and passkeys all need a secure context, and a certificate for a bare
   LAN IP won't do. Set `proxy.host` and `APP_URL` in `config/deploy.yml`
   (currently `status.example.com` placeholders), point DNS at the server,
   and confirm Kamal's proxy gets a Let's Encrypt cert. Your wall iPad and
   everyone's phones should all use this same address. Passkeys are bound to
   the hostname, so changing it later means re-registering them.
2. **Deploy once with the current code and confirm** `/up` is healthy over
   https. Don't start testing push on a broken deploy.
3. **Supply or approve the icon.** Decide whether `public/icon.svg` is the
   final brand. If you want a different one, give the agent an SVG or a
   1024x1024 PNG with a plain background and some breathing room around the
   mark (maskable icons get cropped to a circle or rounded square).
4. **Confirm the app name** (shown under the icon; keep it under about 12
   characters or it truncates on iOS). Currently the manifest says
   "FamilyStatus" while the app says "family-status".
5. **Decide the notification defaults** the agent will ship with (Phase 4):
   which kinds are on by default, whether quiet hours exist, and the default
   reminder lead time (suggested 15 minutes).
6. **Test on real phones, not just a desktop.** Phases 3 and 7 are not
   verifiable by automated tests. You need:
   - an Android phone with Chrome,
   - an iPhone running **iOS 16.4 or later** (check Settings > General >
     About). Older iPhones can't get web push at all.
   Install from the Home Screen on iPhone; remember that Safari tabs can't
   receive push.
7. **Tell your family the one-time steps.** On iPhone: open the link in
   Safari, tap Share, Add to Home Screen, open it from the icon, tap Enable
   notifications. On Android: open the link in Chrome, tap Install or Add to
   Home screen, then Enable notifications. Put these steps in the invitation
   email text if you like (the agent can add them in Phase 8).
8. **Back up `storage/`** (the database and the generated VAPID key live
   there). If it's lost, everyone has to re-enable notifications.
9. **Optional: SMTP.** Only if you want the Phase 6 email fallback. Set it
   in Admin > Settings. Use a sender address your domain is allowed to send
   from (SPF/DKIM) or digests land in spam.
10. **Review and merge each phase's PR.** Phase 1 is safe to ship alone and
    gives you installable icons immediately; push (2 and 3) should ship
    together; 4 should follow quickly after, before you invite anyone who
    isn't you.

## 6. Risks and things to watch

- **iOS is the weak link.** Install friction and platform quirks are the
  likeliest reasons a family member says "I never got it". Invest in the
  instructions in Phase 3 and keep email as a fallback.
- **Over-notifying** gets the app muted or uninstalled. Ship preferences
  with push, not after.
- **Subscription rot.** Phones come and go; handle 404/410 by deleting, and
  keep the self-healing client check.
- **Service worker caching bugs are nasty** (users stuck on an old version).
  Keep the worker tiny, never cache authenticated HTML, and make updates
  immediate.
- **SQLite and one instance.** Push sends go through Solid Queue in the same
  container; a big household with many devices is fine, but sends must stay
  in the background job, never in the request or an `after_commit`
  callback's critical path.
- **Privacy on lock screens.** Private tasks must stay redacted
  (`title_for`), and consider a per-user "hide details on lock screen"
  option (generic "You have an update") if anyone cares.
- **Single-household assumptions.** Notifications from a user who belongs to
  several households should name the household (the existing title already
  does); make sure the tap path switches household context (see
  `session[:current_household_id]`) or the link will 404.
