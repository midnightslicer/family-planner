#!/bin/sh
set -e

# Zero-config secrets: without SECRET_KEY_BASE or a master key, create a
# random secret once and keep it on the storage volume, so sessions and
# encrypted settings survive restarts and upgrades. Back it up with the
# database (it's in the same volume).
if [ -z "$SECRET_KEY_BASE" ] && [ -z "$RAILS_MASTER_KEY" ]; then
  unset RAILS_MASTER_KEY
  secret_file=/rails/storage/.secret_key_base
  if [ ! -s "$secret_file" ]; then
    umask 077
    od -An -N64 -tx1 /dev/urandom | tr -d ' \n' > "$secret_file"
  fi
  SECRET_KEY_BASE="$(cat "$secret_file")"
  export SECRET_KEY_BASE
fi

bin/rails db:prepare

exec "$@"
