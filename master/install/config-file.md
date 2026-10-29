# Configure the Stack from One File

Instead of passing command-line flags to `start-all.sh`, you can describe the whole monitoring stack in one YAML file.
`scylla_monitoring_config.py`, the *watcher*, reads the file, applies it, and applies it again whenever it changes.

The file holds everything the stack needs: the targets, the alert rules, the Alertmanager configuration,
the Grafana settings, the storage directories, TLS, and systemd drop-ins for host services such as node_exporter.
The watcher generates the derived files from it, starts the stack, and on a later change runs only what
that change needs: a change to the targets needs no restart, a change to the alert rules reloads Prometheus,
and a new Grafana password is set in place.

## Requirements

* Python 3, with `PyYAML` (`python3-yaml`) and `jsonschema` 3.2 or later (`python3-jsonschema`).
* The watcher runs as a regular user who is a member of the `docker` group.
* TLS certificates and systemd drop-ins need root. The watcher runs `scylla-monitoring-root.sh` for them with `sudo -n`.
  Install the script root-owned and let the watcher’s user run it, and only it, for example:
  ```shell
  sudo install -o root -g root -m 755 scylla-monitoring-root.sh /usr/local/sbin/
  echo 'scylla ALL=(root) NOPASSWD: /usr/local/sbin/scylla-monitoring-root.sh' | sudo tee /etc/sudoers.d/scylla-monitoring
  ```

  Replace `scylla` with the watcher’s user. Without the `tls` and `systemd` sections, the watcher does not need root.

## The Configuration File

`scylla-monitoring.schema.json`, in the root of the monitoring directory, defines the file.
The description of each field names the `start-all.sh` flag it replaces and its default.
`scylla-monitoring.example.yaml` is a complete, commented example:

```yaml
# An example of the configuration file applied by scylla_monitoring_config.py.
# scylla-monitoring.schema.json is the definition; this file is checked
# against it. Every write replaces the file whole; keep it 0600, it holds
# secrets.
version: 1
generation: "2026-10-21T10:00:00Z-1"  # set by the writer; reported back in the status
cluster: cluster1                     # the cluster label on the prometheus and grafana jobs, and the
                                      # cluster external label; only for a monitor of one cluster,
                                      # set to the cluster label of its targets

stack:
  scylla_version: "2025.3"            # -v
  manager_version: "3.5"              # -M; missing: the release default
  alertmanager: true                  # false: --no-alertmanager
  log_collector: alloy                # --log-collector alloy|promtail|none
  thanos_sidecar: true                # --thanos-sc
  local_thanos: false                 # --local-thanos
  bind_address: 127.0.0.1             # -A; 127.0.0.1 when tls.enabled is true
  docker_args: ["--restart=unless-stopped"]   # -D
  extra_flags: []                     # start-all.sh syntax; takes precedence over the rest

storage:
  prometheus_dir: /data/prometheus      # -d
  grafana_dir: /data/grafana            # -G
  alertmanager_dir: /data/alertmanager  # -f
  retention_days: 30                    # -b --storage.tsdb.retention.time=30d

prometheus:
  external_url: https://example.com/prometheus   # -b --web.external-url, with --web.route-prefix=/

grafana:
  root_url: https://example.com/grafana  # GF_SERVER_ROOT_URL
  default_theme: light                   # GF_USERS_DEFAULT_THEME
  anonymous_role: Viewer                 # -Q
  env:                                   # -c, any other Grafana setting
    GF_SECURITY_COOKIE_SECURE: "true"
  admin_password: "change-me"            # GRAFANA_ADMIN_PASSWORD
  datasource:
    scylla_user: "monitor"               # SCYLLA_USER
    scylla_password: "change-me"         # SCYLLA_PSSWD

targets:                                 # Prometheus file_sd entries
  scylla:                                # hosts without a port; also scraped for node_exporter and the manager agent
    - targets: ["10.0.0.1", "10.0.0.2"]
      labels: {cluster: cluster1, dc: dc1}
    - targets: ["10.0.0.3"]
      labels: {cluster: cluster1, dc: dc2}
  node_exporter:                         # optional; replaces the copy of scylla
    - targets: ["10.0.1.1:9100"]
      labels: {cluster: cluster1, dc: dc1, instance: "10.0.0.1"}
  manager:
    - targets: ["10.0.0.5:5090"]
  vector_search:                         # present: --vector-search
    - targets: ["10.0.0.6"]
      labels: {cluster: cluster1}

alert_rules:                             # a Prometheus rule file
  groups:
    - name: scylla.rules
      rules:
        - alert: InstanceDown
          expr: up{job="scylla"} == 0
          for: 30s
          labels:
            severity: error
          annotations:
            description: "{{ $labels.instance }} has been down for more than 30 seconds."
            summary: Instance {{ $labels.instance }} down

alertmanager_config:                     # an Alertmanager config file
  route:
    receiver: default
    group_by: [alertname, cluster]
  receivers:
    - name: default

systemd:                                 # drop-ins for host services, by unit
  node-exporter.service: |               # 127.0.0.1:9100 behind traefik
    [Service]
    Environment=NODE_EXPORTER_ARGS=--web.listen-address=127.0.0.1:9100

tls:
  enabled: true                          # run traefik
  listen_ip: 10.0.0.10                   # PRIVATE_IP of start-traefik.sh
  ca_crt: |                              # rootCA.crt
    -----BEGIN CERTIFICATE-----
    ...
    -----END CERTIFICATE-----
  server_crt: |                          # server.crt
    -----BEGIN CERTIFICATE-----
    ...
    -----END CERTIFICATE-----
  server_key: |                          # server.key
    -----BEGIN PRIVATE KEY-----
    ...
    -----END PRIVATE KEY-----
```

`version`, `generation`, `stack` and `targets` are required. A missing optional section keeps the
`start-all.sh` default: without `tls` no traefik runs, and without `systemd` the host’s units are left as they are.

`stack.extra_flags` takes any other `start-all.sh` flag, in `start-all.sh` syntax. A flag there takes
precedence over the same option derived from the rest of the file. The options the watcher sets from the file itself
(the targets, rule and Alertmanager files, `--target-directory`, `--vector-search`, `--vector-store`,
`--cluster-label`, `--archive`, `--compose` and `-h`) are rejected in `extra_flags`.

### Writing the File

* Always write the whole file, and replace it atomically: write a temporary file in the same directory and rename it into place.
* The file holds secrets (the Grafana admin password, the CQL password and the TLS private key). Keep it `0600`, owned by the watcher’s user.
* Set `generation` to a new value on every write. The watcher reports it back in the status file, so you know when your change is applied.
* The watcher ignores fields it does not know. With `--strict`, an unknown field rejects the file.

## Running the Watcher

```shell
scylla_monitoring_config.py check|apply|run --config-file FILE --monitoring-dir DIR [options]
```

* `check` validates the file, renders the derived files into a temporary directory and prints the `start-all.sh` command line,
  with the secrets masked. It changes nothing, so it is safe to run next to a running watcher.
* `apply` applies the file once. `--force` applies it as a first apply, restarting the whole stack.
* `run` applies the file on start, then checks it every `--poll-interval` seconds (30) and applies it when it changes.
  On start, it checks that the stack is up; when it is not (for example, after a reboot), the file is applied whole.
  Until the file exists, it waits and changes nothing.

Options:

**–config-file path** The configuration file. It can be given more than once; the watcher watches every path and applies the one that changed last.

**–monitoring-dir path** The monitoring directory, where `start-all.sh` is. The watcher runs the start scripts from it.

**–compose** Run the stack with Docker Compose instead of `start-all.sh`. See [Docker Compose](https://monitoring.docs.scylladb.com/master/install/docker-compose.md).

**–strict** Reject fields the schema does not define.

**–auto-revert** When an apply fails, apply the previous configuration again.

**–state-dir path** Where the last applied configuration and the status are kept (default: `<monitoring-dir>/config-state`).

**–staging-dir path** Where the derived files are generated (default: `<monitoring-dir>/config-build`).

**–cert-dir path** Where the TLS certificates are installed (default: `/etc/scylla-monitoring/certs`).

**–root-helper path** The root helper (default: `<monitoring-dir>/scylla-monitoring-root.sh`).

**–health-timeout seconds** How long to wait for the components to become ready after an apply (default: 180).

**–poll-interval seconds** How often `run` checks the file (default: 30).

### As a systemd Service

Run the watcher as a service, for example with `/etc/systemd/system/scylla-monitoring-config.service`:

```ini
[Unit]
Description=Configure the monitoring stack from its config file
After=docker.service network-online.target
Wants=network-online.target
PartOf=docker.service

[Service]
User=scylla
WorkingDirectory=/opt/scylla-monitoring
ExecStart=/usr/bin/python3 /opt/scylla-monitoring/scylla_monitoring_config.py run --monitoring-dir /opt/scylla-monitoring --config-file /etc/scylla-monitoring/scylla-monitoring.yaml --root-helper /usr/local/sbin/scylla-monitoring-root.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

The watcher’s user needs to read the config file. It writes the status next to the file when it can write to that directory,
and always in the state directory. When the data directories are on a separate disk, add `RequiresMountsFor=<data dir>` in a drop-in.

* `systemctl stop scylla-monitoring-config` stops the watcher; `./kill-all.sh --traefik` (or `docker compose down`) then stops the containers, traefik included.
* `systemctl start scylla-monitoring-config` starts the watcher, which brings the stack up.

## How Changes Are Applied

Each apply validates the file, renders the derived files and checks them with `promtool` and `amtool`.
If the file or a derived file is invalid, the running stack is left as it is, and the status file says why.
Otherwise the watcher compares each section with the last applied configuration and runs what the changed sections need:

| Change                                            | What runs                                                        |
|---------------------------------------------------|------------------------------------------------------------------|
| `targets`                                         | nothing; Prometheus reads the new targets                        |
| `alert_rules`                                     | Prometheus reload                                                |
| `alertmanager_config`                             | Alertmanager reload                                              |
| `cluster`                                         | the Prometheus configuration is generated again, then reloaded   |
| `grafana.admin_password`                          | the password is set in Grafana                                   |
| `grafana.datasource`                              | the data source is written, then Grafana restarts                |
| `tls` certificates                                | the certificates are installed, then traefik reloads them        |
| `tls.enabled`, `tls.listen_ip`                    | traefik starts, restarts or is removed                           |
| `systemd`                                         | the unit’s drop-in is written or removed, then the unit restarts |
| `stack`, `storage`, `prometheus`, other `grafana` | the stack restarts                                               |

Adding or removing `alert_rules`, `alertmanager_config` or `targets.vector_search` also restarts the stack.

A `systemd` entry maps a unit name to the content of a drop-in, written as
`/etc/systemd/system/<unit>.d/50-scylla-monitoring.conf`. The watcher owns only that file.
Keep secrets out of drop-ins: systemd shows a unit’s settings, `Environment=` included, to every user on the host.
For example, the node_exporter unit installed by the ScyllaDB images ends its command line with `$NODE_EXPORTER_ARGS`,
so a drop-in can set its arguments:

```yaml
systemd:
  node-exporter.service: |
    [Service]
    Environment=NODE_EXPORTER_ARGS=--web.listen-address=127.0.0.1:9100
```

With `tls.enabled`, traefik serves the stack on `tls.listen_ip` with mutual TLS.
Set `stack.bind_address` to `127.0.0.1` as well, so traefik is the only way in.

## The Status File

After each apply, the watcher writes `status.json` in the state directory, and `scylla-monitoring.status.json`
next to each config file:

```json
{"generation": "9f2c", "state": "applied", "time": "2026-10-20T10:00:00Z"}
{"generation": "a1b3", "state": "rejected", "error": "alert_rules: ...", "time": "2026-10-20T10:05:00Z"}
```

* `applied`: the stack runs the configuration of `generation`.
* `rejected`: the file is invalid; the stack still runs `applied_generation`.
* `failed`: the apply failed; the stack is left as the failed apply left it, for inspection. The next apply runs every action, as a first apply does.
* `reverted`: the apply failed and, with `--auto-revert`, the previous configuration was applied again.

Error messages name the section and position, without the values, since the file holds secrets.

#### NOTE
`start-all.sh` and the start scripts still read `env.sh` from the monitoring directory, and what it sets can override the file.
The watcher logs a warning when `env.sh` exists.
