# syntax=docker/dockerfile:1
# check=error=true

# family-status production image.
# Build: docker build -t family-status .
# Run:   docker run -d -p 3000:3000 -e RAILS_MASTER_KEY=<key> family-status

ARG RUBY_VERSION=4.0
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base

WORKDIR /rails

# Runtime packages: libsqlite3 for the sqlite3 gem, jemalloc for lower memory.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libsqlite3-0 libjemalloc2 curl && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2"

# ---- Build stage: gems, JS bundles, and precompiled assets ----
FROM base AS build

# Build tools for native gem extensions, plus Node for esbuild.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git libyaml-dev pkg-config node-gyp python-is-python3 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ARG NODE_VERSION=26
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
RUN corepack enable

# Install gems first (layer cache: only rebuilds when Gemfile changes).
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Install JS dependencies and run the esbuild bundle (same as bin/build).
COPY package.json ./
COPY app/javascript ./app/javascript
COPY bin ./bin
COPY config ./config
RUN yarn install && yarn build

# Application code and asset precompile.
COPY . .
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf node_modules

# ---- Final stage ----
FROM base

# Non-root user owns the runtime files.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

RUN mkdir -p storage && chown -R rails:rails storage

USER rails:rails

ENV RAILS_ENV="production"
EXPOSE 3000

ENTRYPOINT ["/rails/entrypoint.sh"]
CMD ["bin/rails", "server", "-p", "3000"]