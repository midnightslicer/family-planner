#!/bin/sh
set -e

bin/rails db:prepare

exec "$@"