# GoonAuth
[![Build status](https://travis-ci.org/Goonswarm/goon_auth.svg?branch=master)](https://travis-ci.org/Goonswarm/goon_auth)

Authentication services for GoonSwarm.

This is a simple LDAP-backed registration and user management service that lets
members of [OHGOD] register an account in an LDAP server.

This account can then be used for access to forums and other external services.

GoonAuth only concerns itself with maintaining the data in LDAP, for bad services
that can't deal with that we have [BADS][].

## Features

GoonAuth currently has the following features:

* User authentication through EVE SSO
* Account creation in LDAP with refresh token storage
* Password change functionality

Several other features are planned for implementation once the base system is
rolled out:

* LDAP group management ([#2][])
* Corp application feature with SSO verification ([#3][])
* Password resets ([#1][])

## Tech overview

GoonAuth is an Elixir application using the Phoenix framework. It is currently
built as a Docker image and intended to be deployed in a Kubernetes cluster.

An image for an LDAP server with the correct schema is located in the
[infrastructure][] repository.

Access to CCP's CREST API is provided by the Elixir [OAuth2][] library with
credentials retrieved from the EVE SSO site. Please refer to CCP's
[third-party documentation][] for information specific to this.

Most other functionality, including LDAP connectivity, is provided by the Erlang
standard library.

## Configuration & Secrets

In addition to configuration related to Phoenix, GoonAuth needs credentials for
accessing both the EVE SSO and the LDAP directory. While normal configuration is
provided with Elixir's configuration mechanism from the [config][] directory,
secrets are loaded at runtime from a JSON structure with the following format:

```json
{
    "crest": {
        "client": "SSO_CLIENT_ID",
        "secret": "SSO_CLIENT_SECRET",
        "callback": "https://goon-auth.host/register/crest-catch"
    },
    "ldap_password": "SOME_PASSWORD",
    "phoenix_secret_key": "SECRET_COOKIE_SESSION_KEY"
}
```

The location of this configuration file is specified in the Elixir configuration
under the `:secrets_path` key.

## Building

### Building for production

As GoonAuth is intended to be deployed as a Docker container, a Dockerfile is
included for production builds.

The Dockerfile will install dependencies and build an Erlang release.

Run `docker build` with appropriate flags in the repository root to create this
image.

### Building for development

Follow instructions from the aforementioned `slapd` image README to set up an
LDAP test server locally.

Install Elixir and run these commands:

```
mix do deps.get, deps.compile
iex -S mix phoenix.server
```

This will fetch and compile dependencies and start up the server, giving you an
interactive console.

[BADS]: https://github.com/goonswarm/bads
[infrastructure]: https://github.com/goonswarm/infrastructure
[OAuth2]: https://github.com/scrogson/oauth2
[third-party documentation]: https://eveonline-third-party-documentation.readthedocs.io/en/latest/
[#1]: https://github.com/Goonswarm/goon_auth/issues/1
[#2]: https://github.com/Goonswarm/goon_auth/issues/2
[#3]: https://github.com/Goonswarm/goon_auth/issues/3
