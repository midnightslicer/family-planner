# syntax=docker/dockerfile:1
# check=error=true

# family-status production image.
#   docker build -t family-status .
#   docker run -d -p 3000:3000 -v family_status:/rails/storage family-status
# No secrets are required: the entrypoint creates SECRET_KEY_BASE on the
# storage volume the first time it starts.

ARG RUBY_VERSION=4.0
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libsqlite3-0 libjemalloc2 curl && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# jemalloc via a stable symlink, so the image works on amd64 and arm64
# (Raspberry Pi, Apple silicon) alike.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# ---- Build stage: gems, JS bundle, precompiled assets ----
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Node only for esbuild; it isn't copied into the final image.
ARG NODE_VERSION=26
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install --no-install-recommends -y nodejs && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Gems first so this layer is cached until the Gemfile changes.
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# JS dependencies from the lockfile, cached until package*.json change.
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY . .

# Precompile bootsnap for faster boots, then build JS (jsbundling runs
# `npm run build`) and fingerprint assets.
RUN bundle exec bootsnap precompile app/ lib/ && \
    SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf node_modules

# ---- Final stage ----
FROM base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

RUN mkdir -p storage && chown -R rails:rails storage db log tmp

USER 1000:1000

# One container runs everything: Thruster (compression, asset caching) in
# front of Puma, with Solid Queue's worker inside Puma for emails.
ENV HTTP_PORT="3000" \
    TARGET_PORT="3001" \
    SOLID_QUEUE_IN_PUMA="true"
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -fsS http://localhost:3000/up || exit 1

ENTRYPOINT ["/rails/entrypoint.sh"]
CMD ["./bin/thrust", "./bin/rails", "server"]
