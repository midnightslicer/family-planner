# family-status-plan

## Context

Build a multi-household family status app on Ruby on Rails + SQLite: each person logs in with their own account, manages tasks (including recurring ones), and everyone sees a live, auto-updating dashboard of who is busy — ideal for a wall-mounted iPad or the browser home page. First account is created through an initial settings/setup wizard and becomes the admin; all other accounts join only via email invitation. One instance can serve many households; household switchers appear wherever membership is relevant. Deployment is Docker/Kamal, with SMTP wired for password resets, invitations, and future status emails.

## Approach

### Step 0 — Scaffold and deployment base

1. Install Rails: `gem install rails` (Ruby 4.0.7 on this machine; see Assumptions for version contingency).
2. Scaffold the app: `rails new . --database=sqlite3 --javascript=esbuild` in `/home/drh/Work/family-status` (no `--css` flag — the default asset pipeline already ships plain `app/assets/stylesheets/application.css`, exactly the raw-CSS source Step 8 styles).
3. Gems: `devise`; dev/test group gets `letter_opener` (opens sent mail in the browser during development). No other additions.
4. Production database lives in `storage/production.sqlite3` (Rails 8 default layout) so a single Docker volume covers DB + file storage.
5. Shipping artifacts, created in `config/` and repo root:
   - `Dockerfile` — multi-stage: `ruby:4.0-slim` base (contingency: `ruby:3.4-slim` if Rails install fails on 4.0), Node build stage runs the esbuild asset build + `assets:precompile`, final slim image with `storage` dir.
   - `entrypoint.sh` — `bin/rails db:prepare` then `exec "$@"`; `CMD ["bin/rails", "server"]`.
   - `compose.yml` — one service `web`: build the image, volume `storage:/rails/storage`, env from `.env` (dev/homelab path).
   - `config/deploy.yml` — Kamal 3: app name `family-status`, image tag, one `web` server, volume `storage:/rails/storage`, `env` block reading `KAMAL_*` variables (RAILS_MASTER_KEY, SECRET_KEY_BASE not needed; master key only).
   - `.dockerignore` — excludes `storage/`, `tmp/`, `.git`, `node_modules`, `vendor/bundle`.

### Step 1 — Settings, SMTP, mailers

- `Setting` model — single-row key/value store (`key` string unique, `value` text; Rails `HashWithIndifferentAccess` helper `Setting.get("app_name")`). Keys: `app_name`, `smtp_host`, `smtp_port`, `smtp_user`, `smtp_password`, `smtp_from`, `smtp_tls` (bool).
- `smtp_password` stored encrypted via `config.active_record.encryption.primary_key` (generate `bin/rails db:encryption:init` and commit the credentials file per normal Rails practice).
- `config/initializers/mailer.rb`: if `Setting` table exists (rescue `ActiveRecord::NoDatabaseError`/table-missing), configure `ActionMailer::Base.smtp_settings` and `default from:` from Settings; otherwise fall back to `ENV["SMTP_HOST"]` etc. for dev.
- `ApplicationMailer` with the shared HTML/text layout (header: app name; footer: app name + from address).
- Dev: `letter_opener` delivery method; prod: `smtp`.

### Step 2 — Setup wizard and admin

- `User` model: Devise columns plus `handle` (string, unique, index), `display_name` (string), `color` (string, default `"#6366f1"`, validated `/\A#[0-9a-fA-F]{6}\z/`), `admin` (boolean, default false, index).
- `SetupController`: when `User.none?`, root and all pages redirect to `/setup` with a two-step wizard:
  1. **App settings** — app name, SMTP host/port/user/password/from/TLS, and a "Send test email" button that delivers via letter_opener/smtp and reports success/failure inline.
  2. **Admin account** — display name, handle, email, password, color picker; creates the first user with `admin = true`.
- Admin area `AdminController` (namespace `/admin`, `before_action` requiring `current_user.admin`): households list, invitation management, settings form (same fields as wizard step 1 + test email + ability to change admin account's own name/color).
- Color picker UI (shared partial): grid of 20 curated palette colors plus a custom hex input; value stored as 6-char hex. Color surfaces on every element showing that user.

### Step 3 — Households and memberships

- `Household`: `name` (string, not null), `dashboard_token` (string, unique, not null — generated `SecureRandom.hex(16)`), timestamps.
- `HouseholdMembership`: `user_id` + `household_id`, unique composite index on the pair.
- `User has_many :households, through: :household_memberships`, and vice versa.
- `Current.household` via `ActiveSupport::CurrentAttributes`, set in a `before_action` from `session[:current_household_id]`; if missing/stale, fall back to the user's first membership. `switch_household(id)` helper (POST) validates membership and updates the session.
- First-time admin creation also creates their default household from the wizard's app-name step: household name defaults to the app name, editable later in `/admin`.
- Nav header shows a household switcher (native `<select>`) whenever `current_user.households.size > 1`; the select submits `POST /switch_household`. All household-scoped pages re-render after switch.

### Step 4 — Invitations (the only way to join)

- `Invitation`: `email` (string, index), `household_id` (FK), `token` (string, unique, indexed — stored as `Digest::SHA256.hexdigest` of a `SecureRandom.urlsafe_base64(32)` raw value; only the digest persists), `expires_at` (datetime, default now + 7 days), `accepted_at` (datetime, nullable), `invited_by_id` (FK to User).
- Devise `RegistrationsController` overridden: `new`/`create` render a "Join requires an invite" screen unless `User.none?` or a valid unmatched token is supplied via `?token=`.
- Public join page `GET /invitations/:token`: shows app name + inviting user + household; form collects display name, handle, color, password; on submit, creates the user, creates the `HouseholdMembership`, marks `accepted_at`, signs the user in, and sends them to `/dashboard`.
- Token rules: not found/expired/already accepted → friendly error page with a "request a new invite" note (no link target; invites come from the admin).
- Admin invitation form (`/admin/invitations/new`): email + household select + optional short note; creating it sends `InvitationMailer#invite` (link `https://<host>/invitations/<raw token>`), shows a confirmation page with inline resend/copy-link controls. Admin can also see per-invitation status (pending/accepted/expired) and revoke by delete.
- Only site admins can invite, per the requirement. (Household-level roles are not modeled; see Assumptions.)

### Step 5 — Tasks (household-scoped, recurring)

- `Task`: `household_id` (FK, index), `title` (string, not null), `description` (text, nullable), `status` (Rails enum: `planned`, `in_progress`, `undone`, `completed`), `assigned_to_id` (FK User, index — defaults to current user on create), `created_by_id` (FK User, index), `starts_at` (datetime, nullable — set to now when started if nil), `ends_at` (datetime, nullable), `recurrence_interval` (string, nullable: `""`, `"daily"`, `"weekly"`, `"biweekly"`, `"monthly"`), `next_occurrence` (datetime, nullable). All queries scoped by `household_id == Current.household.id`.
- Creation form: title, description, assignee select limited to the household's members (default: current user), starts/ends datetime-local inputs, recurrence select. Validation: assignee must belong to the task's household.
- Status transitions (buttons on each task card; POST actions on the task):
  - planned → in_progress "Start" (sets `starts_at = now` if nil)
  - in_progress → completed "Complete"
  - in_progress → undone "Cancel" (record kept as a history item)
  - Any → completed/undone additionally runs recurrence logic (below).
- Recurrence: on finishing a recurring task, compute next start from `starts_at` (+1 day / +7 / +14 / `Date.next_month` with day-of-month clamping to month length), create a **new** Task copy (status `planned`, same household/assignee/title/etc., fresh timestamps), set the finished task's `next_occurrence = nil`.
- Permissions: household members can create/edit/delete their own tasks; any household member can start/complete/cancel any household task. Non-members get 404.

### Step 6 — Dashboard and live updates

- Authenticated `GET /dashboard` — cards per household member (sorted by display name): color accent, display name + `@handle`, current activity (in-progress task titles with time remaining or next-planned task), "Available" state when idle. Header shows household name + switcher; only tasks of `Current.household`.
- Public wall view `GET /h/:dashboard_token` — identical renderer, **no auth**; scoped to the token's household (invalid token → 404). This is the URL for the iPad kiosk / browser home page. Kiosk stylesheet variant: full-bleed grid, no nav chrome, larger type, `body { overflow: hidden }`.
- Live updates via SSE on `GET /households/:household_id/stream`: `ActionController::Live`, keeps the connection open, writes `data:` lines as JSON `{type: "task_update", task_id: …}` whenever a task in that household is created or changes status. Server side: after every task-save in Step 5 callbacks, broadcast to the household's Redis-less channel list (an in-memory subscriber registry keyed by household id works for a single-server deployment; see Assumptions about multi-instance). Client: `EventSource` on the dashboard and wall pages; on `task_update`, `fetch` the household's current card fragment and swap only the affected card. Visibility pause/resume to save battery on the kiosk.

### Step 7 — Web notifications

- On first authenticated load, request `Notification.permission` (banner with explicit "Enable notifications" button — never auto-pop).
- SSE events (Step 6) also carry `assigned_to` user id and type `new_assignment` / `status_change`; logged-in pages show a system/browser notification when the event concerns the current user ("`@alex` assigned you: Review budget" / "`@sam` completed: Standup"), via `new Notification(title, {body, tag})`.
- Logged-in task pages additionally use Turbo Streams (`turbo_stream.prepend`/`replace`) for same-page live updates; the wall page uses plain DOM patching only.

### Step 8 — Raw CSS styling

- All styling in `app/assets/stylesheets/application.css` (and a `kiosk.css` for the wall view): CSS custom properties for palette + per-user colors (`--user-color` set inline from the user's hex).
- Principles: clean cards with generous padding and rounded corners; status colors — blue planned, amber in_progress, gray undone, green completed; responsive grid `grid-template-columns: repeat(auto-fill, minmax(280px, 1fr))` (naturally 1-2 cols phone, 3-4 desktop); tap targets ≥ 48px; contrast-checked text over user colors (compute luminance for a `--user-fg`).

### Step 9 — Deployment runbook (Docker + Kamal)

- Local smoke: `docker compose up --build` → visit `http://localhost:3000`, walk the setup wizard.
- Kamal (VPS): add `kamal` gem to Gemfile (not required at runtime); `.env` on the server supplies `KAMAL_REGISTRY_PASSWORD`, `RAILS_MASTER_KEY`; run `kamal setup` then `kamal deploy`; `kamal app exec "bin/rails db:prepare"` if migrations were skipped; `kamal logs` for diagnostics.
- `config/credentials.yml.enc` holds `secret_key_base`, `active_record_encryption.primary_key`, `active_record_encryption.deterministic_key` — generate with `bin/rails credentials:edit` and never commit the master key.
- Backups are out of scope for v1; one line in the deploy README: copy `storage/production.sqlite3` while the app is stopped. (Assumption below.)

## Critical files & anchors

| File | Symbol/Region | Reason |
|------|--------------|--------|
| `app/controllers/setup_controller.rb` | wizard steps 1-2 | First-run gate + admin creation; load-bearing ordering |
| `app/controllers/registrations_controller.rb` | overridden `new`/`create` | Invite-only signup enforcement |
| `app/models/invitation.rb` | token digest, expiry, accept! | Security of the only join path |
| `app/models/task.rb` | enum, recurrence, household scope | State machine + auto-scheduling |
| `app/controllers/application_controller.rb` | `Current.household` + `before_action` | Household scoping everywhere |
| `app/controllers/dashboards_controller.rb` | `show`, `stream` (SSE) | Public wall view + live updates core |
| `config/initializers/mailer.rb` | SMTP from Settings | Email infra must work before invites |
| `config/deploy.yml` + `Dockerfile` | volume/env wiring | SQLite persistence + deploy |
| `app/views/layouts/_nav.html.erb` | switcher + admin links | Household context switching UX |

## Verification

### Setup & onboarding
1. Fresh DB → visit `/`, redirected to `/setup`; fill app settings; send test email; verify it renders in letter_opener (dev) — no SMTP needed locally.
2. Complete wizard → first user exists with `admin=true`, a default household exists, redirected to `/dashboard`.
3. Try `GET /users/sign_up` while logged out → invite-required screen; signup with a bogus `?token=` → error page.
4. In `/admin`, invite `kid@example.com` to the household → verify invite email (letter_opener) contains a working link; open it, complete the join form → user created, membership created, signed in.

### Households
1. Admin creates a second household in `/admin`; adds user B to both (two memberships via new invite to same email — accept with same account; verify no duplicate user rows).
2. User B sees a household switcher (2 entries); switch → dashboard cards change to the other household.
3. A task created in household 1 is invisible to household 2's dashboard and task list; assignment dropdown lists only current-household members.

### Tasks & recurrence
1. Create "Review budget" assigned to B with `ends_at` = now+2h; B sees it; B clicks Start → card shows amber in_progress on B's dashboard immediately.
2. B clicks Cancel → status `undone`, record still present in DB.
3. Create "Standup" 9:00-9:30 `recurrence_interval: daily`; Start, then Complete → a new planned task appears with tomorrow's 9:00 `starts_at`; repeat weekly → +7 days.

### Live dashboard & wall
1. Two browsers: logged-in `/dashboard` and anonymous `/h/<token>`; change a status in one → other updates within 2 seconds without refresh.
2. `GET /h/wrong-token` → 404.
3. Resize to <640px → single-column grid.

### Notifications & deploy
1. User B approves notifications; admin assigns a task to B → B receives a browser notification.
2. `docker compose up --build` → wizard reachable on localhost:3000.
3. If a Kamal/VPS target is available: `kamal setup && kamal deploy`, verify the site is live over HTTPS and email (SMTP) works end-to-end with a real provider. If no target exists at implementation time, skip with a note; compose smoke is the required proof.

## Assumptions & contingencies

- **Ruby version:** local Ruby is 4.0.7. If `gem install rails` fails or Rails gems misbehave on 4.0, pin the project to Ruby 3.4 via mise (`mise local ruby@3.4`), run the build locally with that, and set `ruby:3.4-slim` in the Dockerfile. Do not spend time on Ruby 4.0 compatibility research.
- **Single-server deployment:** in-memory SSE subscriber registry and SQLite assume one app instance per household set. If the family later runs multiple app replicas, swap the registry for a tiny Redis pub/sub — not now.
- **Role model:** only a global `admin` flag exists; household-specific roles are not modeled. If the admin later wants per-household admins, extend `HouseholdMembership` with a role enum — not now.
- **SMTP required for invites** — that's why SMTP config is in the wizard. If a user skips SMTP fields, invitations fail to send; the settings screen must make the "send test email" step mandatory before inviting (enforce: warning banner, allow proceeding anyway).
- **Backups:** not automated in v1; documented manual sqlite copy only.
- **Notification permissions:** browsers require a secure context; on the kiosk/local LAN over http, notifications silently no-op — SSE patching still works.
