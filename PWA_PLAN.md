# PWA plan: installable app, push and email notifications, per-user settings

> **Status (Nov 2026):** phases 1 to 5 and the folded-in hardening are
> built on the `pwa-plan` branch, one commit per phase. What's left is
> section 6 (the owner's steps) and the manual device checklist in
> section 5. Small departures from the text below: the Email column's
> address is shown in the hint under the table (a header that long doesn't
> fit at 320px); the Notifications page already existed in phase 3, so the
> temporary account-page section was skipped; a replaced subscription is
> re-posted to `POST /push_subscriptions/renew`, authorised by the old
> endpoint, since a service worker has no CSRF token; and
> `public/icon.svg` is a new mark (the nav's house on the accent colour)
> because the old one was the Rails placeholder circle.

Goal: people install family-status from their browser onto their phone, it
behaves like an app (icon, full screen, no browser chrome), and they get
notifications on the lock screen even when the app is closed. Each person
chooses, per kind of update, whether it reaches them by **push**, **email**,
both or neither. No Android or iOS native apps.

This file has: what's true today, the decisions, the phased work (each phase
shippable on its own), what's deliberately out of scope, and the steps only
the owner can do.

## 1. Where things stand

- Rails 8.1, SQLite, Solid Queue inside Puma (`config/recurring.yml` runs
  `ScheduleTickJob` every minute), Kamal behind `proxy: ssl: true`.
- `app/views/pwa/manifest.json.erb` and `service-worker.js` are the Rails
  defaults (`theme_color: red`, "FamilyStatus", worker fully commented out).
  Neither is linked from a layout and `config/routes.rb` has no `pwa` routes.
- Both layouts have `apple-mobile-web-app-capable`, `mobile-web-app-capable`,
  a viewport tag, `/icon.png` (512px) as icon and apple-touch-icon, and
  `public/icon.svg`.
- Notifications today: **four** code paths broadcast the hidden
  `shared/_notification` partial on `[user, :notifications]`:
  - `TaskAssigner#notify`: assigned / asked (clash),
  - `Task#notify_people`: status changes, follow-ups,
  - `TasksController#respond_to_invite`: someone accepted or declined an item
    you made,
  - `PetCheckIn#notify_subscribers`: followed pets moved or fed.
  `notification_controller.js` turns them into `new Notification(...)` **only
  while a tab is open**. There is no Web Push and no notification email.
- `notifications_controller.js` + `shared/_notifications_banner` is an
  opt-in banner on the dashboard and pet pages. It never auto-prompts; that
  stays true.
- CSP: `default_src :self`, `script_src :self`. A same-origin service worker
  needs no change (`worker-src` falls back to `script-src 'self'`); push
  messages are delivered to the worker, not fetched by the page.
- Every notification fires on a change; nothing fires on the clock.
- Account page (`Account::ProfilesController#show`) is one page of
  `account-section`s: Profile, Passkeys, Password, Two-step verification.
- `AppSettings.smtp_configured?` says whether email can be sent; mail goes
  through `:app_smtp` and links use `AppSettings.url_options`.
- Tools on the dev machine: `rsvg-convert`, ImageMagick and `vips` are
  installed; OpenSSL 3.6 (HKDF, P-256 ECDH/ECDSA, AES-128-GCM all present).

## 2. Decisions (don't relitigate)

1. **PWA + Web Push, not native apps.**
2. **One notifier, several channels.** The four broadcast blocks become one
   call: `Notifier.notify(user, category:, title:, body:, path:, household:,
   tag:, urgent: false)`. It shows an in-page toast in open tabs, queues a
   push per subscribed device, and queues an email, each according to the
   user's settings (Phase 4).
3. **Dependency-free Web Push, no gem.** Write `lib/web_push/` (RFC 8030
   delivery, RFC 8291 `aes128gcm`, RFC 8292 VAPID ES256 JWT) on OpenSSL +
   `Net::HTTP`, tested in `test/lib` like `lib/web_authn`, including the
   RFC 8291 appendix known-answer vector. No `web-push` gem fallback.
4. **Push endpoints are allowlisted, not resolved-and-checked.** Only
   `https` URLs whose host is a known push service:
   `fcm.googleapis.com`, `*.push.apple.com`, `*.notify.windows.com`,
   `updates.push.services.mozilla.com` (plus `push.services.mozilla.com`).
   Anything else is rejected at subscribe time and again at send time.
   Resolving DNS and refusing private addresses has a rebinding race; an
   allowlist is simpler and stronger.
5. **No duplicate notifications, no focus guessing.** The service worker
   **always** calls `showNotification` for a push (iOS revokes subscriptions
   that don't; Chrome shows its own generic notice anyway). The old in-tab
   `new Notification(...)` path is removed. Open tabs get a small in-page
   toast from the existing Turbo stream instead. A focused tab may see both
   the toast and the system notification; that's acceptable and consistent.
6. **Quiet hours drop non-urgent pushes; they aren't held or summarised.**
   Urgent ones (a clash request waiting for your OK) always go through.
   Quiet hours don't affect email (it doesn't buzz).
7. **Email sends one message per update**, immediately (through Solid Queue),
   except the to-do reminder, which is one morning digest. No batching or
   throttling in this round; email defaults are conservative instead (see
   Phase 4). Every email has a one-click unsubscribe for its category.
8. **Settings are per person, not per household.** Someone in two households
   has one set of choices. Each notification names its household and its
   link switches to that household on open.
9. **Icons are generated once on the dev machine and committed** (from
   `public/icon.svg` with `rsvg-convert`/`magick`). No image gem, nothing at
   runtime.
10. **Docs ship with each phase**: README and AGENTS.md (new files, tables,
    env vars, the "no Web Push" gotcha) are updated in the phase that
    changes them, not saved for the end.

## 3. Phased work

Each phase ends with `bin/rails test` green, Brakeman and rubocop clean, and a
short manual check. Commit per phase on a feature branch. Follow AGENTS.md:
tokens-only CSS, reuse the class vocabulary, household scoping on every
query, no user text interpolated into HTML, Stimulus controllers registered
in `app/javascript/controllers/index.js`, icons in `IconsHelper::ICONS`.

### Phase 1: Installable app shell

- `PwaController` of our own (inherits `ActionController::Base` directly,
  so no setup gate, no Devise, no household context), with `manifest` and
  `service_worker` actions rendering `app/views/pwa/*`. Routes
  `get "manifest.webmanifest"` and `get "service-worker.js"`. Responses carry
  `Cache-Control: no-cache` so updates ship past Thruster and browsers. Use
  our own controller because the manifest needs `AppSettings.app_name`.
- Layouts: `<link rel="manifest">` in `application` (not `wall`: the wall
  iPad is a bookmark, not an install); `<meta name="theme-color">` with light
  and dark `media` variants matching the `--bg`/nav tokens (the values are
  copied from the token block, the one allowed exception, with a comment
  pointing back to it); `viewport-fit=cover`.
- Manifest: `name`/`short_name` from `app_name` (short name capped for iOS),
  a real `description`, `id: "/"`, `start_url: "/?source=pwa"`, `scope: "/"`,
  `display: "standalone"`, `theme_color`/`background_color` matching tokens.
- Icons: `icon-192.png`, `icon-512.png`, `icon-maskable-512.png` (mark
  inside the 80% safe zone on a solid background), `apple-touch-icon.png`
  (180px, no transparency). Layout's apple-touch-icon points at the 180px.
- Service worker, small and safe: versioned constant; precache only
  `/offline.html` (new, in `public/`, inline CSS, light/dark via
  `prefers-color-scheme`); network-only for everything, falling back to the
  offline page for failed **navigations** only. Never caches HTML, `/cable`,
  `/h/*` or Turbo responses. `skipWaiting` + `clients.claim` on install /
  activate; old caches deleted on activate.
- Register from `application.js` after `load`, only if
  `navigator.serviceWorker` exists and `isSecureContext`. The wall layout
  doesn't load it.
- No offline action queue. Offline means the offline page, honestly.
- Tests: manifest and worker served signed-out, before setup, with the right
  content types and `no-cache`; manifest JSON parses with the required keys
  and icon sizes; layout has the link and meta tags; wall doesn't.
- Manual: Chrome DevTools > Application > Manifest shows installable, no
  errors; going offline shows the offline page.

### Phase 2: Push plumbing (server)

- Migration `push_subscriptions`: `user_id` (FK, index), `endpoint` (text,
  unique), `p256dh`, `auth` (both `encrypts`), `user_agent`,
  `last_used_at`, `last_error`, `failed_at`, timestamps. `User has_many`.
- VAPID keys: P-256 keypair generated on first use into
  `storage/.vapid_key` (like `.secret_key_base`), `VAPID_PRIVATE_KEY` /
  `VAPID_PUBLIC_KEY` ENV override. Never in git or the DB. `rake push:keys`
  prints the public key. VAPID `sub` is `mailto:` the mail-from address, else
  `APP_URL`.
- `lib/web_push/`:
  - `Vapid`: ES256 JWT (raw r||s signature, not DER), 12h expiry, `aud` from
    the endpoint origin; header `Authorization: vapid t=..., k=...`.
  - `Encryption`: RFC 8291 (ECDH with an ephemeral key, HKDF with the
    `WebPush: info` and `Content-Encoding: aes128gcm` infos, single 4096-byte
    record, `0x02` delimiter padding).
  - `Client`: POST with `TTL`, `Urgency`, `Topic`, `Content-Encoding:
    aes128gcm`; checks the endpoint against the allowlist (decision 4);
    returns `ok` / `gone` (404, 410) / `retry` (429, 5xx, timeouts) /
    `failed`.
- `PushSubscriptionsController` (`create`, `destroy`, `test`), signed in,
  scoped to `current_user`. `create` upserts by endpoint and **re-homes** an
  existing endpoint to the current user (shared phone, new sign-in).
  Rate-limited like the password resets. Signing out doesn't delete the
  subscription (the browser keeps it) but the next sign-in re-homes it.
- `SendPushJob(subscription_id, payload, urgency:, ttl:)` on `background`:
  `gone` deletes the subscription; `retry` retries with backoff (3 tries);
  other failures set `last_error`/`failed_at` and stop. Never raises into a
  request.
- `Notifier` (decision 2), push and toast channels only in this phase (every
  category on, as today). Payload: `title`, `body`, `path` (same-origin,
  starts with `/`, carries `?household=<id>` so the tap switches household),
  `tag`, `icon`, `badge`. Private items use `Task#title_for`, so a private
  title never reaches a lock screen.
- `ApplicationController`: honour a `household` param that names one of the
  user's households by switching `session[:current_household_id]` (then
  redirect to the clean URL). Non-members: ignored.
- Replace the four broadcast blocks with `Notifier.notify` calls, each with
  its category (Phase 4's list) and `urgent:` where it's a clash request.
- Tests: RFC 8291 vector, VAPID signature verifies with the public key, job
  deletes on 410 and retries on 503, allowlist rejects other hosts and
  `http`, controller scoping and re-homing, private-title redaction in the
  payload, household switch from the param.

### Phase 3: Push client and devices

- Service worker:
  - `push`: parse JSON; on any error show a generic "You have an update";
    always `showNotification` (decision 5), with `tag` and `renotify`.
  - `notificationclick`: validate `data.path` is same-origin and starts with
    `/`; focus an open window and navigate it, else `openWindow`.
  - `pushsubscriptionchange`: resubscribe and POST the new subscription.
- Remove `notification_controller.js`'s `new Notification(...)`; the
  `shared/_notification` partial now renders an in-page toast (reuse
  `flash-stack`/`flash-notice` styling, auto-dismiss).
- Replace `notifications_controller.js` with a `push` controller showing one
  of five states:
  1. unsupported browser;
  2. iOS, not installed (iOS + not `display-mode: standalone` + no
     `PushManager`): "Tap Share, then Add to Home Screen, then open it from
     your Home Screen and turn notifications on";
  3. permission `default`: **Turn on notifications** button (user gesture,
     never auto-prompts);
  4. permission `denied`: how to re-enable in system settings;
  5. on: shown as on, with **Send a test**.
  Subscribes with `userVisibleOnly: true` and the public key from a data
  attribute; POSTs the subscription. On every app load it checks that the
  browser's subscription is known to the server and re-posts it if not
  (self-healing after a key loss or a re-home).
- The dashboard/pet banner stays as a nudge that links to the Notifications
  page (Phase 4) instead of prompting itself; it hides once this device is
  subscribed.
- Device list and test button land on the Notifications page (Phase 4); in
  this phase they can sit in a temporary `account-section` on the account
  page if Phase 4 isn't shipped together.
- Tests: controller flow with a stubbed `Client`. JS verified by hand.
- Manual: desktop Chrome on localhost first, then a real Android phone, then
  a real iPhone (needs the real domain, owner step 1).

### Phase 4: Notification settings screen (push and/or email per category)

A page where each person decides how they hear about each kind of update.

#### Categories

| Key | Label on screen | What sends it | Urgent | Push default | Email default |
| --- | --- | --- | --- | --- | --- |
| `assigned` | Things for me | Someone gives you an item, or asks you to take one that clashes with your schedule | clash requests | on | on |
| `replies` | Answers to my requests | Someone accepts or declines an item you made for them | no | on | off |
| `task_updates` | Changes to my items | An item you're on, or following up, is started, done or skipped | no | on | off |
| `pets` | Pets I follow | A pet you follow is moved or fed | no | on | off |
| `event_reminders` | Event reminders | An event you've accepted starts soon (Phase 5) | no | on | off |
| `todo_digest` | Today's to-dos | One morning list of to-dos due today (Phase 5) | no | off | off |

Email defaults are mostly off because email sends one message per update
(decision 7); `assigned` defaults on so people who never install still hear
about the things that need them. Owner can change these defaults (owner
step 5). The pet row still only covers pets you follow: following a pet
(`PetSubscription`) picks *which* pets, this row picks *how*.

#### Data

- `notification_preferences`: `user_id` (FK), `category` (string, validated
  against `NotificationPreference::CATEGORIES`), `push` (bool), `email`
  (bool), timestamps; unique index on `[user_id, category]`. A missing row
  means the defaults above, so existing users need no backfill and new
  categories get their defaults automatically.
- On `users`: `reminder_lead_minutes` (integer, default 15; 5/15/30/60),
  `digest_hour` (integer, default 7), `quiet_hours_start` /
  `quiet_hours_end` (integer minutes after midnight, nullable = off),
  `notifications_paused_until` (datetime, nullable).
- `User#notification_preference(category)` returns the row or an unsaved one
  with defaults. `NotificationPreference.matrix_for(user)` returns all
  categories in display order for the form.

#### Screen: `/account/notifications`

Route `resource :notifications, only: [:show, :update]` in the `account`
namespace (`Account::NotificationsController < Account::BaseController`).
Linked from the user menu (bell icon, "Notifications"), from the account page,
and from the dashboard/pet nudge banner. Sections, top to bottom, using
existing classes (`page-header`, `account-section`, `form-card`,
`table-wrap`, `inline-check`, `form-hint`, `form-actions`, `btn`):

1. **This device**: the Phase 3 `push` controller's panel (turn on, iOS
   steps, blocked, or on + **Send a test**).
2. **What you hear about**: one form, a table:

   ```
                              Push    Email
   Things for me              [x]     [x]
     New items for you and requests that need your OK
   Answers to my requests     [x]     [ ]
     When someone accepts or declines something you made
   Changes to my items        [x]     [ ]
   Pets I follow              [x]     [ ]
   Event reminders            [x]     [ ]    15 minutes before ▾
   Today's to-dos             [ ]     [ ]    at 7:00 ▾
   ```

   - Each checkbox has an accessible name ("Push: Things for me"), via a
     `visually-hidden` label, since the column header alone isn't announced
     per cell everywhere. The row label is a `th scope="row"`.
   - The Email column header shows where it goes ("Email to
     jo@example.com"), so people know which address.
   - The reminder lead time and digest hour are selects in their rows.
   - The table must fit at 320px wide: descriptions wrap under the label,
     the two checkbox columns stay narrow. No horizontal scroll.
   - One **Save** button; redirect back with a notice. No autosave, because
     a half-ticked matrix shouldn't apply as you click.
3. **Quiet hours and pause**:
   - Quiet hours: off, or from/to time selects. Hint: "No pushes
     between these times, except requests that need your OK. Email isn't
     affected." Times are in the household's time zone,
     the same clock as the rest of the app.
   - Pause: "Pause pushes for 1 hour / 8 hours / 1 day" buttons, or "Paused
     until 18:00. Resume now" when paused.
4. **Your devices**: each subscribed device (from `user_agent`: "iPhone ·
   Safari", "Android · Chrome", "Windows · Edge"), last used, an error
   marker if its last send failed, and **Remove**. "This device" is marked.

States the screen must handle:

- **Email not set up on the server** (`!AppSettings.smtp_configured?`): the
  Email column's checkboxes are `disabled` with a hint "Email isn't set up on
  this server" (admins also get a link to Admin > Settings). The update
  action must **not touch** stored `email` values in this state (disabled
  inputs don't submit, so treating them as unticked would wipe everyone's
  email choices).
- **No devices subscribed**: the Push column still saves, with a hint "None
  of your devices get pushes yet. Turn them on above, on each phone."
- **Push unavailable on the server** (no VAPID key could be generated): Push
  column disabled with a hint; same don't-touch rule.

Controller rules: `update` permits only known categories and the two
booleans each, plus the scalar settings within their allowed values; acts on
`current_user` only (never a user id from params; admins don't manage other
people's notifications, like sign-in security).

#### Delivery

- `Notifier.notify` looks up the preference for `category`, then:
  - toast: always, to open tabs;
  - push: if `push` is on, not paused, and (`urgent` or outside quiet hours):
    a `SendPushJob` per subscription;
  - email: if `email` is on and SMTP is configured:
    `NotificationMailer.update(user, category:, ...).deliver_later`.
- `NotificationMailer` (html + text): subject "[Household] title", the body
  line, a button to the item, a footer saying why they got it ("You get
  emails about *Things for me*") with **Change notification settings** and
  **Unsubscribe from these emails**. Private items use `title_for`. All links
  from `AppSettings.url_options`, never the request host.
- Unsubscribe: `GET`/`POST /notifications/unsubscribe/:token`, a
  `signed_id`-style token (`Rails.application.message_verifier`, purpose
  `:unsubscribe`, carrying user id + category). No sign-in needed. GET shows a
  confirm page with one button (mail scanners prefetch GETs); POST flips that
  category's `email` off. Also send `List-Unsubscribe` and
  `List-Unsubscribe-Post: List-Unsubscribe=One-Click` headers (RFC 8058)
  pointing at the POST, so mail apps show their own unsubscribe button.

#### Tests

- Defaults when no row exists; saving the matrix creates/updates rows.
- Unknown categories and other users are ignored; scalar values outside the
  allowed set are rejected.
- SMTP not configured: email values survive an update untouched; push
  likewise when VAPID is unavailable.
- `Notifier`: push only, email only, both, neither; pause; quiet hours at
  both boundaries and across midnight, in the household time zone; urgent
  bypasses quiet hours.
- Mailer: private title redacted, links use `url_options`, headers present.
- Unsubscribe: GET doesn't change anything, POST turns off only that
  category, tampered token is rejected, works signed out.

### Phase 5: Reminders (notifications on the clock)

- A recurring job next to `ScheduleTickJob` (every minute):
  - **Event reminders**: events starting within each user's
    `reminder_lead_minutes`, for **accepted** assignees only, category
    `event_reminders`.
  - **To-do digest**: at each user's `digest_hour` in the household time
    zone, one notification listing undone to-dos due today, category
    `todo_digest`. Skipped if there are none.
- Idempotency: `reminders_sent` with a unique index on
  `(user_id, task_id, kind, occurrence_starts_at)` (digest uses the date and
  no task). Recurring events key on the occurrence, not the task. Insert
  first; only notify if the insert succeeded.
- Private items use `title_for`; declined or pending assignments get nothing;
  household time zone throughout.
- Not built until asked: "pet not fed by…" nudges.
- Tests with `travel_to`: exactly N minutes before, double tick, recurring
  occurrence, declined/pending assignee, lead-time change, DST change day,
  digest with nothing due.

### Folded in from the old hardening phase

- **Admin > Settings** gets a small Notifications block: push configured
  (and the public key), number of subscribed devices, last send error, and
  whether email is available. Lets the owner diagnose without logs.
- Losing `storage/.vapid_key` invalidates every subscription; the
  self-healing check re-subscribes each device next time it opens the app.
  Documented in README.
- Invitation email gets the one-time phone steps (see owner step 7).

## 4. Out of scope for this round

- **Phone UX pass** (bottom tab bar, safe-area insets, 44px targets, 16px
  inputs, `visibilitychange` reconnect). Its own project after this ships;
  `viewport-fit=cover` from Phase 1 is the only piece done now, and it needs
  a check that nothing sits under the notch.
- **Batched or throttled email** (an hourly roundup instead of one email per
  update). Revisit if anyone turns on email for pets and regrets it.
- **"Hide details on lock screen"** option. Easy to add later as a user
  column the payload builder checks.
- Offline action queues.

## 5. Test plan summary

| Layer | How |
| --- | --- |
| Encryption and VAPID | Known-answer vectors in `test/lib` |
| Push delivery | Stubbed `WebPush::Client`; job tests for 410/503 |
| Settings and routing | Controller and `Notifier` tests per channel and category |
| Email | Mailer tests; unsubscribe integration tests |
| Reminders | Model/job tests with `travel_to` |
| Install and push on devices | Manual, real hardware (below) |

Manual device checklist (Android Chrome and iPhone Safari):

1. Open the site, sign in, install (Install prompt, or Share > Add to Home
   Screen). Icon and name look right.
2. Open from the icon: no browser chrome, status bar colour right in light
   and dark.
3. Notifications page: turn on, send a test. Arrives with the app open,
   in the background and with the phone locked.
4. Another account assigns you an item: push arrives, tap opens it, in the
   right household.
5. Untick Push for that category: next one doesn't arrive. Tick Email:
   email arrives; its unsubscribe link works.
6. Quiet hours covering now: a pet feed doesn't push, a clash request does.
7. Wi-Fi off: offline page, not a blank screen. On again: recovers.
8. Remove the device on the Notifications page: pushes stop. Turn back on:
   they resume.
9. Sign out, sign in as someone else on the same phone: the first person's
   pushes stop arriving there.

## 6. What you (the owner) need to do

1. **Real domain with HTTPS** before testing on phones (localhost is enough
   for building and desktop testing). Set `proxy.host` and `APP_URL` in
   `config/deploy.yml`, point DNS, confirm the Let's Encrypt cert. Phones and
   the wall iPad use this address; passkeys are bound to it.
2. **Deploy once and confirm `/up`** over https before testing push.
3. **Approve the icon.** The agent generates the PNGs from
   `public/icon.svg`. If that isn't the final mark, supply an SVG (or a
   1024px PNG) with breathing room around it.
4. **App name under the icon**: under about 12 characters or iOS truncates
   it. Currently "FamilyStatus" in the manifest vs "family-status" in the app.
5. **Check the defaults** in the Phase 4 category table (push on for all but
   the to-do digest; email on only for "Things for me"; reminders 15 minutes
   before; digest at 7:00; quiet hours off).
6. **SMTP**, if you want the Email column to work: Admin > Settings, with a
   sender your domain is allowed to send from (SPF/DKIM) or mail lands in
   spam. Without it the column shows as unavailable.
7. **Real phones**: Android with Chrome, and an iPhone on **iOS 16.4+**,
   installed to the Home Screen (Safari tabs can't receive push).
8. **Tell the family the one-time steps.** iPhone: open the link in Safari,
   Share, Add to Home Screen, open from the icon, Notifications page, turn
   on. Android: open in Chrome, Install, then turn on.
9. **Back up `storage/`** (database and VAPID key).
10. **Review each phase.** Phase 1 is safe alone. Phases 2–4 should ship
    together (push without settings would over-notify). Phase 5 can follow.

## 7. Risks

- **iOS is the weak link**: install friction and quirks. The iOS steps in
  the push panel and the email column are the mitigation.
- **Over-notifying** gets the app muted. Settings ship with push, not after.
- **Email volume**: one per update can be a lot for pets; defaults are off
  and every email has one-click unsubscribe.
- **Subscription rot**: 404/410 deletes; the client re-registers itself.
- **Service worker caching bugs**: the worker caches one static page, is
  served `no-cache`, and takes over immediately.
- **SQLite, one instance**: all sends go through Solid Queue jobs, never in
  the request or an `after_commit` critical path.
- **Privacy**: private items stay redacted (`title_for`) in pushes and
  emails alike.
- **Several households**: every notification names its household and its
  link switches to it.
