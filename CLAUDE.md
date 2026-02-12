# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ScyllaDB Monitoring Stack — a container-based monitoring solution for ScyllaDB clusters. It orchestrates Prometheus (metrics), Grafana (dashboards), AlertManager (alerts), and optionally Loki/Promtail (logs) via Docker/Podman containers.

Documentation: https://monitoring.docs.scylladb.com

## Key Commands

### Start/Stop the Monitoring Stack
```bash
./start-all.sh -v <scylla-version> -d <prometheus-data-dir>    # start
./kill-all.sh                                                    # stop all containers
```

### Generate Grafana Dashboards
```bash
./generate-dashboards.sh -v <versions> -M <manager-version>    # generate for specific versions
./generate-dashboards.sh -F -v 6.0                              # force regenerate
./generate-dashboards.sh -t                                      # test/validate only (no output)
./generate-dashboards.sh -D                                      # generate all supported versions
```

### Generate Prometheus Target Configuration
```bash
python3 genconfig.py -dc "dc1:ip1,ip2" -c my-cluster -o prometheus/scylla_servers.yml
```

### Build and Test Documentation
```bash
cd docs && make setupenv    # first time: install poetry
cd docs && make test        # build with warnings-as-errors
cd docs && make preview     # live preview on port 5500
```

## Architecture

### Dashboard Generation Pipeline

This is the most complex subsystem. Dashboards are NOT hand-written JSON — they're generated:

1. **`grafana/types.json`** (~4000 lines) — Defines reusable component types (panels, rows, templates) with an inheritance system. A type can specify `"class": "parent_type"` to inherit fields. This is the core definition file for all dashboard UI components.

2. **`grafana/*.template.json`** — Dashboard templates that reference types from `types.json`. These define the layout and which metrics each dashboard shows.

3. **`make_dashboards.py`** — The generation engine. Reads types.json + templates, resolves inheritance, applies version filtering (`"dashversion"` field controls which ScyllaDB versions see a panel), and outputs complete Grafana JSON.

4. **`generate-dashboards.sh`** → calls `make_dashboards.py` → outputs to **`grafana/build/ver_<version>/`**

When modifying dashboards: edit `types.json` for component definitions or `*.template.json` for layout, then regenerate.

### Version Matrix System

`versions.sh` defines which ScyllaDB versions are supported by each monitoring stack release. Key associative arrays:
- `SUPPORTED_VERSIONS[stack_ver]` — comma-separated ScyllaDB versions
- `DEFAULT_VERSION[stack_ver]` — default ScyllaDB version
- `MANAGER_DEFAULT_VERSION[stack_ver]` — default Manager version
- Container image versions: `PROMETHEUS_VERSION`, `GRAFANA_VERSION`, `LOKI_VERSION`, etc.

### Container Orchestration

`start-all.sh` (~930 lines) is the master orchestrator. It parses CLI args, resolves paths, sets up Docker networking, and calls component-specific scripts:
- `start-grafana.sh` — loads dashboards, configures datasources
- `start-loki.sh` — log aggregation
- `start-alertmanager.sh` — alert routing
- `prometheus-config.sh` — generates Prometheus config from templates

`make-compose.sh` generates `docker-compose.yml` from `docker-compose.template.yml`.

Multiple independent stacks can run simultaneously via `--stack <id>` (uses different ports per stack).

### Configuration Templates

Template files with variable substitution (not Jinja — shell-based sed/envsubst):
- `prometheus/prometheus.yml.template` — Prometheus scrape config
- `docker-compose.template.yml` — base compose file
- `loki/conf/loki-config.template.yaml` — Loki config
- `loki/promtail/promtail_config.template.yml` — log shipping

### Alert Rules

Prometheus alert rules in `prometheus/prom_rules/`:
- `prometheus.rules.yml` — core alerts
- `prometheus.latency.rules.yml` — latency alerts
- `prometheus.table.yml` — table-level metrics

Loki alert rules in `loki/rules/scylla/loki-rule.yaml`.

## File Layout Quick Reference

| Path | Purpose |
|------|---------|
| `grafana/types.json` | Dashboard component type definitions (edit this for panel changes) |
| `grafana/*.template.json` | Dashboard layout templates |
| `grafana/build/` | Generated dashboards (don't edit directly) |
| `prometheus/prom_rules/` | Prometheus alerting rules |
| `versions.sh` | Version matrix and container image versions |
| `dashboards.sh` | List of dashboards to generate (default set) |
| `make_dashboards.py` | Dashboard generation engine |
| `genconfig.py` | Prometheus target file generator |
| `docs/` | Sphinx documentation (RST format) |
| `packer/` | AWS/GCP cloud image building |

## CI/CD

GitHub Actions workflows in `.github/workflows/`:
- `docs-pr.yaml` — validates docs on PRs (runs `make -C docs test`)
- `docs-pages.yaml` — publishes docs to GitHub Pages on merge to master
- `build-cloud-images.yaml` — builds AWS AMI and GCP images on release tags
