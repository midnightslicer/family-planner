# Whereabouts

A small status board for a family. Everyone gets an account (invite-only, no
open signup) and can see at a glance what everyone else is doing right now.
Tasks have a start and an end, some of them repeat, and the dashboard updates
live without a page reload.

Each household also gets a wall page (`/h/<household name>`, for a member
who stays signed in) for a wall-mounted tablet or a browser kiosk somewhere
in the house. It installs as an app of its own that opens full screen.

Sign-in supports passkeys (Face ID, fingerprint, device PIN), passwords, and
optional two-step verification with an authenticator app.

Built with Rails 8.1 and SQLite. Styling is plain CSS. Ships as one Docker
container; deploy it with Docker Compose or Kamal.

## Run it on a server in two minutes

With Docker installed:

```sh
git clone <this repo> whereabouts && cd whereabouts
docker compose up -d --build
docker compose logs web | grep -A2 "setup code"
```

Open http://localhost:3000 (or the machine's address), enter the setup code
from the log, then name your household and create your account (or, moving
from another server, restore its backup zip instead: see [Backups](#backups)). That's all
the configuration there is: secrets are generated on first boot and kept in
the `storage` volume with the database.

Then invite people from the dashboard. Each invite is a single-use link; if
email isn't set up you get the link to send by text or chat instead.

Optional settings go in a `.env` file next to `compose.yml`:

| Variable | What it does |
| --- | --- |
| `APP_URL` | Public address used in email links, e.g. `https://status.example.com`; its host is then the only one accepted (plus `APP_HOSTS`) |
| `FORCE_SSL=true` | Set when a reverse proxy serves the app over https. Compose defaults to `false` (plain http on a LAN, so cookies aren't https-only) |
| `APP_HOSTS` | Extra hostnames to accept (comma separated), e.g. a LAN name. With neither this nor `APP_URL` set, any Host header is accepted |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM` | Email, if you'd rather not enter it in Admin > Settings |
| `APP_NAME` | Board name before setup names it |
| `VAPID_PRIVATE_KEY`, `VAPID_PUBLIC_KEY` | Push notification keys (base64url, as printed by any web-push key generator). Optional: without them a key pair is generated into `storage/.vapid_key` on first use |

**https matters.** Passkeys, the copy buttons and browser notifications only
work over https (or on `http://localhost`). On plain http over a LAN the app
still works with passwords; put Caddy, Traefik or Tailscale in front to get
the rest.

### Put it on your phone

The app installs from the browser, no app store: on Android open it in
any browser (Chrome, Firefox, Edge, Brave, Samsung Internet) and choose
**Install app** or **Add to Home screen** from its menu;
on an iPhone open it in Safari, tap **Share**, then **Add to Home Screen**.
It opens full screen from its icon. Installing needs https (or
`http://localhost` while developing).

For a wall tablet, open the household's wall page (Admin > Households has
the link), sign in, and install it the same way: it becomes its own app,
with a dark icon and the household's name, that opens straight to the wall
in full screen (on Android; iPhones and iPads keep the status bar). If the
Wi-Fi drops it shows the offline page and comes back by itself. Offline, it shows a short "You're
offline" page and reloads itself when the connection is back.

### Notifications

Each person picks, on **Your account > Notifications**, which kinds of
update reach them by push (on each phone they turn it on for) and which by
email, plus quiet hours and a pause button. Event reminders (5 to 60
minutes before) and a morning list of the day's to-dos are among the
choices. Pushes need https and, on an iPhone, the app added to the Home
Screen first (iOS 16.4 or later); the page walks people through it. Email
needs SMTP (Admin > Settings) and every email has a one-click unsubscribe.
Admin > Settings also shows whether push and email are working.

### Deploy with Kamal (a VPS with a domain)

You need Docker and the Ruby from `.ruby-version` on your machine
(`bundle install` gets Kamal), SSH access to the server, and a container
registry account.

1. Point a DNS name at the server.
2. Copy the example settings and fill them in. `config/deploy.yml` reads
   them, so you don't need to edit it.

   ```sh
   cp .env.kamal.example .env.kamal
   chmod 600 .env.kamal
   ```

   | Variable | What it is |
   | --- | --- |
   | `DEPLOY_SERVER` | The server's hostname or IP, as you'd SSH to it |
   | `DEPLOY_DOMAIN` | The DNS name from step 1, without `https://`. Sets the certificate, `APP_URL` and Host header checking |
   | `KAMAL_REGISTRY_USERNAME` | Your registry user; the image is `<user>/whereabouts` |
   | `KAMAL_REGISTRY_PASSWORD` | A registry token (on GitHub, a classic token with `write:packages`) |
   | `DEPLOY_SSH_USER` | Optional, default `root`. Another user needs to be able to run Docker |
   | `DEPLOY_ARCH` | Optional, default `amd64`; `arm64` for an ARM server |
   | `KAMAL_REGISTRY_SERVER` | Optional, default `ghcr.io` |

3. Load them and set up the server. Kamal installs Docker if needed (that
   takes root), gets a Let's Encrypt certificate and boots the app.

   ```sh
   source .env.kamal
   bin/kamal setup
   ```

4. `bin/kamal setup-code` prints the setup code. Open your domain and finish
   setup in the browser.

Later deploys are `bin/kamal deploy`; migrations run by themselves when the
container starts. Every `bin/kamal` command needs the settings loaded, so
`source .env.kamal` in each new terminal. `.env.kamal` is ignored by Git:
don't commit it.

Before you rely on it:

- **Keep the `whereabouts_storage` volume.** It holds the database,
  photos and `.secret_key_base`, which signs sessions and links and
  encrypts two-step secrets and the SMTP password. Lose or change the
  secret and everyone is signed out and those have to be set up again.
  If you set `SECRET_KEY_BASE` yourself instead, never change it.
- **Leave `FORCE_SSL` alone** (it defaults to on in production). kamal-proxy
  serves https (`proxy: ssl: true`), and the app then keeps cookies
  https-only and sends HSTS.
- **Run one app server.** It's SQLite: don't add a second host to `web`.
- **Make a backup** (below) once you've set up, and before upgrades.

What to expect: anyone with an account stays signed in (30 days on a
device they ticked "Keep me signed in" on), so a wall tablet never
times out. Too many sign-in tries from one address are slowed down;
accounts are never locked. Admins are admins of the whole server: run
one per family.

## Run it locally for development

Ruby is pinned in `.ruby-version`; Node (`.node-version`) builds the JS.

```sh
bin/setup        # installs gems and npm packages, prepares the database, starts the server
```

Open http://localhost:3000. In development the setup page doesn't ask for a
code. Mail opens in the browser via letter_opener.

`bin/dev` listens on every interface. To reach it from a phone or another
machine, list the names you'll use in `DEV_HOSTS` (comma separated; a leading
dot allows every subdomain), for example on a tailnet:
`DEV_HOSTS=mymachine,.ts.net bin/dev`, then open http://mymachine:3000.
Passkeys, push and installing the app
need https: `tailscale serve --bg 3000` puts the dev server at
https://<machine>.<tailnet>.ts.net (tailnet only; `tailscale serve --https=443 off`
stops it). Passkeys belong to the address they were made on, so add one
there; ones made on localhost don't carry over.

Tests: `bin/rails test` (with the Ruby from `.ruby-version`); `bin/ci`
also runs the linters and security checks.

## Backups

**Admin > Backup** downloads the whole app as one zip: every household,
account, schedule, pet, place and photo. From a shell,
`bin/rails backup:create` writes the same zip into `storage/backups`
(`bin/kamal backup` on Kamal, `docker compose exec web bin/rails backup:create`
with Compose); give it a path to write somewhere else:
`bin/rails "backup:create[/path/to/family.zip]"`.

There are two ways to restore:

- **Onto a fresh server** (moving to a new one): start it, enter its setup
  code, and choose **Restore a backup** on the setup page instead of creating
  an account (or run `bin/rails "backup:restore[/path/to/family.zip]"`). This
  only works while the server has no accounts.
- **Over a server in use** (going back to an earlier backup): an admin opens
  **Admin > Backup** and uses **Restore a backup** at the bottom. **This
  overwrites the whole database**: every household, account, schedule, pet,
  place and photo is replaced by what's in the zip, and anything added or
  changed since the backup was made is lost. To make that hard to do by
  accident, you type `RESTORE` and confirm once more. Before anything is
  replaced, the server saves a backup of what's there now as
  `storage/backups/before-restore-<name>-<time>.zip`, so a mistaken restore
  can be undone by restoring that file. The zip is checked first; if it isn't
  a backup the app can read, nothing changes. You're signed out afterwards and
  sign in with the accounts from the backup.

Either way, backups from an older version of the app are brought up to date
as they're restored; one from a newer version asks you to update the server
first.

Everyone then signs in with their usual email and password. What doesn't
come along, because it stays encrypted to the old server and never leaves it
in the clear:

- Two-step verification is turned off for anyone who had it; they set it up
  again from their account.
- The email (SMTP) password needs entering again in Admin > Settings.
- Each device turns notifications back on by itself the next time it opens
  the app.
- Passkeys keep working only if the new server has the same address.

Restoring onto the same server, or one that kept the old `storage/.secret_key_base`
(or `SECRET_KEY_BASE`), keeps two-step verification and the SMTP password.

The zip holds everything the board knows (including password hashes and
where everyone has been): keep it as safe as the server.

Under the hood everything lives in the `storage` volume: the SQLite
databases, the generated `.secret_key_base` and the push notification key
`.vapid_key`. Copying the whole volume while the app is stopped is also a
complete backup, secrets included.

## Locked out?

- **Forgot a password:** use "Forgot your password?" on the sign-in page. If
  email isn't set up, an admin can make a reset link under Admin > People.
- **Lost the phone with the passkey or authenticator app:** use a recovery
  code, or ask an admin to use "Reset sign-in" under Admin > People, which
  removes passkeys and two-step verification and signs you out everywhere
  (the lost phone too), so a password reset gets you in.
- **Changing or resetting a password** signs you out on every other
  device, including ones kept signed in.

## License

[MIT](LICENSE)
