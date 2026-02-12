.PHONY: build test integration-test lint vet clean generate-assets verify-assets

BINARY = scylla-monitor-ctl
VERSION ?= dev

# Required source files for generate-assets (relative to parent repo)
ASSET_SOURCES = \
	../grafana/types.json \
	../grafana/datasource.yml \
	../grafana/datasource.loki.yml \
	../grafana/datasource.scylla.yml \
	../grafana/datasource.psswd.scylla.yml \
	../grafana/load.yaml \
	../prometheus/prometheus.yml.template \
	../prometheus/prometheus.consul.yml.template \
	../prometheus/rule_config.yml \
	../loki/conf/loki-config.template.yaml \
	../loki/promtail/promtail_config.template.yml \
	../docker-compose.template.yml

# Required destination files that must exist after generate-assets (for go:embed)
ASSET_TARGETS = \
	assets/grafana/types.json \
	assets/grafana/datasource.yml \
	assets/grafana/datasource.loki.yml \
	assets/grafana/datasource.scylla.yml \
	assets/grafana/datasource.psswd.scylla.yml \
	assets/grafana/load.yaml \
	assets/prometheus/prometheus.yml.template \
	assets/prometheus/prometheus.consul.yml.template \
	assets/alertmanager/rule_config.yml \
	assets/loki/conf/loki-config.template.yaml \
	assets/loki/promtail/promtail_config.template.yml \
	assets/docker-compose.template.yml \
	assets/versions.yaml

build:
	go build -ldflags "-X github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/cmd.MonitorVersion=$(VERSION)" -o $(BINARY) .

test:
	go test -v -count=1 ./...

integration-test:
	go test -v -count=1 -tags=integration -timeout=300s ./pkg/docker/ ./pkg/stack/

lint: vet
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run ./...; \
	else \
		echo "golangci-lint not installed, skipping (run: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest)"; \
	fi

vet:
	go vet ./...

clean:
	rm -f $(BINARY)
	rm -rf grafana/build/

generate-assets:
	@echo "Validating source files..."
	@missing=""; \
	for f in $(ASSET_SOURCES); do \
		if [ ! -f "$$f" ]; then \
			missing="$$missing $$f"; \
		fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo "ERROR: Missing source files:$$missing" >&2; \
		exit 1; \
	fi
	@# Check that at least one template exists
	@if ! ls ../grafana/*.template.json >/dev/null 2>&1; then \
		echo "ERROR: No template.json files found in ../grafana/" >&2; \
		exit 1; \
	fi
	@if ! ls ../prometheus/prom_rules/*.yml >/dev/null 2>&1; then \
		echo "ERROR: No .yml files found in ../prometheus/prom_rules/" >&2; \
		exit 1; \
	fi
	@echo "Copying assets from parent repository..."
	@mkdir -p assets/grafana assets/prometheus/prom_rules assets/alertmanager assets/loki/conf assets/loki/promtail
	cp ../grafana/types.json assets/grafana/
	cp ../grafana/*.template.json assets/grafana/
	cp ../grafana/datasource.yml ../grafana/datasource.loki.yml ../grafana/datasource.scylla.yml ../grafana/datasource.psswd.scylla.yml assets/grafana/
	cp ../grafana/load.yaml assets/grafana/
	cp ../prometheus/prometheus.yml.template ../prometheus/prometheus.consul.yml.template assets/prometheus/
	cp ../prometheus/prom_rules/*.yml assets/prometheus/prom_rules/
	cp ../prometheus/rule_config.yml assets/alertmanager/
	cp ../loki/conf/loki-config.template.yaml assets/loki/conf/
	cp ../loki/promtail/promtail_config.template.yml assets/loki/promtail/
	cp ../docker-compose.template.yml assets/
	@echo "Verifying copied assets..."
	@$(MAKE) --no-print-directory verify-assets
	@echo "Assets copied and verified successfully."

verify-assets:
	@failed=0; \
	for f in $(ASSET_TARGETS); do \
		if [ ! -f "$$f" ]; then \
			echo "ERROR: Missing required asset: $$f" >&2; \
			failed=1; \
		fi; \
	done; \
	if ! ls assets/grafana/*.template.json >/dev/null 2>&1; then \
		echo "ERROR: No dashboard templates in assets/grafana/" >&2; \
		failed=1; \
	fi; \
	if ! ls assets/prometheus/prom_rules/*.yml >/dev/null 2>&1; then \
		echo "ERROR: No alert rules in assets/prometheus/prom_rules/" >&2; \
		failed=1; \
	fi; \
	if [ "$$failed" -eq 1 ]; then \
		exit 1; \
	fi; \
	echo "All required assets present."
