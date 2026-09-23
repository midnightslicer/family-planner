# AGENTS.md

Guide for AI assistants and humans working in this repo.

## What this is

**family-status**: a multi-household family status board on Rails 8.1 + SQLite.
Each person has their own Devise account; accounts join **only via email
invitation** (no open signup). Members manage household-scoped tasks (including
recurring ones), and everyone sees a live auto-updating dashboard of who's busy.
A public wall view (`GET /h/:dashboard_token`, no auth) is meant for a
wall-mounted iPad / browser home page. Deploy: Docker + Kamal.

Stack: Rails 8.1, propshaft (raw CSS, no CSS framework), esbuild via
jsbundling (`npm run build`), SQLite at `storage/production.sqlite3`,
Puma, letter_opener in dev, SMTP from Settings in production.

## Running locally

```sh
bin/rails db:prepare        # create/migrate the database
bin/rails server            # app on http://localhost:3000
bin/dev                     # or: npm run build for JS + rails server
```

First visit redirects to the `/setup` wizard (app settings incl. SMTP, then the
first admin account, the only user creation path besides invitations).

## Where things live

- `app/models/`: `User` (Devise + `handle`, `color`, `admin`), `Household`
  (`dashboard_token` for the public wall), `HouseholdMembership`, `Invitation`
  (SHA-256 token digest, expiry), `Task` (status enum: `planned`,
  `in_progress`, `undone`, `completed`; recurrence), `Setting` (key/value),
  and `TaskBroadcaster`, the in-memory SSE registry keyed by household id.
- `app/controllers/application_controller.rb`: `Current.household` scoping
  (`set_current_household` from `session[:current_household_id]`) and the
  first-run gate (`User.none?` → redirect to `/setup`).
- `app/controllers/households_controller.rb#stream`: the SSE endpoint
  (`GET /households/:id/stream`), plus `switch` (`POST /switch_household`).
- `app/controllers/admin/`: admin-only area (settings, households,
  invitations, profiles). `app/controllers/walls_controller.rb`: public wall.
- `config/initializers/mailer.rb`: SMTP configured from `Setting.get(...)`;
  `Setting`'s `value` column is encrypted (`encrypts :value`), covering
  `smtp_password`. Never handle it in plaintext.
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
    and `custom-color`.
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
  production shipping (Kamal 3, server on port 3000).

## Conventions

- **Household scoping is mandatory** on every task query: filter by
  `Current.household.id` (or the token household on the wall). Non-members get
  404, not 403.
- **Invitations are the only join path.** `RegistrationsController` blocks
  open signup; users are created through `Invitation#join` or the setup wizard
  (first admin only).
- Status colors: blue planned, amber in_progress, gray undone, green
  completed, set via `--status-*` custom properties in application.css.
- Per-user color arrives as inline `--user-color` / `--user-fg` on
  `.person-card`; accents use `color-mix(...)`, so don't hardcode hexes.

## Gotchas

- `config/master.key` is **gitignored and required to boot** (it decrypts
  `credentials.yml.enc` and ActiveRecord encryption keys). Never commit it;
  copy it manually to servers via `RAILS_MASTER_KEY`.
- Dev mail goes to letter_opener (opens in browser); no SMTP needed locally.
- The SSE subscriber registry (`TaskBroadcaster`) is **in-memory** and assumes a
  single app instance. Multiple replicas need Redis pub/sub instead.
- Notifications require a secure context; on LAN http they silently no-op.
- CSS has no build step; edit `app/assets/stylesheets/*.css` directly.
  propshaft fingerprints them at serve time.

## Testing

```sh
bin/rails test              # unit/integration tests
docker compose up --build   # smoke: wizard reachable on localhost:3000
```