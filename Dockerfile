FROM elixir:alpine AS build

RUN mkdir /src
ADD apps config mix.exs mix.lock /src/
WORKDIR /src
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force
RUN mix release


FROM alpine:latest
RUN apk --no-cache add ca-certificates curl

RUN mkdir /app

COPY --from=build /src/_build/prod/rel/fondbot/ /app
WORKDIR /app
CMD /app/bin/fondbot start


