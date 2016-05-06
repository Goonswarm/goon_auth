FROM elixir
MAINTAINER Vincent Ambo <tazjin@gmail.com>

RUN mix do local.hex --force, local.rebar --force
RUN apt-get update && apt-get install -y curl

ENV MIX_ENV prod
ENV PORT 4000

# Cache dependencies
ADD . /opt/goon_auth
WORKDIR /opt/goon_auth

RUN mix do deps.get, deps.compile, compile, release

CMD /opt/goon_auth/rel/goon_auth/bin/goon_auth foreground
