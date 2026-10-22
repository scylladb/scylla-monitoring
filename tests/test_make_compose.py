#!/usr/bin/env python3
# Checks make_compose.py: the compose definition, .env values, helper
# commands and files for several start-all.sh option sets, compared with the
# golden files in tests/data/make_compose/golden/; UPDATE_GOLDEN=1 rewrites
# them. Image versions are written as <NAME> so a version bump in versions.sh
# needs no new golden files. When docker is installed, docker compose config
# checks each golden compose file.
# Run: python3 tests/test_make_compose.py
import inspect
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.path.insert(0, ROOT)

import yaml

import make_compose as mc
import scylla_monitoring_config as smc

DATA = os.path.join("tests", "data", "make_compose")
GOLDEN = os.path.join(DATA, "golden")
TARGETS = ["--target-directory", os.path.join(DATA, "targets")]
ENVIRON = {"PATH": os.environ["PATH"], "HOME": "/nonexistent", "HOSTNAME": "monitor1",
           "GRAFANA_RENDERER_TOKEN": "test-token", "CONF_DIR": os.path.join(DATA, "datadog_conf")}

CASES = {
    "default": ["-v", "2025.3"] + TARGETS,
    "files": ["-v", "2025.3", "-s", os.path.join(DATA, "scylla_servers.yml"), "-d", "/var/lib/prometheus",
              "-N", os.path.join(DATA, "targets", "scylla_manager_servers.yml")],
    "host-network": ["-v", "2025.3", "-l"] + TARGETS,
    "stack": ["-v", "2025.3", "--stack", "2"] + TARGETS,
    "victoria-metrics": ["-v", "2025.3", "--victoria-metrics", "-d", "/var/lib/vm"] + TARGETS,
    "thanos": ["-v", "2025.3", "-d", "/var/lib/prometheus", "--thanos-sc", "--thanos", "-A", "127.0.0.1"] + TARGETS,
    "datadog": ["-v", "2025.3", "--datadog-api-keys", "dd-key", "--datadog-hostname", "host1"] + TARGETS,
    "docker-settings": ["-v", "2025.3", "-D", "--memory=8g --restart=always", "--auto-restart",
                        "--limit", "prometheus,--memory#4g", "--limit", "grafana,--cpus=2",
                        "--volume", "grafana,tests:/etc/extra", "--param", "prometheus,--query.timeout=2m",
                        "--param", "sidecar,--log.level=debug", "-d", "/var/lib/prometheus", "--thanos-sc"] + TARGETS,
    "grafana": ["-v", "2025.3,2025.4", "-P", os.path.join(DATA, "ldap.toml"), "-a", "pa$s\"word", "-Q", "Viewer",
                "-c", "GF_SERVER_ROOT_URL=/grafana", "-c", "GF_USERS_DEFAULT_THEME=dark", "--allow-embedding",
                "-G", "/var/lib/grafana", "-j", "extra.json", "--alternator"] + TARGETS,
    "traefik": ["-v", "2025.3", "-A", "127.0.0.1", "--traefik", "--no-renderer", "--log-collector", "promtail"]
               + TARGETS,
}


def versions():
    v = mc.shell_vars(ROOT, ENVIRON, os.devnull)
    return {name: value for name, value in v.items() if name.endswith("_VERSION") and isinstance(value, str) and value}


def build(argv, **environ):
    return mc.build(argv, environ=dict(ENVIRON, **dict({"PRIVATE_IP": "10.0.0.5", "CERT_DIR": "/etc/certs"}, **environ)),
                    cwd=ROOT, env_file=os.devnull, ids=(1000, 1000))


def describe(stack):
    """The Stack as golden text, with image versions as <NAME>."""
    text = yaml.safe_dump({"compose": stack.compose, "env": stack.env, "commands": stack.commands,
                           "files": sorted(stack.files),
                           "dirs": stack.dirs, "warnings": stack.warnings}, sort_keys=False, width=200)
    for name, value in sorted(versions().items(), key=lambda kv: -len(kv[1])):
        text = text.replace(":" + value + "\n", ":<%s>\n" % name)
    return text


def rejected(argv, **environ):
    try:
        build(argv, **environ)
    except smc.ConfigError as e:
        return e.args[0]
    raise AssertionError("not rejected: %s" % argv)


def test_golden():
    if os.environ.get("UPDATE_GOLDEN"):
        shutil.rmtree(GOLDEN, ignore_errors=True)
        os.makedirs(GOLDEN)
    for name, argv in CASES.items():
        text = describe(build(argv))
        path = os.path.join(GOLDEN, name + ".yml")
        if os.environ.get("UPDATE_GOLDEN"):
            open(path, "w").write(text)
        assert open(path).read() == text, "%s differs from %s" % (name, path)


def test_docker_compose_accepts_golden():
    if not shutil.which("docker") or subprocess.run(["docker", "compose", "version"], capture_output=True).returncode:
        return
    for name, argv in CASES.items():
        stack = build(argv)
        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, "docker-compose.yml"), "w") as f:
                yaml.safe_dump(stack.compose, f)
            with open(os.path.join(tmp, ".env"), "w") as f:
                f.write("".join("%s=%s\n" % (k, mc.env_value(v)) for k, v in stack.env.items()))
            out = subprocess.run(["docker", "compose", "config", "-q"], cwd=tmp, capture_output=True, text=True)
            assert out.returncode == 0, (name, out.stderr)


def test_every_option_handled():
    source = inspect.getsource(mc.options)
    # CANONICAL maps --no-loki and --no-log-collector to --log-collector none
    missing = [o for o in smc.OPTIONS if '"%s"' % o not in source and o not in smc.CANONICAL]
    assert not missing, missing


def test_secrets_stay_out_of_compose():
    stack = build(CASES["grafana"] + ["--datadog-api-keys", "dd-key"])
    text = yaml.safe_dump(stack.compose)
    assert "pa$s" not in text and "pa$$s" not in text and "dd-key" not in text and "test-token" not in text
    assert stack.env == {"GRAFANA_ADMIN_PASSWORD": 'pa$s"word', "DD_API_KEY": "dd-key",
                         "GRAFANA_RENDERER_TOKEN": "test-token"}


def test_env_file_round_trip():
    value = 'a"b\\c$d#e \'f ${X}'
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, ".env")
        open(path, "w").write("A=%s\n" % mc.env_value(value))
        assert mc.read_env_file(path) == {"A": value}
    assert "newline" in rejected(["-v", "2025.3", "-a", "a\nb"] + TARGETS)


def test_renderer_token_kept():
    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy("versions.sh", tmp)
        open(os.path.join(tmp, ".env"), "w").write('GRAFANA_RENDERER_TOKEN="kept"\n')
        environ = {k: v for k, v in ENVIRON.items() if k != "GRAFANA_RENDERER_TOKEN"}
        stack = mc.build(["-v", "2025.3", "--no-log-collector", "--target-directory", os.path.join(ROOT, DATA, "targets")],
                         environ=environ, cwd=tmp, env_file=os.devnull, ids=(1000, 1000))
        assert stack.env["GRAFANA_RENDERER_TOKEN"] == "kept"
        os.remove(os.path.join(tmp, ".env"))
        stack = mc.build(["-v", "2025.3", "--no-log-collector", "--target-directory", os.path.join(ROOT, DATA, "targets")],
                         environ=environ, cwd=tmp, env_file=os.devnull, ids=(1000, 1000))
        assert len(stack.env["GRAFANA_RENDERER_TOKEN"]) == 32


def test_env_sh_is_read():
    with tempfile.NamedTemporaryFile("w", suffix=".sh") as f:
        f.write('DOCKER_PARAM="--memory=1g"\nDEFAULT_THEME=dark\nDOCKER_LIMITS["grafana"]="--cpus=3"\n'
                'LOG_COLLECTOR=none\n')
        f.flush()
        stack = mc.build(["-v", "2025.3"] + TARGETS, environ=ENVIRON, cwd=ROOT, env_file=f.name, ids=(1000, 1000))
        grafana = stack.compose["services"]["agraf"]
        assert grafana["mem_limit"] == "1g" and grafana["cpus"] == "3"
        assert "GF_USERS_DEFAULT_THEME=dark" in grafana["environment"]
        assert "loki" not in stack.compose["services"]
        # the first -D replaces env.sh's DOCKER_PARAM, as in start-all.sh
        stack = mc.build(["-v", "2025.3", "-D", "--cpus=1"] + TARGETS, environ=ENVIRON, cwd=ROOT, env_file=f.name,
                         ids=(1000, 1000))
        assert "mem_limit" not in stack.compose["services"]["aprom"]


def test_generated_files():
    stack = build(["-v", "2025.3", "-m", "9094", "--loki-port", "3101", "--alloy-syslog-port", "1515"] + TARGETS)
    assert "alertmanager_url: http://aalert-9094:9093\n" in stack.files["loki/conf/loki-config.yaml"][0]
    alloy = stack.files["loki/alloy/build/config.alloy"][0]
    assert '"http://loki-3101:3100/loki/api/v1/push"' in alloy and '"0.0.0.0:1515"' in alloy
    stack = build(["-v", "2025.3", "-l", "--log-collector", "promtail"] + TARGETS)
    assert "127.0.0.1:3100" in stack.files["loki/promtail/build/config.yml"][0]
    stack = build(CASES["datadog"])
    conf = os.path.join(DATA, "datadog_conf")
    assert "hostname: host1\n" in stack.files[os.path.join(conf, "datadog.yaml")][0]
    assert "aprom:9090" in stack.files[os.path.join(conf, "conf.d/prometheus.d/conf.yaml")][0]
    assert "url: http://thanos:10904\n" in build(CASES["thanos"]).files["grafana/provisioning/datasources/thanos.yaml"][0]
    servers = build(["-v", "2025.3", "--servers", "10.0.0.1,10.0.0.2", "-N",
                     os.path.join(DATA, "targets", "scylla_manager_servers.yml")]).files["prometheus/build/scylla_servers.yml"][0]
    assert servers.endswith("- targets:\n  - 10.0.0.1\n  - 10.0.0.2\n")


def test_docker_settings():
    assert mc.compose_settings("--net=host -m 1g -e A=1 --env B=2 --ulimit nofile=10:20 --log-opt max-size=1m -i "
                               "--privileged", "-D") == {
        "network": "host", "mem_limit": "1g", "environment": ["A=1", "B=2"],
        "ulimits": {"nofile": {"soft": 10, "hard": 20}}, "logging": {"options": {"max-size": "1m"}},
        "privileged": True}
    assert "--name has no docker compose equivalent" in rejected(["-v", "2025.3", "-D", "--name x"] + TARGETS)
    assert "--limit grafana: --mac-address" in rejected(["-v", "2025.3", "--limit", "grafana,--mac-address=x"] + TARGETS)


def test_dollar_is_escaped():
    stack = build(["-v", "2025.3", "-c", "GF_X=a$b"] + TARGETS)
    assert "GF_X=a$$b" in stack.compose["services"]["agraf"]["environment"]
    assert "GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}" in stack.compose["services"]["agraf"]["environment"]


def test_start_all_checks():
    assert "Port mapping is not supported" in rejected(["-v", "2025.3", "-l", "-g", "3001"] + TARGETS)
    assert "--servers cannot be used" in rejected(["-v", "2025.3", "--servers", "10.0.0.1"] + TARGETS)
    assert "unknown option --nope" in rejected(["-v", "2025.3", "--nope"])
    assert "Unknown --log-collector" in rejected(["-v", "2025.3", "--log-collector", "x"] + TARGETS)
    assert "names, or host" in rejected(["-v", "2025.3", "-D", "--net=bridge"] + TARGETS)
    assert "PRIVATE_IP is required" in rejected(["-v", "2025.3", "--traefik"] + TARGETS, PRIVATE_IP="")
    assert "needs -A 127.0.0.1" in rejected(["-v", "2025.3", "--traefik"] + TARGETS)
    assert "needs -A 127.0.0.1" in rejected(["-v", "2025.3", "--traefik", "-A", "10.0.0.5"] + TARGETS)
    assert "cannot be used with -l" in rejected(["-v", "2025.3", "--traefik", "-l"] + TARGETS)
    assert "only be set for every container" in rejected(["-v", "2025.3", "--limit", "grafana,--net=x"] + TARGETS)


def test_write():
    with tempfile.TemporaryDirectory() as tmp:
        stack = mc.Stack()
        stack.compose = {"services": {}}
        stack.env = {"GRAFANA_ADMIN_PASSWORD": "x"}
        stack.files = {"a/b.yml": ("b\n", 0o644)}
        stack.commands = [["./prometheus-config.sh"]]
        stack.up = True
        ran = []
        mc.write(stack, cwd=tmp, environ={}, run=lambda cmd, **kw: ran.append(cmd))
        assert ran == [["./prometheus-config.sh"], ["docker", "compose", "up", "-d", "--remove-orphans"]]
        assert open(os.path.join(tmp, "a/b.yml")).read() == "b\n"
        assert os.stat(os.path.join(tmp, ".env")).st_mode & 0o777 == 0o600
        assert yaml.safe_load(open(os.path.join(tmp, "docker-compose.yml"))) == {"services": {}}



def test_config_hash():
    """A change in the config a service reads on start changes its label, so
    docker compose up recreates it; the other services keep theirs."""
    with tempfile.TemporaryDirectory() as tmp:
        def labels(prometheus_yml, generated):
            os.makedirs(os.path.join(tmp, "prometheus/build"), exist_ok=True)
            with open(os.path.join(tmp, "prometheus/build/prometheus.yml"), "w") as f:
                f.write(prometheus_yml)
            stack = mc.Stack()
            stack.compose = {"services": {
                "aprom": {"volumes": ["./prometheus/build/:/etc/prometheus/config/:z", "/:/host"]},
                "agraf": {"volumes": ["./grafana/build:/var/lib/grafana/dashboards:z"], "labels": ["a=b"]},
                "datadog": {"volumes": ["./conf/conf.d/:/conf.d"]},
            }}
            stack.files = {"conf/conf.d/p.d/conf.yaml": (generated, 0o644)}
            stack.config = [os.path.join(tmp, "prometheus/build")]
            mc.write(stack, cwd=tmp, environ={}, run=lambda cmd, **kw: None)
            services = yaml.safe_load(open(os.path.join(tmp, "docker-compose.yml")))["services"]
            return {name: svc["labels"] for name, svc in services.items()}
        first = labels("a", "x")
        assert first["agraf"][0] == "a=b" and len(first["agraf"]) == 2
        assert labels("a", "x") == first
        second = labels("b", "x")
        assert second["aprom"] != first["aprom"] and second["agraf"] == first["agraf"]
        assert second["datadog"] == first["datadog"]
        assert labels("b", "y")["datadog"] != second["datadog"]



def test_write_stack_and_traefik():
    """A secondary stack has its own files; with traefik, the stack comes up
    first, then start-traefik.sh --check, then traefik."""
    with tempfile.TemporaryDirectory() as tmp:
        stack = mc.Stack()
        stack.compose = {"name": "scylla-monitoring-stack2", "services": {"aprom": {}, "traefik": {}}}
        stack.compose_file, stack.env_file = "docker-compose.stack2.yml", ".env.stack2"
        stack.up = True
        ran = []
        mc.write(stack, cwd=tmp, environ={}, run=lambda cmd, **kw: ran.append(cmd))
        compose = ["docker", "compose", "-f", "docker-compose.stack2.yml", "--env-file", ".env.stack2"]
        assert ran == [compose + ["up", "-d", "--remove-orphans", "aprom"], ["./start-traefik.sh", "--check"],
                       compose + ["up", "-d", "traefik"]], ran
        assert sorted(os.listdir(tmp)) == [".env.stack2", "docker-compose.stack2.yml"]
    assert build(CASES["stack"]).compose_file == "docker-compose.stack2.yml"


def test_env_sh_grafana_port():
    with tempfile.TemporaryDirectory() as tmp:
        env_sh = os.path.join(tmp, "env.sh")
        with open(env_sh, "w") as f:
            f.write('GRAFANA_PORT="-g 3001"\n')
        stack = mc.build(["-v", "2025.3"] + TARGETS, environ=ENVIRON, cwd=ROOT, env_file=env_sh, ids=(1000, 1000))
        assert stack.compose["services"]["agraf-3001"]["ports"] == ["3001:3000"]


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("ok")
