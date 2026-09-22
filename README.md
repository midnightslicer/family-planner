# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions
* ...

## Deploy

Local smoke test with Docker Compose:

```
echo "RAILS_MASTER_KEY=$(cat config/master.key)" > .env
docker compose up --build
```

Then open http://localhost:3000 and walk the setup wizard.

Production deploy with Kamal (requires a VPS with Docker):

1. Put `KAMAL_REGISTRY_PASSWORD` and `RAILS_MASTER_KEY` in `.kamal/secrets` (or your shell env).
2. Edit `config/deploy.yml`: set `servers.web` to your host and `registry` to your image registry.
3. `kamal setup` (first time: installs Docker, builds/pushes the image, boots the app).
4. `kamal deploy` for subsequent deploys.

Backups: stop the app, then copy `storage/production.sqlite3` (the whole `storage/` volume on the server).
* ...
