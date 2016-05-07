# GoonAuth

Authentication services for GoonSwarm.

This is a simple LDAP-backed registration and user management service that lets
members of [OHGOD] register an account in an LDAP server.

This account can then be used for access to forums and other external services.

## Tech overview

GoonAuth is an Elixir application using the Phoenix framework. It is currently
built as a Docker image and intended to be deployed in a Kubernetes cluster.

An image for an LDAP server with the correct schema is located in the
[infrastructure][] repository.

## Building for production

Run `docker build` with appropriate flags in the repository root.

## Building for development

Follow instructions from the aforementioned `slapd` image README to set up an
LDAP test server locally.

Install Elixir and run these commands:

```
mix do deps.get, deps.compile
iex -S mix phoenix.server
```

This will fetch and compile dependencies and start up the server, giving you an
interactive console.

[infrastructure]: https://github.com/goonswarm/infrastructure
