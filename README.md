# family-status

A small status board for a family. Everyone gets an account (invite-only, no
open signup) and can see at a glance what everyone else is doing right now.
Tasks have a start and an end, some of them repeat, and the dashboard updates
live without a page reload.

Each household also gets a public wall page (`/h/<dashboard_token>`, no login)
for a wall-mounted iPad or a browser kiosk somewhere in the house.

Built with Rails 8.1 and SQLite. Styling is plain CSS. Deployed with Docker
and Kamal.

## Run it locally

Ruby is pinned in `.ruby-version`; Node is needed for the JS build.

```sh
bin/rails db:prepare
bin/dev          # JS build + Rails server on http://localhost:3000
```

The first visit redirects to a short setup wizard: app settings (including
SMTP, though local mail opens in the browser via letter_opener), then the
first admin account.

Tests: `bin/rails test`

Local smoke test with Docker Compose:

```
echo "RAILS_MASTER_KEY=$(cat config/master.key)" > .env
docker compose up --build
```

Then open http://localhost:3000 and walk the setup wizard.

## Deploy

Production deploys go through Kamal to a VPS with Docker:

1. Put `KAMAL_REGISTRY_PASSWORD` and `RAILS_MASTER_KEY` in `.kamal/secrets` (or your shell env).
2. Edit `config/deploy.yml`: set `servers.web` to your host and `registry` to your image registry.
3. `kamal setup` (first time: installs Docker, builds/pushes the image, boots the app).
4. `kamal deploy` for subsequent deploys.

## Backups

Stop the app, then copy `storage/production.sqlite3` (the whole `storage/` volume on the server).