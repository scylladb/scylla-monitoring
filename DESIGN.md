# DESIGN.md — `scylla-monitor-ctl` Go CLI

A single Go binary that replaces the existing shell-script-based monitoring stack management with a flexible, remote-capable, idempotent tool.

---

## Table of Contents

1. [Motivation](#motivation)
2. [CLI Command Structure](#cli-command-structure)
3. [Current → New Mapping](#current--new-mapping)
4. [Embedded Assets](#embedded-assets)
5. [Core Engines](#core-engines)
6. [Command Reference](#command-reference)
7. [Configuration File](#configuration-file)
8. [Go Package Layout](#go-package-layout)
9. [Key Dependencies](#key-dependencies)
10. [Migration & Backup Subsystem](#migration--backup-subsystem)
11. [Implementation Phases](#implementation-phases)

---

## Motivation

The current tooling is ~4,800 lines of bash + ~700 lines of Python spread across 33 scripts. Problems:

- Cannot operate on remote Grafana/Prometheus (everything assumes local Docker)
- No upgrade path (must `kill-all.sh` then `start-all.sh` again)
- No migration/backup capability
- Metric filtering is sed-regex injection, not structured
- Error handling is fragile (silent failures, cryptic messages)
- Requires Python, bash, sed, curl, docker CLI on the host
- Not testable

The Go binary solves all of these: single binary, zero runtime deps (except Docker socket for container ops), remote API support, structured config, proper error handling, unit-testable.

---

## CLI Command Structure

```
scylla-monitor-ctl
├── deploy          # Deploy a new monitoring stack from scratch
├── destroy         # Tear down a running stack
├── upgrade         # Upgrade dashboards/configs on a running stack
├── configure       # Point a fresh/existing Grafana+Prometheus at a ScyllaDB cluster
├── tune            # Adjust Prometheus scraping, metric filtering, intervals
├── dashboards      # Dashboard generation and management
│   ├── generate    # Generate dashboard JSON files from templates
│   ├── upload      # Upload dashboards to a running Grafana
│   ├── download    # Download dashboards from a running Grafana
│   └── list        # List available dashboards and versions
├── targets         # Target file management
│   ├── generate    # Generate Prometheus target YAML from node list
│   ├── validate    # Check target files and test connectivity
│   └── show        # Display current targets
├── prometheus      # Prometheus configuration management
│   ├── config      # Generate prometheus.yml
│   ├── reload      # Hot-reload Prometheus config via /-/reload API
│   └── rules       # List/validate alert rules
├── migrate         # Full stack migration
│   ├── export      # Export entire stack (data + dashboards + config)
│   ├── import      # Import a previously exported stack
│   └── copy        # Live copy from source to destination
├── backup          # Backup/restore (convenience wrapper around migrate)
│   ├── create      # Create a backup (calls migrate export with local defaults)
│   └── restore     # Restore from a backup (calls migrate import)
├── status          # Show status of all stack components
└── version         # Show version info and supported ScyllaDB versions
```

---

## Current → New Mapping

### Script-level mapping

| Current script | New command | Notes |
|---|---|---|
| `start-all.sh` | `deploy` | Full stack deployment |
| `start-all.sh --compose` | `deploy --mode=compose` | Docker Compose mode |
| `kill-all.sh` | `destroy` | Tear down all containers |
| `start-grafana.sh` | `deploy --component=grafana` | Single component |
| `start-alertmanager.sh` | `deploy --component=alertmanager` | Single component |
| `start-loki.sh` | `deploy --component=loki` | Single component |
| `start-thanos.sh` | `deploy --component=thanos-query` | Single component |
| `start-thanos-sc.sh` | `deploy --component=thanos-sidecar` | Single component |
| `start-grafana-renderer.sh` | `deploy --component=renderer` | Single component |
| `start-datadog.sh` | `deploy --component=datadog` | Single component |
| `generate-dashboards.sh` | `dashboards generate` | Dashboard generation |
| `make_dashboards.py` | (internal engine) | Ported to Go, `pkg/dashboard/` |
| `prometheus-config.sh` | `prometheus config` | Prometheus config generation |
| `grafana-datasource.sh` | `configure --datasources` | Or part of `deploy` |
| `load-grafana.sh` | `dashboards upload` | API-based dashboard loading |
| `genconfig.py` | `targets generate` | Target file generation |
| `kill-container.sh` | (internal helper) | Used by `destroy` |
| `versions.sh` | (embedded data) | `go:embed versions.yaml` |
| `dashboards.sh` | (embedded data) | Hardcoded default list |
| `upload_report.sh` | `backup create --upload` | With optional upload |
| `alternator-start-all.sh` | `deploy --solution=alternator` | Solution preset |
| `enterprise-start-all.sh` | `deploy --enterprise` | Enterprise preset |
| `generate-alternator.sh` | `dashboards generate --solution=alternator` | |
| `make-compose.sh` | `deploy --mode=compose` | Compose generation |
| `UA.sh` | (removed or embedded) | Analytics ID |
| `enterprise_versions.sh` | (embedded data) | Merged into versions |
| `start-all-ec2.sh` | (removed) | Deprecated |
| `start-all-local.sh` | (removed) | Deprecated |

### NEW functionality (not in current scripts)

| New command | What it does |
|---|---|
| `upgrade` | Update dashboards and configs on a live stack without restart |
| `migrate export` | Snapshot Prometheus data + export Grafana dashboards + configs |
| `migrate import` | Restore a full stack from an export archive |
| `migrate copy` | Live copy from one stack to another |
| `backup create` | Convenience wrapper: calls `migrate export` with local defaults |
| `backup restore` | Convenience wrapper: calls `migrate import` |
| `tune` | Modify metric filtering, scrape intervals, alert rules on the fly |
| `status` | Health check all components, show versions, disk usage |
| `targets validate` | Test connectivity to ScyllaDB nodes |
| `prometheus reload` | Hot-reload config without container restart |

---

## Embedded Assets

All template/config files are embedded into the binary via `go:embed`:

```go
//go:embed assets/grafana/types.json
var typesJSON []byte

//go:embed assets/grafana/*.template.json
var dashboardTemplates embed.FS

//go:embed assets/prometheus/prometheus.yml.template
var prometheusTemplate []byte

//go:embed assets/prometheus/prometheus.consul.yml.template
var prometheusConsulTemplate []byte

//go:embed assets/prometheus/prom_rules/*.yml
var alertRules embed.FS

//go:embed assets/grafana/datasource.yml
var datasourceTemplate []byte

//go:embed assets/grafana/datasource.loki.yml
var datasourceLokiTemplate []byte

//go:embed assets/grafana/datasource.scylla.yml
var datasourceScyllaTemplate []byte

//go:embed assets/grafana/load.yaml
var loadTemplate []byte

//go:embed assets/loki/conf/loki-config.template.yaml
var lokiConfigTemplate []byte

//go:embed assets/loki/promtail/promtail_config.template.yml
var promtailConfigTemplate []byte

//go:embed assets/alertmanager/rule_config.yml
var alertmanagerDefaultConfig []byte

//go:embed assets/docker-compose.template.yml
var composeTemplate []byte

//go:embed assets/versions.yaml
var versionsData []byte
```

The `versions.yaml` is generated from the current `versions.sh` as a structured YAML:

```yaml
stack_versions:
  "4.14":
    supported_scylla: ["2024.1", "2024.2", "2025.1", "2025.2", "2025.3", "2025.4", "2026.1", "master"]
    default_scylla: "2025.3"
    default_enterprise: "2025.4"
    manager_supported: ["3"]
    manager_default: "3"
    vector_default: "1"
  # ... all versions

container_images:
  prometheus: "v3.9.1"
  alertmanager: "v0.30.1"
  grafana: "12.3.2"
  loki: "3.6.4"
  grafana_renderer: "v5.4.0"
  thanos: "v0.40.1"
  victoria_metrics: "v1.96.0"

stack_ports:
  1: { prometheus: 9051, grafana: 3001, alertmanager: 9041 }
  2: { prometheus: 9052, grafana: 3002, alertmanager: 9042 }
  3: { prometheus: 9053, grafana: 3003, alertmanager: 9043 }
  4: { prometheus: 9054, grafana: 3004, alertmanager: 9044 }

default_dashboards:
  - scylla-overview
  - scylla-detailed
  - scylla-os
  - scylla-cql
  - scylla-advanced
  - alternator
  - scylla-ks
```

---

## Core Engines

### 1. Dashboard Type Engine (port of `make_dashboards.py`)

This is the most critical piece. The Python implementation has these operations that must be faithfully ported:

**Type resolution** (`get_type` → Go: `ResolveType`):
```
Input: type name + types map
Process: recursive lookup via "class" field, merge parent fields (parent does NOT override child)
Output: fully resolved type object
```

Current Python (lines 130-140 of `make_dashboards.py`):
```python
def get_type(name, types):
    if name not in types:
        return {}
    if "class" not in types[name]:
        return types[name]
    result = types[name].copy()
    cls = get_type(types[name]["class"], types)
    for k in cls:
        if k not in result:
            result[k] = cls[k]
    return result
```

Go equivalent:
```go
func ResolveType(name string, types map[string]map[string]interface{}) map[string]interface{} {
    t, ok := types[name]
    if !ok {
        return map[string]interface{}{}
    }
    className, hasClass := t["class"].(string)
    if !hasClass {
        return copyMap(t)
    }
    result := copyMap(t)
    parent := ResolveType(className, types)
    for k, v := range parent {
        if _, exists := result[k]; !exists {
            result[k] = v
        }
    }
    return result
}
```

**Version filtering** (`is_version_bigger` / `should_version_reject`):
- Compares ScyllaDB version numbers (handles both `5.4` and `2024.1` enterprise formats)
- Supports operators: `>5.0`, `<2024.1`, `5.4` (exact match)
- `"dashversion"` field can be a string or list of strings
- `"master"` version is represented as 666 (bigger than everything except `>` comparisons)

**Object update** (`update_object` → Go: `UpdateObject`):
- Recursively walks JSON object tree
- Resolves `"class"` references at each level
- Replaces `"id": "auto"` with auto-incrementing integer
- Removes objects where version filtering rejects them (returns nil)
- Removes objects where product filtering rejects them (`"dashproduct"`, `"dashproductreject"`)
- Applies exact-match replacements from `--replace-file` (e.g. `metrics.yaml`)
- Recurses into arrays (filtering out nil results) and nested objects

**Grafana 5 layout** (`make_grafana_5` → Go: `ConvertToGrafana5Layout`):
- Converts row-based layout to panel-based layout with `gridPos`
- Handles collapsible rows (panels nested inside a row panel)
- Calculates x/y positions based on panel widths (24-unit grid)
- Height conversion: pixel value / 30

**String replacements** (applied after JSON serialization):
- `__MONITOR_VERSION__` → monitoring stack version
- `__SCYLLA_VERSION_DOT__` → ScyllaDB version (e.g., "6.2")
- `__SCYLLA_VERSION_DASHED__` → ScyllaDB version with dashes (e.g., "6-2") — auto-derived from `_DOT__` suffix
- `__MONITOR_BRANCH_VERSION` → branch version
- `__REFRESH_INTERVAL__` → dashboard refresh interval (default: "5m")

**Output**: JSON with `sort_keys=True`, 4-space indent, `(',', ': ')` separators — must match Python's `json.dumps` output for compatibility.

### 2. Prometheus Config Generator (port of `prometheus-config.sh`)

Currently: sed substitutions on template files.

New approach: structured Go generation using `prometheus/prometheus` Go types or raw YAML manipulation.

**Base templates** (embedded):
- `prometheus.yml.template` — file-based service discovery
- `prometheus.consul.yml.template` — Consul-based service discovery (when using Scylla Manager)

**Substitutions applied:**
| Placeholder | Source |
|---|---|
| `AM_ADDRESS` | AlertManager container IP:port |
| `GRAFANA_ADDRESS` | Grafana container name:port (default: `agraf:3000`) |
| `MANAGER_ADDRESS` | Consul/Manager address:port (consul template only) |

**Dynamic modifications (currently done by sed, new tool does structurally):**

1. **Metric filtering** (`--no-cas`, `--no-cdc`):
   - Currently: injects a `metric_relabel_configs` drop rule via sed at the `# FILTER_METRICS` marker
   - New: adds relabel config entries to the scylla job's `metric_relabel_configs` list
   - CAS pattern: `.*_cas.*`
   - CDC pattern: `.*_cdc_.*`

2. **Custom metric drops** (NEW — not in current scripts):
   - User specifies metric name patterns to drop
   - Tool generates proper `metric_relabel_configs` entries with `action: drop`
   - Example: `--drop-metrics "alternator,cdc,cas,streaming"`

3. **Scrape interval** (`--scrap`):
   - Replaces `scrape_interval` in global config
   - Adjusts `scrape_timeout` to `interval - 5s`

4. **Evaluation interval** (`--evaluation-interval`):
   - Replaces `evaluation_interval` in global config

5. **Native histograms** (`--native-histogram`):
   - Sets `scrape_native_histograms: true` in global config

6. **Node exporter port mapping** (`--no-node-exporter-file`):
   - When no separate node exporter target file exists, adds relabel rules to derive node exporter targets from ScyllaDB targets (strip port, add `:9100`)

7. **Manager agent port mapping** (`--no-manager-agent-file`):
   - Same pattern: derive manager agent targets from ScyllaDB targets (strip port, add `:5090`)

8. **Vector search jobs** (`--vector-search`):
   - Appends two additional scrape jobs: `vector_search` (port 6080) and `vector_search_os` (port 9100)

9. **Additional target files** (`-T`):
   - Appends raw YAML content from user-provided files to prometheus.yml

**Scrape jobs in the generated config:**

| Job name | Target source | Default port | Scrape interval |
|---|---|---|---|
| `scylla` | `scylla_servers.yml` or Consul SD | 9180 | 20s (global) |
| `node_exporter` | `node_exporter_servers.yml` or Consul SD | 9100 | 1m |
| `manager_agent` | `scylla_manager_agents.yml` or Consul SD | 5090 | 20s (global) |
| `scylla_manager` | `scylla_manager_servers.yml` or static | — | 20s (global) |
| `prometheus` | localhost:9090 | 9090 | 30s |
| `grafana` | GRAFANA_ADDRESS | 3000 | 30s |
| `vector_search` | `vector_search_servers.yml` (optional) | 6080 | 20s (global) |
| `vector_search_os` | `vector_search_servers.yml` (optional) | 9100 | 20s (global) |

### 3. Grafana API Client

Operations needed:

| Operation | API endpoint | Used by |
|---|---|---|
| Create/update datasource | `POST /api/datasources`, `PUT /api/datasources/:id` | `configure`, `deploy` |
| List datasources | `GET /api/datasources` | `configure`, `status` |
| Upload dashboard | `POST /api/dashboards/db` (with `overwrite: true`) | `dashboards upload`, `upgrade` |
| Download dashboard | `GET /api/dashboards/uid/:uid` | `dashboards download`, `migrate export` |
| Search dashboards | `GET /api/search` | `dashboards list`, `migrate export` |
| Create folder | `POST /api/folders` | `dashboards upload` |
| List folders | `GET /api/folders` | `dashboards list` |
| Set folder permissions | `POST /api/folders/:uid/permissions` | `deploy` (support dashboard) |
| Health check | `GET /api/health` | `status`, startup wait |
| Get org | `GET /api/org` | `status` |

**Datasources created** (from current `grafana-datasource.sh` and `grafana/datasource*.yml`):

1. **prometheus** — type: `prometheus`, URL: `http://<prometheus-address>:9090`, default datasource, timeInterval matches scrape interval
2. **alertmanager** — type: `alertmanager`, URL: `http://<alertmanager-address>:9093`, implementation: `prometheus`
3. **loki** — type: `loki`, URL: `http://<loki-address>:3100` (optional, only when Loki is enabled)
4. **scylla-datasource** — type: `scylladb-scylla-datasource`, optionally with user/password credentials
5. **thanos** — type: `prometheus`, URL: `http://<thanos-address>:10904` (optional, only when Thanos query is enabled)

### 4. Container Orchestrator

Uses Docker SDK (`github.com/docker/docker/client`) instead of CLI. Maps current `docker run` calls.

**Containers managed:**

| Container | Image | Default port | Name pattern |
|---|---|---|---|
| Prometheus | `prom/prometheus:<ver>` | 9090 | `aprom` / `aprom-<port>` |
| Grafana | `grafana/grafana:<ver>` | 3000 | `agraf` / `agraf-<port>` |
| AlertManager | `prom/alertmanager:<ver>` | 9093 | `aalert` / `aalert-<port>` |
| Loki | `grafana/loki:<ver>` | 3100 | `loki` / `loki-<port>` |
| Promtail | `grafana/promtail:<ver>` | 9080 (HTTP), 1514 (binary) | `promtail` / `promtail-<port>` |
| Thanos Query | `thanosio/thanos:<ver>` | 10904 (HTTP), 10903 (gRPC) | `thanos` |
| Thanos Sidecar | `thanosio/thanos:<ver>` | 10911 (gRPC), 10912 (HTTP) | `sidecar<n>` |
| Grafana Renderer | `grafana/grafana-image-renderer:<ver>` | 8081 | `agrafrender` |
| Datadog Agent | `gcr.io/datadoghq/agent:latest` | — | `datadog-agent` |
| VictoriaMetrics | `victoriametrics/victoria-metrics:<ver>` | 9090 | `aprom` (replaces Prometheus) |
| VMAlert | `victoriametrics/vmalert:<ver>` | — | `vmalert` |

**Docker network:** `monitor-net` (or `monitor-net<stack-id>` for secondary stacks).

**Podman support:** Detect via `docker --help | grep podman`, add `--userns=keep-id` arg.

**Startup wait pattern** (replicated from current scripts):
- Each container: start, then poll HTTP endpoint up to N retries (1s interval)
- Prometheus: `GET http://localhost:<port>/` — 35 retries
- Grafana: `GET http://localhost:<port>/api/org` — 35 retries
- AlertManager: `GET http://localhost:<port>/` — 25 retries
- Loki: `GET http://localhost:<port>/` — 25 retries
- Promtail: `GET http://localhost:<port>/` — 25 retries
- `--quick-startup` skips these waits

### 5. Target File Generator (port of `genconfig.py`)

Generates Prometheus target YAML files from various inputs.

**Input formats:**
1. CLI argument: `--targets "dc1:ip1,ip2 dc2:ip3,ip4"` with `--cluster <name>`
2. Piped `nodetool status` output: `nodetool status | scylla-monitor-ctl targets generate --from-nodetool --cluster <name>`
3. Alias support: `--targets "dc1:192.0.2.1=node1,192.0.2.2=node2"` with `--alias-separator =`

**Output format** (YAML, same as current `scylla_servers.yml`):
```yaml
- targets:
    - 172.17.0.2
  labels:
    cluster: cluster1
    dc: dc1
- targets:
    - 172.17.0.3
  labels:
    cluster: cluster1
    dc: dc2
```

When an alias separator is used, each aliased node gets its own entry with an `instance` label.

---

## Command Reference

### `deploy`

Deploys a complete monitoring stack. Replaces `start-all.sh`.

```
scylla-monitor-ctl deploy \
  --scylla-version 6.2 \
  --manager-version 3 \
  --targets-file ./scylla_servers.yml \
  --data-dir /data/prometheus \
  --grafana-data-dir /data/grafana \
  --grafana-port 3000 \
  --prometheus-port 9090 \
  --alertmanager-port 9093 \
  --admin-password secret \
  --bind-address 0.0.0.0 \
  --no-loki \
  --no-renderer \
  --auto-restart \
  --native-histogram \
  --scrape-interval 30s \
  --drop-metrics "cas,cdc" \
  --stack 1
```

**Full flag mapping from `start-all.sh`:**

| `start-all.sh` flag | `deploy` flag | Notes |
|---|---|---|
| `-v <versions>` | `--scylla-version` | |
| `-M <version>` | `--manager-version` | |
| `-d <path>` | `--data-dir` | Prometheus data |
| `-G <path>` | `--grafana-data-dir` | |
| `-s <file>` | `--targets-file` | |
| `-n <file>` | `--node-exporter-file` | |
| `-N <file>` | `--manager-targets-file` | |
| `-p <port>` | `--prometheus-port` | |
| `-g <port>` | `--grafana-port` | |
| `-m <port>` | `--alertmanager-port` | |
| `-a <password>` | `--admin-password` | |
| `-A <ip>` | `--bind-address` | |
| `-l` | `--host-network` | |
| `-L <ip>` | `--consul-address` | |
| `-b <opt>` | `--prometheus-opt` | Repeatable |
| `-c <var>` | `--grafana-env` | Repeatable |
| `-j <dashboard>` | `--extra-dashboard` | Repeatable |
| `-r <file>` | `--alertmanager-config` | |
| `-R <file\|dir>` | `--alert-rules` | |
| `-D <param>` | `--docker-param` | |
| `-C <cmd>` | `--alertmanager-opt` | Repeatable |
| `-Q <role>` | `--anonymous-role` | |
| `-S <set>` | `--solution` | |
| `-T <file>` | `--extra-targets` | Repeatable |
| `-P <file>` | `--ldap-config` | |
| `-f <path>` | `--alertmanager-data-dir` | |
| `-k <path>` | `--loki-data-dir` | |
| `-E` | `--renderer` / `--no-renderer` | |
| `-e` | `--enterprise` | Use enterprise defaults |
| `--compose` | `--mode compose` | |
| `--no-loki` | `--no-loki` | |
| `--no-alertmanager` | `--no-alertmanager` | |
| `--no-renderer` | `--no-renderer` | |
| `--no-cas` | `--drop-metrics cas` | Unified metric filtering |
| `--no-cdc` | `--drop-metrics cdc` | Unified metric filtering |
| `--auto-restart` | `--auto-restart` | |
| `--loki-port` | `--loki-port` | |
| `--promtail-port` | `--promtail-port` | |
| `--promtail-binary-port` | `--promtail-binary-port` | |
| `--thanos-sc` | `--thanos-sidecar` | |
| `--thanos` | `--thanos-query` | |
| `--local-thanos` | `--thanos-local` | |
| `--native-histogram` | `--native-histogram` | |
| `--scrap <s>` | `--scrape-interval` | |
| `--evaluation-interval` | `--evaluation-interval` | |
| `--vector-search <file>` | `--vector-search-file` | |
| `--target-directory` | `--targets-dir` | |
| `--stack <id>` | `--stack` | |
| `--limit <c,p>` | `--container-limit` | Repeatable |
| `--volume <c,s:d>` | `--container-volume` | Repeatable |
| `--param <c,p>` | `--container-param` | Repeatable |
| `--archive <dir>` | `--archive` | |
| `--quick-startup` | `--quick-startup` | |
| `--victoria-metrics` | `--victoria-metrics` | |
| `--alternator` | `--solution alternator` | |
| `--support-dashboard` | `--support-dashboard` | |
| `--auth` | `--auth` | |
| `--disable-anonymous` | `--disable-anonymous` | |
| `--datadog-api-keys` | `--datadog-api-key` | |
| `--datadog-hostname` | `--datadog-hostname` | |
| `--manager-agents` | `--manager-agents-file` | |

### `destroy`

Tears down the stack. Replaces `kill-all.sh`.

```
scylla-monitor-ctl destroy [--stack <id>] [--force] [--keep-data]
```

Sequence: send SIGTERM to Prometheus, wait for graceful shutdown (up to 120s), then kill+remove all containers, remove Docker network.

### `upgrade`

Updates dashboards and configuration on a running stack. **NEW — no current equivalent.**

```
scylla-monitor-ctl upgrade \
  --grafana-url http://localhost:3000 \
  --grafana-user admin \
  --grafana-password admin \
  --scylla-version 6.2 \
  --manager-version 3
```

What it does:
1. Connects to Grafana API
2. Generates dashboards for the target ScyllaDB version (using embedded templates)
3. Uploads each dashboard with `overwrite: true`
4. Updates datasource configurations if needed
5. Optionally updates Prometheus config and triggers hot-reload

### `configure`

Points a fresh or existing Grafana+Prometheus at a ScyllaDB cluster. **NEW — partially covered by `load-grafana.sh`.**

```
scylla-monitor-ctl configure \
  --grafana-url http://grafana:3000 \
  --grafana-user admin \
  --grafana-password admin \
  --prometheus-url http://prometheus:9090 \
  --alertmanager-url http://alertmanager:9093 \
  --loki-url http://loki:3100 \
  --scylla-version 6.2 \
  --manager-version 3
```

What it does:
1. Creates/updates datasources in Grafana (Prometheus, AlertManager, Loki, ScyllaDB)
2. Generates and uploads dashboards for the specified ScyllaDB version
3. Does NOT manage containers — works with pre-existing infrastructure

### `tune`

Adjusts Prometheus configuration on the fly. **NEW.**

```
scylla-monitor-ctl tune \
  --prometheus-url http://localhost:9090 \
  --config-path /etc/prometheus/prometheus.yml \
  --drop-metrics "cas,cdc,alternator,streaming" \
  --keep-metrics "scylla_reactor_utilization,scylla_transport_requests_served" \
  --scrape-interval 30s \
  --evaluation-interval 30s \
  --native-histogram \
  --reload
```

What it does:
1. Reads current `prometheus.yml` (from file path or Docker volume)
2. Parses YAML structurally
3. Modifies `metric_relabel_configs` to add/remove drop rules
4. Adjusts global scrape/evaluation intervals
5. Writes updated config
6. If `--reload`, calls `POST /-/reload` on Prometheus (requires `--web.enable-lifecycle`)

**Metric filter categories** (predefined groups for `--drop-metrics`):

| Category | Regex pattern | Description |
|---|---|---|
| `cas` | `.*_cas.*` | CAS (lightweight transactions) |
| `cdc` | `.*_cdc_.*` | Change Data Capture |
| `alternator` | `.*alternator.*` | DynamoDB-compatible API |
| `streaming` | `.*streaming.*` | Streaming operations |
| `sstable` | `.*sstable.*` | SSTable-level metrics |
| `cache` | `.*cache.*` | Cache metrics |
| `commitlog` | `.*commitlog.*` | Commitlog metrics |
| `compaction` | `.*compaction.*` | Compaction metrics |

Users can also pass raw regex patterns: `--drop-metrics-regex "scylla_my_custom_.*"`

### `dashboards generate`

Generates dashboard JSON files. Replaces `generate-dashboards.sh`.

```
scylla-monitor-ctl dashboards generate \
  --scylla-version 6.2 \
  --manager-version 3 \
  --output-dir ./grafana/build \
  --force \
  --dashboards "scylla-overview,scylla-detailed,scylla-os" \
  --refresh-interval 5m
```

### `dashboards upload`

Uploads dashboards to a running Grafana. Replaces `load-grafana.sh`.

```
scylla-monitor-ctl dashboards upload \
  --grafana-url http://localhost:3000 \
  --grafana-user admin \
  --grafana-password admin \
  --scylla-version 6.2 \
  --source-dir ./grafana/build/ver_6.2
```

### `dashboards download`

Downloads all dashboards from a running Grafana. **NEW.**

```
scylla-monitor-ctl dashboards download \
  --grafana-url http://localhost:3000 \
  --grafana-user admin \
  --grafana-password admin \
  --output-dir ./backup/dashboards
```

### `targets generate`

Generates Prometheus target files. Replaces `genconfig.py`.

```
scylla-monitor-ctl targets generate \
  --targets "dc1:10.0.0.1,10.0.0.2 dc2:10.0.0.3" \
  --cluster my-cluster \
  --output scylla_servers.yml

# Or from nodetool status:
nodetool status | scylla-monitor-ctl targets generate \
  --from-nodetool \
  --cluster my-cluster \
  --output scylla_servers.yml
```

### `targets validate`

Tests connectivity to ScyllaDB nodes. **NEW.**

```
scylla-monitor-ctl targets validate --targets-file scylla_servers.yml
```

Checks: TCP connectivity to port 9180 (ScyllaDB metrics), 9100 (node exporter), 5090 (manager agent).

### `prometheus config`

Generates prometheus.yml. Replaces `prometheus-config.sh`.

```
scylla-monitor-ctl prometheus config \
  --alertmanager-address aalert:9093 \
  --grafana-address agraf:3000 \
  --output ./prometheus/build/prometheus.yml \
  --consul-address 10.0.0.1:5090 \
  --drop-metrics "cas,cdc" \
  --scrape-interval 30s \
  --native-histogram \
  --vector-search
```

### `prometheus reload`

Hot-reloads Prometheus config. **NEW.**

```
scylla-monitor-ctl prometheus reload --prometheus-url http://localhost:9090
```

### `migrate export`

Exports a complete stack for migration or backup. **NEW.**

```
scylla-monitor-ctl migrate export \
  --prometheus-url http://localhost:9090 \
  --grafana-url http://localhost:3000 \
  --grafana-user admin \
  --grafana-password admin \
  --output /backup/stack-export.tar.gz
```

Prometheus metric data is included automatically when `--prometheus-url` is provided.
Without it, only configuration files and Grafana dashboards/datasources are exported
(a warning is logged).

Contents of the archive:
- `dashboards/` — all Grafana dashboards as JSON (exported via API)
- `datasources/` — all datasource definitions (exported via API)
- `folders/` — Grafana folder structure
- `prometheus/` — prometheus.yml and alert rules
- `alertmanager/` — alertmanager config
- `loki/` — loki config
- `targets/` — all target files
- `data/prometheus/` — Prometheus TSDB snapshot (when `--prometheus-url` is provided, via `/api/v1/admin/tsdb/snapshot`)
- `metadata.yaml` — versions, export timestamp, source info

### `migrate import`

Restores from an export archive. **NEW.**

```
scylla-monitor-ctl migrate import \
  --archive /backup/stack-export.tar.gz \
  --data-dir /data/prometheus \
  --grafana-data-dir /data/grafana \
  --grafana-port 3000
```

### `migrate copy`

Live migration from one stack to another. **NEW.**

```
scylla-monitor-ctl migrate copy \
  --source-grafana http://old:3000 \
  --source-grafana-user admin \
  --source-grafana-password admin \
  --target-grafana http://new:3000 \
  --target-grafana-user admin \
  --target-grafana-password admin \
  --include-dashboards \
  --include-datasources
```

### `status`

Shows health and status of all components. **NEW.**

```
scylla-monitor-ctl status [--stack <id>]
```

Output:
```
Component       Status    Version        Address            Uptime
─────────────────────────────────────────────────────────────────────
Prometheus      running   v3.9.1         localhost:9090     3d 12h
Grafana         running   12.3.2         localhost:3000     3d 12h
AlertManager    running   v0.30.1        localhost:9093     3d 12h
Loki            running   3.6.4          localhost:3100     3d 12h
Promtail        running   3.6.4          localhost:9080     3d 12h
Renderer        running   v5.4.0         localhost:8081     3d 12h

ScyllaDB version: 6.2
Manager version:  3
Dashboards:       7 loaded (ver_6.2)
Targets:          3 nodes in 2 DCs
Prometheus data:  12.4 GB (/data/prometheus)
```

### `version`

Shows version info. Replaces `start-all.sh --version`.

```
scylla-monitor-ctl version [--supported]
```

---

## Configuration File

Optional `scylla-monitor.yaml` that can replace command-line flags:

```yaml
scylla_version: "6.2"
manager_version: "3"
enterprise: false

targets:
  file: ./scylla_servers.yml
  # or inline:
  # clusters:
  #   - name: my-cluster
  #     datacenters:
  #       dc1: [10.0.0.1, 10.0.0.2]
  #       dc2: [10.0.0.3]

storage:
  prometheus_data: /data/prometheus
  grafana_data: /data/grafana
  loki_data: /data/loki
  alertmanager_data: /data/alertmanager

ports:
  prometheus: 9090
  grafana: 3000
  alertmanager: 9093
  loki: 3100
  promtail: 9080
  promtail_binary: 1514

auth:
  grafana_admin_password: admin
  anonymous_role: Admin    # Admin/Editor/Viewer
  basic_auth: false
  anonymous: true
  # ldap_config: ./ldap.toml

prometheus:
  scrape_interval: 20s
  evaluation_interval: 20s
  native_histogram: false
  drop_metrics: []          # ["cas", "cdc"]
  drop_metrics_regex: []    # ["scylla_custom_.*"]
  extra_targets: []
  command_line_options: []

components:
  loki: true
  alertmanager: true
  renderer: true
  thanos_sidecar: false
  thanos_query: false
  victoria_metrics: false
  datadog:
    enabled: false
    api_key: ""
    hostname: ""

docker:
  auto_restart: true
  host_network: false
  bind_address: ""
  params: ""                # global Docker params
  container_limits: {}      # per-container: {"prometheus": "--memory=4g"}
  container_volumes: {}
  container_params: {}

dashboards:
  list: []                  # empty = default set
  solution: ""              # "alternator", etc.
  refresh_interval: "5m"
  extra: []                 # additional dashboard templates

stack_id: 0                 # 0 = primary, 1-4 = secondary
```

Loading order: defaults → config file (`--config` or `./scylla-monitor.yaml`) → CLI flags (highest priority).

---

## Go Package Layout

```
scylla-monitor-ctl/
├── main.go
├── go.mod
├── go.sum
├── assets/                          # Embedded via go:embed
│   ├── grafana/
│   │   ├── types.json               # From grafana/types.json
│   │   ├── *.template.json          # From grafana/*.template.json
│   │   ├── datasource.yml           # From grafana/datasource.yml
│   │   ├── datasource.loki.yml
│   │   ├── datasource.scylla.yml
│   │   ├── datasource.psswd.scylla.yml
│   │   ├── load.yaml
│   │   └── plugins/                 # ScyllaDB datasource plugin
│   ├── prometheus/
│   │   ├── prometheus.yml.template
│   │   ├── prometheus.consul.yml.template
│   │   └── prom_rules/
│   │       ├── prometheus.rules.yml
│   │       ├── prometheus.latency.rules.yml
│   │       └── prometheus.table.yml
│   ├── alertmanager/
│   │   └── rule_config.yml
│   ├── loki/
│   │   ├── conf/loki-config.template.yaml
│   │   └── promtail/promtail_config.template.yml
│   ├── docker-compose.template.yml
│   └── versions.yaml
├── cmd/                             # Cobra command definitions
│   ├── root.go                      # Root command, config loading
│   ├── deploy.go                    # deploy command
│   ├── destroy.go                   # destroy command
│   ├── upgrade.go                   # upgrade command
│   ├── configure.go                 # configure command
│   ├── tune.go                      # tune command
│   ├── dashboards.go                # dashboards subcommands
│   ├── targets.go                   # targets subcommands
│   ├── prometheus.go                # prometheus subcommands
│   ├── migrate.go                   # migrate subcommands
│   ├── backup.go                    # backup subcommands (convenience wrappers around migrate)
│   ├── status.go                    # status command
│   └── version.go                   # version command
├── pkg/
│   ├── dashboard/
│   │   ├── types.go                 # Type inheritance engine
│   │   ├── types_test.go            # Test: verify output matches Python
│   │   ├── version.go               # Version comparison logic
│   │   ├── version_test.go
│   │   ├── generator.go             # Dashboard generation orchestrator
│   │   ├── generator_test.go
│   │   ├── layout.go                # Grafana 5 grid layout conversion
│   │   └── layout_test.go
│   ├── prometheus/
│   │   ├── config.go                # prometheus.yml generation
│   │   ├── config_test.go
│   │   ├── rules.go                 # Alert rule management
│   │   ├── metrics.go               # Metric filtering (relabel_config generation)
│   │   ├── metrics_test.go
│   │   └── client.go                # Prometheus API client (reload, snapshot)
│   ├── grafana/
│   │   ├── client.go                # Grafana HTTP API client
│   │   ├── client_test.go
│   │   ├── datasource.go            # Datasource CRUD
│   │   ├── dashboard.go             # Dashboard upload/download
│   │   ├── folder.go                # Folder management
│   │   └── migrate.go               # Full Grafana export/import
│   ├── docker/
│   │   ├── container.go             # Container lifecycle (start, stop, inspect)
│   │   ├── network.go               # Docker network management
│   │   ├── compose.go               # docker-compose.yml generation
│   │   └── detect.go                # Docker/Podman detection
│   ├── targets/
│   │   ├── generator.go             # Target YAML generation (port of genconfig.py)
│   │   ├── generator_test.go
│   │   ├── nodetool.go              # Parse nodetool status output
│   │   └── validator.go             # Connectivity testing
│   ├── versions/
│   │   ├── matrix.go                # Version compatibility matrix
│   │   └── matrix_test.go
│   ├── config/
│   │   ├── config.go                # Config file parsing + flag merging
│   │   └── defaults.go              # Default values
│   ├── stack/
│   │   ├── deploy.go                # Full stack deployment orchestration
│   │   ├── destroy.go               # Stack teardown
│   │   ├── upgrade.go               # In-place upgrade logic
│   │   └── status.go                # Status collection
│   └── migrate/
│       ├── export.go                # Stack export (Prometheus snapshot + Grafana export)
│       ├── import_.go               # Stack import
│       ├── copy.go                  # Live stack-to-stack copy
│       └── archive.go               # tar.gz archive handling
│   # NOTE: No pkg/backup/ — backup commands call pkg/migrate/ directly
└── testdata/                        # Test fixtures
    ├── types_small.json             # Minimal types for unit tests
    ├── template_small.json          # Minimal template for unit tests
    └── expected_output/             # Expected dashboard JSON for comparison tests
```

---

## Key Dependencies

```go
require (
    github.com/spf13/cobra          // CLI framework
    github.com/spf13/viper          // Config file + env var handling
    github.com/docker/docker        // Docker SDK (container management)
    gopkg.in/yaml.v3                // YAML parsing/generation
    github.com/mholt/archiver/v4    // tar.gz archive handling
)
```

No Grafana or Prometheus SDK needed — their APIs are simple REST, implemented with `net/http`.

---

## Migration & Backup Subsystem

All migration and backup logic lives in `pkg/migrate/`. The `backup` CLI commands are
convenience wrappers around `migrate export` / `migrate import` with pre-filled defaults
for local backup workflows (e.g. default config paths). There is no separate `pkg/backup/`
package.

### Export flow (`migrate export`)

```
1. Connect to Prometheus API
   └─ POST /api/v1/admin/tsdb/snapshot → snapshot name
   └─ Docker: cp aprom:/prometheus/snapshots/<name> → local tar

2. Connect to Grafana API
   └─ GET /api/search?type=dash-db → list all dashboards
   └─ For each: GET /api/dashboards/uid/:uid → save JSON (strip "id", keep "uid")
   └─ GET /api/datasources → save all datasource definitions
   └─ GET /api/folders → save folder structure

3. Collect config files
   └─ prometheus.yml (from container or local path)
   └─ alert rules (from prom_rules/ directory)
   └─ alertmanager config (rule_config.yml)
   └─ loki config
   └─ target files (scylla_servers.yml, etc.)

4. Write metadata.yaml
   └─ Export timestamp, versions, source addresses

5. Pack everything into tar.gz archive
```

### Import flow (`migrate import`)

```
1. Extract archive

2. Read metadata.yaml
   └─ Determine versions, validate compatibility

3. If archive includes Prometheus data:
   └─ Place Prometheus snapshot in data-dir

4. Deploy stack with extracted configs
   └─ Use target files from archive
   └─ Use prometheus.yml from archive (or regenerate)
   └─ Use alert rules from archive

5. Wait for Grafana to start
   └─ Create datasources from exported definitions
   └─ Upload dashboards from exported JSON
   └─ Recreate folder structure
```

### Live copy flow (`migrate copy`)

```
1. Connect to source Grafana
   └─ Download all dashboards
   └─ Download all datasources
   └─ Download folder structure

2. Connect to target Grafana
   └─ Create folders
   └─ Adjust datasource URLs to target addresses
   └─ Upload datasources
   └─ Upload dashboards with overwrite: true

3. Optionally copy Prometheus data:
   └─ Snapshot source
   └─ Transfer via streaming tar
   └─ Import to target
```

---

## Implementation Phases

### Phase 1: Core engines + offline generation
- Dashboard type engine (port `make_dashboards.py`)
- Version matrix
- Target file generator (port `genconfig.py`)
- Prometheus config generator (port `prometheus-config.sh`)
- Grafana datasource generator (port `grafana-datasource.sh`)
- `dashboards generate`, `targets generate`, `prometheus config`, `version`
- Unit tests comparing output with Python/bash originals

### Phase 2: Container orchestration + deploy/destroy
- Docker SDK integration (container lifecycle, network management)
- Podman detection and compatibility
- `deploy`, `destroy`, `status`
- Startup wait and health checks
- Multi-stack support

### Phase 3: Remote API operations
- Grafana API client
- `configure`, `dashboards upload`, `dashboards download`, `dashboards list`
- `upgrade`
- `prometheus reload`

### Phase 4: Tuning + metric filtering
- Structured prometheus.yml manipulation
- `tune` command with metric categories
- Custom metric regex support

### Phase 5: Migration + backup
- Prometheus snapshot API integration
- Grafana full export/import
- Archive handling (all in `pkg/migrate/`)
- `migrate export`, `migrate import`, `migrate copy`
- `backup create`, `backup restore` (CLI wrappers calling `pkg/migrate/` directly)

### Phase 6: Docker Compose mode + advanced features
- `deploy --mode=compose` (generate docker-compose.yml + .env)
- VictoriaMetrics support
- Thanos support
- Datadog integration
- Support dashboard folder permissions
- LDAP configuration
