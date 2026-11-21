# AGENTS.md

Guide for AI assistants and humans working in this repo.

## What this is

**family-status**: a multi-household family status board on Rails 8.1 + SQLite.
Each person has their own Devise account; accounts join **only via email
invitation** (no open signup). Members manage household-scoped tasks (including
recurring ones), and everyone sees a live auto-updating dashboard of who's busy.
A public wall view (`GET /h/:dashboard_token`, no auth) is meant for a
wall-mounted iPad / browser home page. Sign-in: passwords, passkeys
(WebAuthn), and optional TOTP two-step verification. Deploy: Docker + Kamal.

Stack: Rails 8.1, propshaft (raw CSS, no CSS framework), esbuild via
jsbundling (`npm run build`), SQLite at `storage/production.sqlite3`,
Puma behind Thruster, letter_opener in dev, SMTP from Settings (or `SMTP_*`
env) in production. Live updates are Turbo Streams over Action Cable
(solid_cable in production).

## Running locally

```sh
bin/rails db:prepare        # create/migrate the database
bin/rails server            # app on http://localhost:3000
bin/dev                     # or: npm run build for JS + rails server
```

First visit redirects to `/setup`: one page that names the household and
creates the first admin (the only account creation path besides invitations).
Outside development it first asks for a setup code printed in the server log
at boot (`bin/rails setup:code` prints it again), so whoever finds a fresh
server can't claim it. SMTP is optional and lives in Admin > Settings.

## Where things live

- `app/models/`: `User` (Devise + `handle`, `color`, `admin`, TOTP fields,
  `webauthn_id`), `Passkey` (WebAuthn public keys), `Household`
  (`dashboard_token` for the public wall; `member_statuses` loads every
  card's tasks in one query; `broadcast_member_cards`), `HouseholdMembership` (`home`: the house, a household location, they
  live in; `Household#by_house` groups people and pets by it for the
  board),
  `Invitation` (SHA-256 token digest, expiry, optional email, atomic
  `accept!`), `Task` (a schedule item: a *to-do* with no time, optionally
  `due_on` a day, or an *event* with `starts_at`/`ends_at` and a `place`;
  `availability` free/text/busy says how reachable the person is while it's
  on; `private` items show only "Busy" to anyone but their assignee and
  creator (`visible_to?`, `title_for`; a nil viewer, as on person cards and
  the wall, never sees them); an event whose `place` names a household
  location links to it (`location_id`), and while it's on that's where the
  person shows as being (`whereabouts`, the `:at` in member statuses); status enum `planned`, `in_progress`, `undone`, `completed`;
  `started_at` stamps "doing it now"; recurrence, with `roll_forward!`
  moving ended recurring events on; broadcasts cards and assignee
  notifications after commit), `TaskAssignment` (who an item is for: `accepted`,
  `pending` when it clashed with their schedule, or `declined`; several
  people can share one item, and none means "for anyone";
  `conflicts_for` checks their events and work hours), `TaskAssigner`
  (places people on save, notifies them, and writes the flash that says
  what happened), `PersonSchedule` (one person's now / to-dos / today /
  later / done / waiting for their OK / following up), `Setting` (encrypted key/value, cached per request in `Current`),
  `AppSettings` (app name/URL, SMTP and setup code, Setting then ENV),
  `GettingStarted` (the dashboard checklist), and the pets feature:
  `Location` (a place: house/yard/pasture/pool/other, with a photo),
  `Pet` (species, birthday, `meals_per_day`, `feeding_notes`, `home` =
  where it sleeps; `Pet.statuses` loads every card's state in a few
  queries into `PetStatus`), `LocationReport` (polymorphic `subject`: Pet or
  User; the newest per subject is where they are; `latest_for`), `Feeding`,
  `PetSubscription` (follow a pet), and `PetCheckIn`, the form object behind
  both batch flows ("Report where" and "Feed": pick pets, maybe a place,
  comment) which also notifies followers. `concerns/small_photo.rb`
  (`small_photo :avatar`) is the one way to give a model a photo.
- `lib/`: dependency-free security code with its own tests in `test/lib`:
  `Totp` (RFC 6238), `QrCode` (inline SVG for the 2FA setup page), and
  `WebAuthn::RelyingParty`/`Cbor`/`CoseKey` (passkey ceremonies on OpenSSL).
  There are no auth gems beyond Devise; keep it that way unless the lockfile
  can be regenerated.
- `app/controllers/application_controller.rb`: first-run gate, `Current.user`
  / `Current.household` (from `session[:current_household_id]`), and the
  passkey ceremony helpers (`relying_party`, `start_ceremony`,
  `finish_ceremony`, `credential_param`).
- `app/controllers/users/`: Devise sessions (password, then
  `two_factor#show` if TOTP is on), passkey sign-in, rate-limited resets.
  `app/controllers/account/`: every member's profile, password, passkeys,
  2FA and recovery codes. `concerns/account_signup.rb`: passkey-or-password
  sign-up shared by setup and invitations.
- Pets & people: `PetsController`, `PetLocationsController` (GET/POST
  `/pets/where`), `FeedingsController` (`/pets/feed`; a card's one-tap Fed
  button posts `quick=1` and stays on the page), `LocationsController`,
  `PeopleController` (`show` redirects to the person's day on the
  Schedule, which is their profile; `locate` sets *your own* location only,
  from the "I'm at" chips: it never reads a person from params),
  `PetSubscriptionsController`. They
  include `concerns/household_scoped.rb` (sign-in, household, creator-or-admin
  deletes, whitelisted `return_to`). Anyone in the household can add and edit
  pets and locations; deleting is for whoever added it or an admin.
- `app/controllers/admin/`: admin-only area (households + wall link and
  members, invitations, people, settings). `walls_controller.rb`: public wall.
- `config/initializers/mailer.rb` + `app/mailers/app_mail_delivery.rb`: SMTP
  is read at send time (`:app_smtp` delivery method), so settings changes
  apply without a restart; email links use `AppSettings.url_options`. The
  settings page never renders the saved SMTP password.
- `app/assets/stylesheets/application.css`: all app styling, plus
  `kiosk.css`, whose every rule is scoped to `body.kiosk` (the wall view).
  Both are served by Propshaft; `stylesheet_link_tag :app` in the layouts
  picks up every file in the directory. The class vocabulary is the contract
  with the views — reuse it, don't invent new classes:
  - shell: `nav`/`nav-inner`/`nav-brand`/`nav-links`/`nav-user`, the account
    menu `user-menu` > `user-menu-button` (> `nav-avatar`) + `user-menu-panel`
    (> `user-menu-header`), closed by the `menu` Stimulus controller,
    `container`, `page-header`, `page-intro`, `household-switch`
  - messages: `flash-stack` (the always-present `#flash` container that
    flashes render into), `flash-notice`, `flash-alert`
  - forms: `form-card`, `form-field` (also on a `fieldset`), `form-actions`,
    `btn` + `btn-primary`/`btn-danger`/`btn-quiet`/`btn-small`, `devise-links`
  - tables: `table-wrap` (scroll container) + bare `table`, `table-actions`
  - components: `dashboard-grid`, `person-card` > `person-identity` >
    `person-avatar` + `person-meta` > `person-name` + `person-handle`, then
    `person-status` (> `person-now`), `person-next`; `status-chip status-*`
    and `status-chip avail-free|avail-text|avail-busy` (availability);
    `task-meta`, `task-recurrence`, `task-actions`; the schedule:
    `people-switch`, `quick-add` (> `quick-add-row`, `quick-add-more`),
    `now-banner`, `schedule-columns`, `sched-list` > `sched-item`
    (`sched-todo`/`sched-event`, `is-<status>`, `is-past`, `is-now`) >
    `sched-check` or `sched-time`, `sched-body` (`sched-title`, `sched-meta`,
    `sched-notes`), `sched-actions`; `done-today`; `family-grid` >
    `family-column` (`family-person`, `family-now`, `family-day`,
    `family-todos`); `avail-options`, `form-row-3`, `form-hint`;
    `invite-banner` + `invite-actions`; `color-picker` > `palette` > `swatch`
    and `custom-color`; `avatar-picker` > `avatar-preview` + `avatar-controls`, and the
    `crop-dialog` (`crop-hint`, `crop-stage` canvas, `crop-zoom`); `checklist` > `checklist-header` + `checklist-steps`
    > `checklist-step` (`is-done`) > `checklist-mark` + `checklist-body`.
  - pets & profiles (the pattern for new features: a card says what's true
    now and puts the next action one tap away; batch actions are "pick
    tiles, then a button that says what will happen"): `header-actions`,
    `section-header`, `empty-state`, `pet-grid` > `pet-card` > `pet-identity`
    + `pet-facts` (`pet-where`, `report-comment`, `pet-fed` > `meal-pips`);
    `person-where`, `birthday-cake`; `profile-header` > `profile-avatar` +
    `profile-heading`; `profile-panels` > `panel` (`panel-wide`);
    `place-now`, `place-photo` (rounded square; discs are for faces),
    `place-grid` > `place-card` > `place-body` + `here-now`; `history` >
    `history-item` > `history-mark` + `history-body`; tile pickers
    `picker-field` > `picker-shortcuts` + `pick-grid` > `pick-tile`
    (`pick-check`, `pick-name`, `pick-meta`, `pick-place`, `pick-add`) driven
    by the `picker` Stimulus controller; `kind-options` > `kind-option`;
    `feeding-notes`, `form-row`, `form-card-wide`, `sticky-actions`,
    `btn-wide`, `danger-zone`. Partials: `shared/_photo_picker`,
    `shared/_pet_picker`, `shared/_location_picker`, `shared/_history`,
    `pets/_pet_card`, `shared/_live`.
  - account & auth: `account-section`, `admin-tabs`, `copy-field`,
    `inline-form`, `inline-check`, `code-input`, `help-details`,
    `passkey-signin`, `passkey-choice`, `passkey-hint`, `passkey-add`,
    `setup-steps`, `qr-frame` > `qr-code` (`qr-light`/`qr-dark`, coloured by
    the `--qr-*` tokens), `secret-key`, `recovery-codes`.
  - icons & motion: `icon(:name)` / `icon_label(:name, "Text")` from
    `IconsHelper` render inline SVG with `icon icon-<name>` (add new icons to
    `IconsHelper::ICONS`); `flash_message` renders a flash with its icon.
    `btn-success` (Done), `btn-icon` (+ `btn-icon-danger`),
    `person-card.is-busy` (pulsing avatar: not free to call),
    `banner-icon`, `checklist-progress` (`--progress`), and `.confetti` from
    the `celebrate` Stimulus controller. Motion uses the `--ease-*`, `--fast`,
    `--medium` tokens; entrance animations use fill-mode `backwards`, never
    `both`, or the held end frame blocks hover transforms.
  - utilities: `visually-hidden`, `btn-block`, `empty-hint`, `section-title`.
    `[hidden]` is forced to `display: none` because `.btn` sets a display.
  `button_to` renders a `<form>`; inside a flex row the wrapping form is set
  to `display: contents` so the button itself lays out. Add new action rows to
  that selector list.
- **Theming is tokens only.** Every colour a component uses comes from a
  custom property on `:root`; light and dark differ solely in the values.
  `@media (prefers-color-scheme: dark)` redefines that token set and nothing
  else — never put a colour rule inside it, and never hard-code a hex outside
  the token block, or one theme will be wrong. `:root` also declares
  `color-scheme: light dark` so the UA-drawn parts follow (scrollbars, the
  datetime picker, checkbox glyphs). `body.kiosk` pins `color-scheme: dark`
  and its own token values, so the wall stays dark whatever the OS says.
- `entrypoint.sh` / `Dockerfile` / `compose.yml` / `config/deploy.yml`:
  production shipping (Kamal 2, Thruster on port 3000 in front of Puma on
  3001, Solid Queue inside Puma). The entrypoint generates
  `storage/.secret_key_base` on first boot when neither `SECRET_KEY_BASE`
  nor `RAILS_MASTER_KEY` is set.

## Conventions

- Items belong to people through `task_assignments`, never a column on
  `tasks`. Only accepted assignments put an item on someone's day, card
  and availability. `Task.for_person(user)` / `for_anyone` are the scopes;
  `Task.create!(assigned_to: user)` is shorthand for one accepted person.
  `follow_up` keeps an item on its creator's list ("Following up") and
  sends them its status changes.
- **Household scoping is mandatory** on every task query: filter by
  `Current.household.id` (or the token household on the wall). Non-members get
  404, not 403.
- **Invitations are the only join path.** Devise `:registerable` is off (no
  `/users/sign_up`); accounts come from `InvitationsController#join` or the
  setup wizard (first admin only).
- **Admins can manage other members' details** (profile, house, work
  schedule, days off) through `concerns/manages_person.rb`: those pages
  act on `managed_person`, yourself unless an admin passes `person_id` for
  a member of the current household (anyone else gets 404).
  `PersonProfilesController` is the admin's "Manage profile" page; the
  profile form (`shared/_profile_form`) and its save (`ProfileUpdate`) are
  shared with the account page. Sign-in security is never managed this way.
- **Checkboxes and radios are drawn by CSS** (`appearance: none`, tick and
  dot as clip-paths in the tokens); toggles that should read as chips put
  the input inside a label with `opacity: 0` (`who-chip`,
  `follow-up-check`, `kind-option`, `pick-tile`).
- **Two-factor must not be bypassable.** `Users::SessionsController#create`
  skips `set_current_context`: Devise enables params authentication for that
  action, so an early `current_user` call would sign the person in before
  the TOTP check. Don't add `current_user` lookups to filters that run there.
- **Links in emails** come from `AppSettings.url_options` (APP_URL or the URL
  saved at setup), never from the request's Host header.
- **Never interpolate user text into HTML strings**; build markup with
  `tag`/`content_tag` or partials (task titles once reached turbo stream
  flashes unescaped).
- Status colors: blue planned, amber in_progress, gray undone, green
  completed, set via `--status-*` custom properties in application.css.
  Availability reuses them: green free, amber text only, red (danger)
  do not disturb.
- The Schedule lives at `/tasks` (`?person=<id>` or `?person=family`).
  Every task action redirects back and the page morphs in place; there are
  no task turbo-stream responses. A card's "now" is computed from the
  clock, so the dashboard and schedule refresh every minute
  (`auto-refresh` interval) and `ScheduleTickJob` (production, every
  minute) broadcasts refreshes when events start or end.
- Per-user color arrives as inline `--user-color` / `--user-fg` on
  `.person-card`; accents use `color-mix(...)`, so don't hardcode hexes.

## Gotchas

- The colour picker's swatches post `user[color]`; the custom hex box posts
  `user[custom_color]`, which wins when filled. Never give the box the name
  `color` again: as the later field it overrode the swatch, so picked
  colours silently didn't save.
- Photos (`User#avatar`, `Pet#photo`, `Location#photo`, Active Storage on
  the `:local` disk service under `storage/`) all go through
  `shared/_photo_picker`: cropped in a `<dialog>` (drag, zoom, arrow keys;
  round mask for faces, square for places), rendered at 256px (480 for
  places) and re-encoded in the browser by `photo_upload_controller.js`,
  which also strips EXIF/GPS. The profile form saves itself after a crop
  (`autosave`); the pet and location forms upload with the rest. Previews must be `data:` URLs: the CSP's img-src
  allows `data:` but not `blob:` (a blob preview silently shows nothing). There
  is no server-side image library, so no variants and analyzers are off;
  `SmallPhoto` only accepts JPEG/PNG/WebP (sniffed, not trusted) up to 2 MB.
  Photo URLs are signed blob links, so the public wall can show them.

- Active Record encryption keys come from credentials if present, otherwise
  they're derived from `SECRET_KEY_BASE` (see `config/application.rb`). So
  `config/master.key` is optional; losing the storage volume's
  `.secret_key_base` makes encrypted settings and TOTP secrets unreadable
  (they read as blank rather than crashing).
- Dev mail goes to letter_opener (opens in browser); no SMTP needed locally.
- Live updates use Turbo Streams: pages subscribe with
  `turbo_stream_from household, :members` (cards) and
  `turbo_stream_from current_user, :notifications`. Stream names are signed,
  which is what authorises the anonymous wall. Broadcasts render
  synchronously in `after_commit` and never raise into the request.
- Pet, location and feeding changes call `Household#broadcast_refresh`
  (a debounced Turbo refresh on `[household, :members]`); pages that show
  them render `shared/_live`, which subscribes and morphs. Person cards still
  get targeted replaces.
- Every request runs on the household's clock: `households.time_zone`
  (Rails zone name, set by an admin on the household page), applied by
  `ApplicationController#use_household_time_zone` with `Time.use_zone`;
  the wall uses its token's household. Work hours, "today", "fed today"
  and every time shown follow it. Until it's set, the browser's own zone
  (the `tz` cookie from `application.js`) is used, then UTC.
- Pet-follow notifications ride the same `[user, :notifications]` stream as
  task notifications, so they only arrive while the app is open somewhere
  (there's no Web Push).
- Passkeys, clipboard and notifications require a secure context; on LAN
  http the UI hides passkeys and falls back to passwords. Passkeys are bound
  to the hostname they were created on.
- SQLite + one container: run a single app instance.
- JS controllers are registered by hand in
  `app/javascript/controllers/index.js` (esbuild, no import map).
- CSS has no build step; edit `app/assets/stylesheets/*.css` directly.
  propshaft fingerprints them at serve time.

## Testing

```sh
bin/rails test              # unit/integration tests
docker compose up --build   # smoke: setup page on localhost:3000, code in the logs
```

`test/support/fake_authenticator.rb` is a software passkey that signs real
WebAuthn responses; `register_passkey` / `sign_in_with_passkey` in
`test_helper.rb` drive the endpoints with it.