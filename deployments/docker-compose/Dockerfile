# Multi-stage Phoenix release image.
#
# Build stage: compile Elixir release + Vue/Tailwind assets.
# Runtime stage: minimal Debian slim, just enough to run the
# embedded ERTS the release ships with.
#
# The runtime image does NOT include Elixir / Erlang / Node /
# build tools — the release is self-contained.

# --- Build stage -------------------------------------------------
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.0.1
ARG DEBIAN_VERSION=bookworm-20240926-slim
ARG NODE_VERSION=24.14.1

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION} AS build

RUN apt-get update -y \
 && apt-get install -y --no-install-recommends \
      build-essential git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Node for the Vite/Vue asset build.
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    | tar -xJ -C /usr/local --strip-components=1

ENV MIX_ENV=prod
WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

# Cache deps + compile first so source changes don't re-fetch.
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod && mix deps.compile

# Asset deps before app code so npm cache layer is reusable.
COPY assets/package.json assets/package-lock.json ./assets/
RUN cd assets && npm ci

# Now the app itself.
COPY priv priv
COPY lib lib
COPY assets assets

RUN mix assets.deploy && mix compile

COPY rel rel
RUN mix release --overwrite

# --- Runtime stage -----------------------------------------------
FROM debian:${DEBIAN_VERSION} AS runtime

RUN apt-get update -y \
 && apt-get install -y --no-install-recommends \
      libstdc++6 openssl libncurses6 locales ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
 && sed -i 's/^# en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/' /etc/locale.gen \
 && locale-gen

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US:en \
    MIX_ENV=prod

WORKDIR /app
RUN groupadd -r mixchamb && useradd -r -g mixchamb -d /app mixchamb \
 && chown -R mixchamb:mixchamb /app
USER mixchamb

COPY --from=build --chown=mixchamb:mixchamb /app/_build/prod/rel/mixchamb ./

EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://localhost:4000/up || exit 1

CMD ["/app/bin/server"]
