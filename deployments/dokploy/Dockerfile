# Same multi-stage Phoenix release image as the docker-compose
# variant. Dokploy auto-detects this Dockerfile when you point it
# at the repo (build context: repo root, dockerfile path:
# deployments/dokploy/Dockerfile).
#
# If you prefer to share the image with the docker-compose
# variant, you can build from that Dockerfile instead — both
# produce identical artifacts. The two are kept as separate
# files so each subdirectory is self-contained.

ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.0.1
ARG DEBIAN_VERSION=bookworm-20240926-slim
ARG NODE_VERSION=24.14.1

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION} AS build

RUN apt-get update -y \
 && apt-get install -y --no-install-recommends \
      build-essential git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    | tar -xJ -C /usr/local --strip-components=1

ENV MIX_ENV=prod
WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod && mix deps.compile

COPY assets/package.json assets/package-lock.json ./assets/
RUN cd assets && npm ci

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix assets.deploy && mix compile

COPY rel rel
RUN mix release --overwrite

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

# Run migrations on container start, then exec the server.
CMD ["sh", "-c", "/app/bin/mixchamb eval 'Mixchamb.Release.migrate' && exec /app/bin/server"]
