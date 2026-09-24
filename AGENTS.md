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
  card's tasks in one query; `broadcast_member_cards`), `HouseholdMembership`,
  `Invitation` (SHA-256 token digest, expiry, optional email, atomic
  `accept!`), `Task` (status enum: `planned`, `in_progress`, `undone`,
  `completed`; recurrence; broadcasts cards and assignee notifications after
  commit), `Setting` (encrypted key/value, cached per request in `Current`),
  `AppSettings` (app name/URL, SMTP and setup code, Setting then ENV), and
  `GettingStarted` (the dashboard checklist).
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
  - shell: `nav`/`nav-inner`/`nav-brand`/`nav-links`/`nav-user`/`nav-user-name`,
    `container`, `page-header`, `page-intro`, `household-switch`
  - messages: `flash-stack` (the always-present `#flash` container that
    `TasksController` prepends into), `flash-notice`, `flash-alert`
  - forms: `form-card`, `form-field` (also on a `fieldset`), `form-actions`,
    `btn` + `btn-primary`/`btn-danger`/`btn-quiet`/`btn-small`, `devise-links`
  - tables: `table-wrap` (scroll container) + bare `table`, `table-actions`
  - components: `dashboard-grid`, `person-card` > `person-identity` >
    `person-avatar` + `person-meta` > `person-name` + `person-handle`, then
    `person-status`; `status-chip status-*`; `task-list`, `task-card`,
    `task-title`, `task-meta`, `task-recurrence`, `task-actions`;
    `invite-banner` + `invite-actions`; `color-picker` > `palette` > `swatch`
    and `custom-color`; `checklist` > `checklist-header` + `checklist-steps`
    > `checklist-step` (`is-done`) > `checklist-mark` + `checklist-body`.
  - account & auth: `account-section`, `admin-tabs`, `copy-field`,
    `inline-form`, `inline-check`, `code-input`, `help-details`,
    `passkey-signin`, `passkey-choice`, `passkey-hint`, `passkey-add`,
    `setup-steps`, `qr-frame` > `qr-code` (`qr-light`/`qr-dark`, coloured by
    the `--qr-*` tokens), `secret-key`, `recovery-codes`.
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

- **Household scoping is mandatory** on every task query: filter by
  `Current.household.id` (or the token household on the wall). Non-members get
  404, not 403.
- **Invitations are the only join path.** Devise `:registerable` is off (no
  `/users/sign_up`); accounts come from `InvitationsController#join` or the
  setup wizard (first admin only).
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
- Per-user color arrives as inline `--user-color` / `--user-fg` on
  `.person-card`; accents use `color-mix(...)`, so don't hardcode hexes.

## Gotchas

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