# Multi-stage Phoenix release image. Build stage compiles deps,
# runs the asset pipeline, and produces an OTP release; runtime
# stage is a slim Debian with just the release artifacts copied
# in.
#
# Image tags below match the project's Elixir / Erlang versions.
# If you bump versions later, update both ARGs and rebuild.
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.0.1
ARG DEBIAN_VERSION=bookworm-20250630-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

# Install the OS deps the build needs: build essentials for any
# native NIFs, git for hex deps that pull from git, and curl +
# nodejs for the Vite asset build.
RUN apt-get update -y && apt-get install -y \
      build-essential git curl ca-certificates && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

# Node 22 — Phoenix's asset pipeline drives Vite via npm, and
# phoenix_vite hardcodes the `npm` binary so we need it in PATH.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

# Working dir; matches the runner-stage path.
WORKDIR /app

# Hex + rebar.
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

# Deps first for layer caching.
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Compile config before deps so deps see compile-time config.
RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

# Source.
COPY priv priv
COPY lib lib

# Asset pipeline. package.json + package-lock.json must be
# present so npm install can run; vite.config.mjs reads from
# assets/.
COPY package.json package-lock.json ./
COPY assets assets
RUN mix assets.setup
RUN mix assets.deploy

# Compile the project itself.
RUN mix compile

# Runtime config + release scripts.
COPY config/runtime.exs config/
COPY rel rel
RUN mix release

# Runtime image — only what's needed to run the release.
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

# UTF-8 locale so logs + DB content render cleanly.
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

ENV MIX_ENV="prod"

# Copy the compiled release from the build stage.
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/mixwave ./

USER nobody

# fly.toml's [http_service] points at this port; PORT is
# overridable in the env if you ever change it.
ENV PORT=8080

CMD ["/app/bin/server"]
