# AGENTS.md

Guide for AI assistants and humans working in this repo.

## What this is

**family-status** — a multi-household family status board on Rails 8.1 + SQLite.
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
first admin account — the only user creation path besides invitations).

## Where things live

- `app/models/` — `User` (Devise + `handle`, `color`, `admin`), `Household`
  (`dashboard_token` for the public wall), `HouseholdMembership`, `Invitation`
  (SHA-256 token digest, expiry), `Task` (status enum: `planned`,
  `in_progress`, `undone`, `completed`; recurrence), `Setting` (key/value),
  `TaskBroadcaster` — the in-memory SSE registry keyed by household id.
- `app/controllers/application_controller.rb` — `Current.household` scoping
  (`set_current_household` from `session[:current_household_id]`) and the
  first-run gate (`User.none?` → redirect to `/setup`).
- `app/controllers/households_controller.rb#stream` — the SSE endpoint
  (`GET /households/:id/stream`), plus `switch` (`POST /switch_household`).
- `app/controllers/admin/` — admin-only area (settings, households,
  invitations, profiles). `app/controllers/walls_controller.rb` — public wall.
- `config/initializers/mailer.rb` — SMTP configured from `Setting.get(...)`;
  `Setting`'s `value` column is encrypted (`encrypts :value`), covering
  `smtp_password` — never handle it in plaintext.
- `app/assets/stylesheets/application.css` — all styling; the class vocabulary
  (`person-card`, `status-chip status-*`, `task-card`, `form-card`, `btn`,
  `household-switch`, `invite-banner`, `color-picker`, …) is the contract with
  the views — reuse it, don't invent new classes.
- `entrypoint.sh` / `Dockerfile` / `compose.yml` / `config/deploy.yml` —
  production shipping (Kamal 3, server on port 3000).

## Conventions

- **Household scoping is mandatory** on every task query: filter by
  `Current.household.id` (or the token household on the wall). Non-members get
  404, not 403.
- **Invitations are the only join path.** `RegistrationsController` blocks
  open signup; users are created through `Invitation#join` or the setup wizard
  (first admin only).
- Status colors: blue planned, amber in_progress, gray undone, green
  completed — set via `--status-*` custom properties in application.css.
- Per-user color arrives as inline `--user-color` / `--user-fg` on
  `.person-card`; accents use `color-mix(...)` — don't hardcode hexes.

## Gotchas

- `config/master.key` is **gitignored and required to boot** (it decrypts
  `credentials.yml.enc` and ActiveRecord encryption keys). Never commit it;
  copy it manually to servers via `RAILS_MASTER_KEY`.
- Dev mail goes to letter_opener (opens in browser) — no SMTP needed locally.
- The SSE subscriber registry (`TaskBroadcaster`) is **in-memory** — assumes a
  single app instance. Multiple replicas need Redis pub/sub instead.
- Notifications require a secure context; on LAN http they silently no-op.
- CSS has no build step — edit `app/assets/stylesheets/*.css` directly;
  propshaft fingerprints them at serve time.

## Testing

```sh
bin/rails test              # unit/integration tests
docker compose up --build   # smoke: wizard reachable on localhost:3000
```