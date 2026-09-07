FROM docker.io/library/elixir:1.14.5-otp-25-alpine AS build
RUN apk --no-cache add ca-certificates curl git

RUN mkdir /src
WORKDIR /src

ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config ./config

COPY apps/util/mix.exs ./apps/util/mix.exs
COPY apps/manager/mix.exs ./apps/manager/mix.exs
COPY apps/extension/mix.exs ./apps/extension/mix.exs

COPY apps/util/config ./apps/util/config
COPY apps/manager/config ./apps/manager/config
COPY apps/extension/config ./apps/extension/config

RUN mix deps.get
RUN mix deps.compile

COPY apps/ ./apps
RUN mix compile
RUN mix release

# only to ensure the base image is compatible
FROM docker.io/library/elixir:1.14.5-otp-25-alpine
RUN apk --no-cache add curl bash

RUN addgroup -S fondbot && adduser -S -G fondbot fondbot
RUN mkdir /app /data && chown fondbot:fondbot /app /data

EXPOSE 9786/tcp
VOLUME /data

WORKDIR /app
COPY --from=build --chown=fondbot:fondbot /src/_build/prod/rel/fondbot ./
USER fondbot
CMD ./bin/fondbot start
