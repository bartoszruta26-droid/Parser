# Raspberry Pi swarm communication

This project includes a lightweight Bash helper for Raspberry Pi swarms:
`swarm/bin/rpi-swarm.sh`. Each Raspberry Pi runs its own local daemon and uses
this helper to pass sensor readings, effector commands and inter-node forwarding
requests through the daemon protocol.

## Node roles

Configure every device with the same inventory in `daemon.conf`, but set a
unique node identity on each Raspberry Pi:

```bash
RPI_NODE_NAME="rpi-worker-01"
RPI_NODE_ROLE="worker"
RPI_MAIN_DAEMON_HOST="192.168.1.10"
RPI_MAIN_DAEMON_PORT="8701"
```

Exactly one device should use `RPI_NODE_ROLE="main"`. Worker devices keep their
own local daemon for hardware access and forward data to the main daemon when
the deployment enables a network transport.

## Sensors

`RPI_SENSOR_SOURCES` maps sensor names to readable files or executable scripts.
A worker can read a configured source and enqueue the reading in its daemon:

```bash
DAEMON_CONFIG=/etc/parser-template/daemon.conf \
  /opt/parser-template/swarm/bin/rpi-swarm.sh sensor-read temperature
```

The daemon records the event in `SENSOR_QUEUE_FILE` and returns `SWARM_SENSOR`.
You can also pass a value explicitly, which is useful for adapters that already
read the hardware:

```bash
/opt/parser-template/swarm/bin/rpi-swarm.sh sensor-read humidity 48.2
```

## Effectors

`RPI_EFFECTOR_TARGETS` maps effector names to writable state files or executable
scripts. The helper first sends the command to the daemon as `swarm.effector`,
then applies the configured target locally:

```bash
/opt/parser-template/swarm/bin/rpi-swarm.sh effector-send relay on
```

The daemon records the command in `EFFECTOR_QUEUE_FILE` and returns
`SWARM_EFFECTOR`.

## Inter-node forwarding

Use `forward-main` when a worker needs to forward a daemon command toward the
main Raspberry Pi:

```bash
/opt/parser-template/swarm/bin/rpi-swarm.sh forward-main swarm.sensor \
  '{"node":"rpi-worker-01","sensor":"temperature","value":"21.7"}'
```

By default `RPI_ENABLE_TCP_FORWARD="false"`, so forwarding requests are recorded
in the local daemon as `swarm.forward`. When TCP forwarding is explicitly
enabled and `nc` or Bash `/dev/tcp` is available, the helper writes one daemon
protocol line to `RPI_MAIN_DAEMON_HOST:RPI_MAIN_DAEMON_PORT`.
