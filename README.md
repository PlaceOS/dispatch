# Server Dispatch

[![Build](https://github.com/PlaceOS/dispatch/actions/workflows/build.yml/badge.svg)](https://github.com/PlaceOS/dispatch/actions/workflows/build.yml)
[![CI](https://github.com/PlaceOS/dispatch/actions/workflows/ci.yml/badge.svg)](https://github.com/PlaceOS/dispatch/actions/workflows/ci.yml)
[![Changelog](https://img.shields.io/badge/Changelog-available-github.svg)](/CHANGELOG.md)


This allows engine drivers to register new servers for devices that might connect to engine vs engine connecting to devices.

* Drivers can indicate a port they want open and the IP addresses they'll accept data from.
* The details of the clients and data is then streamed to the drivers.
* Servers are only opened if there is a driver listening and ports are closed otherwise.

## ENV Vars

* `PLACE_SERVER_SECRET` = shared bearer token for driver auth
* `SG_ENV` = set to `production` for production log levels

## Usage

There are websocket endpoints for TCP, TLS and UDP servers

* `/api/dispatch/v1/tcp_dispatch`
* `/api/dispatch/v1/tls_dispatch`
* `/api/dispatch/v1/udp_dispatch`

The query string should include the

* `bearer_token` used to authenticate the request
* `port` the server should run on
* `accept` a comma delimited list of client IP addresses that are expected to connect to the server

```
WS /api/dispatch/v1/tcp_dispatch?bearer_token=testing&port=6001&accept=127.0.0.1
```

### TLS

`tls_dispatch` behaves the same as `tcp_dispatch` however clients are expected to negotiate TLS.
Dispatch handles the encryption, so data sent and received over the websocket is the decrypted client data. The query string can optionally include

* `private_key` a PEM encoded private key (RSA or EC)
* `certificate` a PEM encoded certificate, optionally followed by the certificate chain

If only a `private_key` is provided then a self-signed certificate is generated for the key.
If neither are provided then a self-signed certificate is used.
The request is rejected with a `400` if a `certificate` is provided without a `private_key`, either can't be parsed, or they don't match.

A port can only be serving one of TCP or TLS at a time, the websocket is closed if the port is already in use by the other transport.
If multiple drivers request TLS on the same port, the configuration provided by the first driver is used.

```
WS /api/dispatch/v1/tls_dispatch?bearer_token=testing&port=6001&accept=127.0.0.1&private_key=<url encoded PEM>
```

### Protocol

The websocket only communicates over `BINARY` frames and has the following message types:

* OPENED == `0` dispatcher => driver - a TCP client connected to the server
* CLOSED == `1` dispatcher => driver - a TCP client disconnected
* RECEIVED == `2` dispatcher => driver - data was received from a UDP or TCP client
* WRITE == `3` driver => dispatcher - request some data be written to a UDP or TCP client
* CLOSE == `4` driver => dispatcher - request a TCP client be disconnected

The message structure sent down the websocket looks like:

```
uint8 message_type (OPENED, CLOSED etc)
string ip_address (remote IP, with null character termination)
uint64 id_or_port (client id for TCP, remote port for UDP)
uint32 data_size (number of bytes of data included)
bytes data (any data associated with the message, RECEIVED and WRITE messages only)
```


## Statistics

Statistics are available via a `GET` request

* `GET /api/server?bearer_token=testing`

```yaml

{
  # Engine drivers requesting a UDP server be open
  "udp_listeners": {"162": 8},

  # Engine drivers requesting a TCP or TLS server be open
  "tcp_listeners": {"6001": 1},

  # Remote clients connected to the live servers
  "tcp_clients": {"6001": 1}
}

```

## Deployment

When deployed in the cloud, one can configure K8s load balancer to forward data coming in on required ports to Dispatch.

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md).
