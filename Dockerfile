FROM elixir:alpine AS build
RUN apk --no-cache add ca-certificates curl git

RUN mkdir /src
WORKDIR /src
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

ADD config mix.exs mix.lock /src/
RUN mix deps.get
RUN mix compile

ADD apps /src/apps
RUN mix deps.get
RUN mix compile
RUN mix release


FROM alpine:latest
RUN apk --no-cache add ca-certificates curl

RUN mkdir /app /data

EXPOSE 9786/tcp
VOLUME /data

COPY --from=build /src/_build/prod/rel/fondbot/ /app
WORKDIR /app
CMD /app/bin/fondbot start


