FROM elixir:1.3.0
MAINTAINER Vincent Ambo <tazjin@gmail.com>

RUN mix do local.hex --force, local.rebar --force
RUN apt-get update && apt-get install -y curl

ENV MIX_ENV prod
ENV PORT 4000

# Cache dependencies
ADD . /opt/goon_auth
WORKDIR /opt/goon_auth

RUN mix do deps.get, deps.compile, compile

CMD mix run --no-halt
