# Server Dispatch

[![Build Status](https://travis-ci.org/aca-labs/crystal-engine-server-dispatch.svg?branch=master)](https://travis-ci.org/aca-labs/crystal-engine-server-dispatch)

This allows engine drivers to register new servers for devices that might connect to engine vs engine connecting to devices.

* Drivers can indicate a port they want open and the IP addresses they'll accept data from.
* The details of the clients and data is then streamed to the drivers.
* Servers are only opened if there is a driver listening and ports are closed otherwise.

## ENV Vars

* `PLACE_SERVER_SECRET` = shared bearer token for driver auth
* `SG_ENV` = set to `production` for production log levels

## Usage

There are two websocket endpoints one for TCP and one for UDP

* `/api/server/tcp_dispatch`
* `/api/server/udp_dispatch`

The query string should include the

* `bearer_token` used to authenticate the request
* `port` the server should run on
* `accept` a comma delimited list of client IP addresses that are expected to connect to the server

```
WS /api/server/tcp_dispatch?bearer_token=testing&port=6001&accept=127.0.0.1
```

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

  # Engine drivers requesting a TCP server be open
  "tcp_listeners": {"6001": 1},

  # Remote clients connected to the live servers
  "tcp_clients": {"6001": 1}
}

```
