FROM elixir:alpine AS build
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


FROM elixir:alpine
RUN apk --no-cache add curl git bash

RUN mkdir /app /data

EXPOSE 9786/tcp
VOLUME /data

WORKDIR /app
COPY --from=build /src/_build/prod/rel/fondbot ./
CMD ./bin/fondbot start
