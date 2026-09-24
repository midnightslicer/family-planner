# family-status

A small status board for a family. Everyone gets an account (invite-only, no
open signup) and can see at a glance what everyone else is doing right now.
Tasks have a start and an end, some of them repeat, and the dashboard updates
live without a page reload.

Each household also gets a wall page (`/h/<secret token>`, no login) for a
wall-mounted tablet or a browser kiosk somewhere in the house.

Sign-in supports passkeys (Face ID, fingerprint, device PIN), passwords, and
optional two-step verification with an authenticator app.

Built with Rails 8.1 and SQLite. Styling is plain CSS. Ships as one Docker
container; deploy it with Docker Compose or Kamal.

## Run it on a server in two minutes

With Docker installed:

```sh
git clone <this repo> family-status && cd family-status
docker compose up -d --build
docker compose logs web | grep -A2 "setup code"
```

Open http://localhost:3000 (or the machine's address), enter the setup code
from the log, then name your household and create your account. That's all
the configuration there is: secrets are generated on first boot and kept in
the `storage` volume with the database.

Then invite people from the dashboard. Each invite is a single-use link; if
email isn't set up you get the link to send by text or chat instead.

Optional settings go in a `.env` file next to `compose.yml`:

| Variable | What it does |
| --- | --- |
| `APP_URL` | Public address used in email links, e.g. `https://status.example.com` |
| `FORCE_SSL=true` | Set when a reverse proxy serves the app over https |
| `APP_HOSTS` | Extra hostnames to accept (comma separated), e.g. a LAN name |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM` | Email, if you'd rather not enter it in Admin > Settings |
| `APP_NAME` | Board name before setup names it |

**https matters.** Passkeys, the copy buttons and browser notifications only
work over https (or on `http://localhost`). On plain http over a LAN the app
still works with passwords; put Caddy, Traefik or Tailscale in front to get
the rest.

### Deploy with Kamal (a VPS with a domain)

1. Point a DNS name at the server.
2. In `config/deploy.yml`, fill in the three `CHANGE ME` lines (server, host,
   registry) and set `APP_URL`.
3. Export `KAMAL_REGISTRY_PASSWORD` (a registry token), then run
   `bin/kamal setup`. Kamal installs Docker, gets a Let's Encrypt
   certificate and boots the app.
4. `bin/kamal setup-code` prints the setup code. Open your domain and finish
   setup in the browser.

Later deploys are `bin/kamal deploy`.

## Run it locally for development

Ruby is pinned in `.ruby-version`; Node (`.node-version`) builds the JS.

```sh
bin/setup        # installs gems and npm packages, prepares the database, starts the server
```

Open http://localhost:3000. In development the setup page doesn't ask for a
code. Mail opens in the browser via letter_opener.

Tests: `bin/rails test`

## Backups

Everything lives in the `storage` volume: the SQLite databases and the
generated `.secret_key_base`. Keep them together; encrypted settings (the
SMTP password, two-step verification secrets) can't be read without that
secret. To back up, stop the app and copy the volume, or use
`sqlite3 storage/production.sqlite3 ".backup backup.sqlite3"` while it runs.

## Locked out?

- **Forgot a password:** use "Forgot your password?" on the sign-in page. If
  email isn't set up, an admin can make a reset link under Admin > People.
- **Lost the phone with the passkey or authenticator app:** use a recovery
  code, or ask an admin to use "Reset sign-in" under Admin > People, which
  removes passkeys and two-step verification so a password reset gets you in.
