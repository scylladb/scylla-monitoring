# TODO — `scylla-monitor-ctl` Implementation

Actionable items derived from [DESIGN.md](./DESIGN.md).

---

## Phase 0: Project Scaffolding

- [x] Initialize Go module (`go mod init`) and directory structure per the package layout in DESIGN.md
- [x] Set up `main.go` with Cobra root command (`cmd/root.go`)
- [x] Add Viper config file loading (defaults → `scylla-monitor.yaml` → CLI flags)
- [x] Create `assets/` directory and copy all embeddable files from their current locations:
  - `grafana/types.json` → `assets/grafana/types.json`
  - `grafana/*.template.json` → `assets/grafana/`
  - `grafana/datasource*.yml` → `assets/grafana/`
  - `grafana/load.yaml` → `assets/grafana/`
  - `prometheus/prometheus.yml.template` → `assets/prometheus/`
  - `prometheus/prometheus.consul.yml.template` → `assets/prometheus/`
  - `prometheus/prom_rules/*.yml` → `assets/prometheus/prom_rules/`
  - `prometheus/rule_config.yml` → `assets/alertmanager/rule_config.yml`
  - `loki/conf/loki-config.template.yaml` → `assets/loki/conf/`
  - `loki/promtail/promtail_config.template.yml` → `assets/loki/promtail/`
  - `docker-compose.template.yml` → `assets/`
- [x] Declare all `go:embed` variables in an `assets.go` file
- [x] Convert `versions.sh` to `assets/versions.yaml` (structured YAML with `stack_versions`, `container_images`, `stack_ports`, `default_dashboards`)
- [x] Write `pkg/versions/matrix.go` to parse `versions.yaml` and expose lookup functions
- [x] Write `pkg/versions/matrix_test.go` — verify supported versions, defaults, and port lookups
- [x] Add key dependencies to `go.mod`: `cobra`, `viper`, `docker/docker`, `yaml.v3`, `archiver/v4`

---

## Phase 1: Core Engines + Offline Generation

### Dashboard Type Engine (`pkg/dashboard/`)

- [x] Implement `ResolveType()` in `pkg/dashboard/types.go` — recursive class-based inheritance resolution from `types.json`
- [x] Implement `UpdateObject()` in `pkg/dashboard/types.go` — recursive JSON tree walker that:
  - Resolves `"class"` references at each level
  - Replaces `"id": "auto"` with auto-incrementing integers
  - Filters by `"dashversion"` (version rejection)
  - Filters by `"dashproduct"` / `"dashproductreject"` (product rejection)
  - Applies exact-match replacements from metrics/replace files
  - Recurses into arrays (filtering out nil results) and nested objects
- [x] Write `pkg/dashboard/types_test.go` — compare output against Python `make_dashboards.py` for identical inputs

### Version Comparison (`pkg/dashboard/`)

- [x] Implement `IsVersionBigger()` in `pkg/dashboard/version.go` — supports `>5.0`, `<2024.1`, exact match; `"master"` = 666
- [x] Implement `ShouldVersionReject()` — handles `"dashversion"` as string or list of strings
- [x] Write `pkg/dashboard/version_test.go` — cover `5.4` vs `6.0`, `2024.1` enterprise format, `master` comparisons, operator prefixes

### Grafana 5 Layout (`pkg/dashboard/`)

- [x] Implement `ConvertToGrafana5Layout()` in `pkg/dashboard/layout.go` — row-to-panel conversion with `gridPos` (24-unit grid, height = px/30, collapsible row support)
- [x] Write `pkg/dashboard/layout_test.go`

### Dashboard Generator (`pkg/dashboard/`)

- [x] Implement `Generator` struct and `Generate()` in `pkg/dashboard/generator.go` — orchestrates: load types.json → load template → resolve types → update objects → Grafana 5 layout → string replacements → JSON output
- [x] String replacements: `__MONITOR_VERSION__`, `__SCYLLA_VERSION_DOT__`, `__SCYLLA_VERSION_DASHED__`, `__MONITOR_BRANCH_VERSION`, `__REFRESH_INTERVAL__`
- [x] JSON output must match Python: `sort_keys=True`, 4-space indent, `(',', ': ')` separators
- [x] Write `pkg/dashboard/generator_test.go` — compare generated JSON byte-for-byte with Python output for a known template+types pair
- [x] Create `testdata/types_small.json`, `testdata/template_small.json`, and `testdata/expected_output/` for comparison tests

### Target File Generator (`pkg/targets/`)

- [x] Implement `GenerateTargets()` in `pkg/targets/generator.go` — parse `--targets "dc1:ip1,ip2 dc2:ip3"` format with cluster name, output Prometheus target YAML
- [x] Support alias separator (`--alias-separator =`) with per-node `instance` label
- [x] Implement `ParseNodetoolStatus()` in `pkg/targets/nodetool.go` — parse piped `nodetool status` output into targets
- [x] Write `pkg/targets/generator_test.go` — verify YAML output matches current `genconfig.py` output

### Prometheus Config Generator (`pkg/prometheus/`)

- [x] Implement `GenerateConfig()` in `pkg/prometheus/config.go` — structured YAML generation (not sed):
  - Base from `prometheus.yml.template` or `prometheus.consul.yml.template`
  - Substitute `AM_ADDRESS`, `GRAFANA_ADDRESS`, `MANAGER_ADDRESS`
  - Add `metric_relabel_configs` drop rules for `--drop-metrics` (cas, cdc, etc.)
  - Custom metric regex drops (`--drop-metrics-regex`)
  - Override `scrape_interval` and calculate `scrape_timeout = interval - 5s`
  - Override `evaluation_interval`
  - Set `scrape_native_histograms: true` when `--native-histogram`
  - Derive node exporter targets from ScyllaDB targets (strip port, add `:9100`) when no separate file
  - Derive manager agent targets similarly (`:5090`)
  - Append vector search scrape jobs
  - Append additional target files (`-T`)
- [x] Implement `pkg/prometheus/metrics.go` — predefined metric filter categories (cas, cdc, alternator, streaming, sstable, cache, commitlog, compaction) with regex patterns
- [x] Write `pkg/prometheus/config_test.go` and `pkg/prometheus/metrics_test.go`

### Grafana Datasource Generator

- [ ] Implement datasource provisioning file generation (prometheus, alertmanager, loki, scylla-datasource, thanos) — port of `grafana-datasource.sh`

### CLI Commands (Phase 1)

- [x] Implement `cmd/version.go` — `scylla-monitor-ctl version [--supported]`
- [x] Implement `cmd/dashboards.go` — `dashboards generate` subcommand with flags: `--scylla-version`, `--manager-version`, `--output-dir`, `--force`, `--dashboards`, `--refresh-interval`
- [x] Implement `cmd/targets.go` — `targets generate` subcommand with flags: `--targets`, `--cluster`, `--output`, `--from-nodetool`, `--alias-separator`
- [x] Implement `cmd/prometheus.go` — `prometheus config` subcommand with flags: `--alertmanager-address`, `--grafana-address`, `--output`, `--consul-address`, `--drop-metrics`, `--scrape-interval`, `--native-histogram`, `--vector-search`

---

## Phase 2: Container Orchestration + Deploy/Destroy

### Docker SDK Integration (`pkg/docker/`)

- [ ] Implement `pkg/docker/detect.go` — detect Docker vs Podman (`docker --help | grep podman`), set `--userns=keep-id` for Podman
- [ ] Implement `pkg/docker/network.go` — create/remove Docker network (`monitor-net` / `monitor-net<stack-id>`)
- [ ] Implement `pkg/docker/container.go` — container lifecycle using Docker SDK (`github.com/docker/docker/client`):
  - `StartContainer()` — pull image, create, start
  - `StopContainer()` — SIGTERM, wait, kill, remove
  - `InspectContainer()` — get IP, status, uptime
  - `WaitForHealth()` — poll HTTP endpoint with retries (configurable per component)
- [ ] Implement `pkg/docker/compose.go` — generate `docker-compose.yml` and `.env` from `docker-compose.template.yml` (port of `make-compose.sh`)

### Stack Orchestration (`pkg/stack/`)

- [ ] Implement `pkg/stack/deploy.go` — full stack deployment sequence:
  1. Create Docker network
  2. Resolve target files
  3. Start AlertManager → capture IP:port
  4. Start Loki+Promtail → capture Loki IP:port
  5. Generate Prometheus config
  6. Start Prometheus (or VictoriaMetrics)
  7. Wait for Prometheus health
  8. Optionally start Thanos sidecar/query
  9. Optionally start Datadog agent
  10. Start Grafana with all datasource addresses
  11. Wait for Grafana health
  12. Save metadata to `$DATA_DIR/scylla.txt`
- [ ] Implement `pkg/stack/destroy.go` — teardown sequence: SIGTERM Prometheus (wait up to 120s), kill+remove all containers, remove network
- [ ] Implement `pkg/stack/status.go` — inspect all containers, collect versions/uptime/addresses/disk-usage

### Multi-Stack Support

- [ ] Implement stack ID-based port resolution from `versions.yaml` (`stack_ports`)
- [ ] Implement stack-specific container naming (`aprom-<port>`, `agraf-<port>`, etc.)
- [ ] Implement stack-specific network naming (`monitor-net<id>`)

### CLI Commands (Phase 2)

- [ ] Implement `cmd/deploy.go` — full flag set from DESIGN.md (all 50+ flags mapped from `start-all.sh`)
- [ ] Implement `cmd/destroy.go` — `destroy [--stack <id>] [--force] [--keep-data]`
- [ ] Implement `cmd/status.go` — `status [--stack <id>]` with tabular output

---

## Phase 3: Remote API Operations

### Grafana API Client (`pkg/grafana/`)

- [ ] Implement `pkg/grafana/client.go` — HTTP client with auth (basic auth: user/password), base URL, timeout
- [ ] Implement `pkg/grafana/datasource.go` — create/update/list datasources (`POST /api/datasources`, `PUT /api/datasources/:id`, `GET /api/datasources`)
- [ ] Implement `pkg/grafana/dashboard.go` — upload (`POST /api/dashboards/db` with `overwrite: true`), download (`GET /api/dashboards/uid/:uid`), search (`GET /api/search`)
- [ ] Implement `pkg/grafana/folder.go` — create/list folders, set folder permissions
- [ ] Implement health check (`GET /api/health`) and org check (`GET /api/org`)
- [ ] Write `pkg/grafana/client_test.go` — test with httptest mock server

### Prometheus API Client (`pkg/prometheus/`)

- [ ] Implement `pkg/prometheus/client.go` — hot-reload (`POST /-/reload`), snapshot (`POST /api/v1/admin/tsdb/snapshot`), health check

### CLI Commands (Phase 3)

- [ ] Implement `cmd/configure.go` — `configure` command: create/update datasources + generate/upload dashboards to pre-existing Grafana+Prometheus
- [ ] Implement `cmd/dashboards.go` additions:
  - `dashboards upload` — upload to running Grafana by URL
  - `dashboards download` — download all dashboards from Grafana to local directory
  - `dashboards list` — list available dashboards and versions
- [ ] Implement `cmd/upgrade.go` — `upgrade` command: connect to Grafana API → generate dashboards → upload with overwrite → optionally update datasources → optionally reload Prometheus
- [ ] Implement `cmd/prometheus.go` addition: `prometheus reload`

---

## Phase 4: Tuning + Metric Filtering

- [ ] Implement `cmd/tune.go` — `tune` command:
  - Read current `prometheus.yml` from file path or Docker volume
  - Parse YAML structurally
  - Add/remove `metric_relabel_configs` drop rules by category or custom regex
  - Adjust global `scrape_interval` and `evaluation_interval`
  - Enable/disable `scrape_native_histograms`
  - Write updated config
  - Optionally trigger `POST /-/reload` on Prometheus
- [ ] Implement `--keep-metrics` flag — whitelist specific metrics that should never be dropped
- [x] Implement predefined metric filter categories mapping in `pkg/prometheus/metrics.go`:
  - `cas` → `.*_cas.*`
  - `cdc` → `.*_cdc_.*`
  - `alternator` → `.*alternator.*`
  - `streaming` → `.*streaming.*`
  - `sstable` → `.*sstable.*`
  - `cache` → `.*cache.*`
  - `commitlog` → `.*commitlog.*`
  - `compaction` → `.*compaction.*`

---

## Phase 5: Migration + Backup

### Export (`pkg/migrate/`)

- [ ] Implement `pkg/migrate/export.go`:
  - Prometheus snapshot via `POST /api/v1/admin/tsdb/snapshot` + `docker cp`
  - Grafana dashboard export via API (`GET /api/search` → `GET /api/dashboards/uid/:uid`, strip `"id"`, keep `"uid"`)
  - Grafana datasource export (`GET /api/datasources`)
  - Grafana folder export (`GET /api/folders`)
  - Collect config files (prometheus.yml, alert rules, alertmanager config, loki config, target files)
  - Write `metadata.yaml` (export timestamp, versions, source info)
- [ ] Implement `pkg/migrate/archive.go` — pack/unpack tar.gz archives using `archiver/v4`

### Import (`pkg/migrate/`)

- [ ] Implement `pkg/migrate/import.go`:
  - Extract archive
  - Read and validate `metadata.yaml`
  - Place Prometheus snapshot data in data-dir
  - Place AlertManager and Loki data (optional)
  - Deploy stack with extracted configs and target files
  - Wait for Grafana, create datasources, upload dashboards, recreate folders

### Live Copy (`pkg/migrate/`)

- [ ] Implement `pkg/migrate/copy.go`:
  - Download dashboards, datasources, folders from source Grafana
  - Create folders on target
  - Adjust datasource URLs to target addresses
  - Upload datasources and dashboards to target
  - Optionally copy Prometheus data (snapshot source → streaming tar → import to target)

### CLI Commands (Phase 5)

- [ ] Implement `cmd/migrate.go`:
  - `migrate export` with flags: `--prometheus-url` (enables metric data export), `--grafana-url`, `--grafana-user`, `--grafana-password`, `--output`
  - `migrate import` with flags: `--archive`, `--data-dir`, `--grafana-data-dir`, `--grafana-port`
  - `migrate copy` with flags: `--source-grafana`, `--target-grafana`, `--include-dashboards`, `--include-datasources`
- [ ] Implement `cmd/backup.go` — convenience wrappers calling `pkg/migrate/` directly (no separate `pkg/backup/`):
  - `backup create` — calls `migrate.ArchiveStack()` with pre-filled local config defaults
  - `backup restore` — calls `migrate.RestoreStack()`

---

## Phase 6: Docker Compose Mode + Advanced Features

- [ ] Implement `deploy --mode=compose` — generate `docker-compose.yml` + `.env` instead of direct `docker run`
- [ ] Implement VictoriaMetrics support — swap Prometheus image/config when `--victoria-metrics` is passed
- [ ] Implement Thanos support:
  - Thanos sidecar (`--thanos-sidecar`) — mount Prometheus data, gRPC/HTTP endpoints
  - Thanos query (`--thanos-query`) — unified query across sidecars
  - Local Thanos (`--thanos-local`) — query connected to local sidecar
  - Optional Thanos datasource in Grafana
- [ ] Implement Datadog integration — `--datadog-api-key`, `--datadog-hostname`, config generation, agent container
- [ ] Implement support dashboard folder permissions via Grafana API (`POST /api/folders/:uid/permissions`)
- [ ] Implement LDAP configuration support (`--ldap-config` → Grafana LDAP auth, disable anonymous)

---

## Cross-Cutting Concerns

- [x] Implement `pkg/config/config.go` — unified config loading: defaults → `scylla-monitor.yaml` → env vars → CLI flags (Viper)
- [x] Implement `pkg/config/defaults.go` — all default values in one place
- [x] Add `--config` global flag to specify config file path
- [x] Add `--verbose` / `--quiet` global flags for log level control
- [x] Add `--dry-run` global flag to preview actions without executing
- [ ] Ensure all commands are idempotent (re-running produces the same result)
- [ ] Ensure proper error handling with meaningful messages (replace silent failures from bash scripts)
- [ ] Add CI workflow for `go build`, `go test`, `go vet`, `golangci-lint`
- [x] Add a Makefile with targets: `build`, `test`, `lint`, `generate-assets` (copy files into `assets/`)
- [x] Write integration test: generate dashboards with Go tool, compare output to Python `make_dashboards.py` output for all default dashboards
