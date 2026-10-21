#!/usr/bin/env python3
# Checks scylla_monitoring_config.py: parse, normalize, render, validate and
# status. The rendered example is compared with the golden files in
# tests/data/scylla_monitoring_config/; UPDATE_GOLDEN=1 rewrites them.
# Run: python3 tests/test_scylla_monitoring_config.py
import contextlib
import io
import json
import os
import re
import subprocess
import sys
import tempfile
from types import SimpleNamespace

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.path.insert(0, ROOT)

import yaml

import scylla_monitoring_config as smc

GOLDEN = os.path.join(ROOT, "tests", "data", "scylla_monitoring_config")
EXAMPLE = os.path.join(ROOT, "scylla-monitoring.example.yaml")
DIRS = smc.Dirs("/srv/monitoring")


def example():
    return smc.load(EXAMPLE)


def rejected(fn, *args):
    try:
        fn(*args)
    except smc.ConfigError as e:
        return e.args[0]
    raise AssertionError("not rejected")


def write_config(directory, cfg):
    path = os.path.join(directory, "config.yaml")
    with open(path, "w") as f:
        yaml.safe_dump(cfg, f)
    return path


def with_extra(*flags):
    cfg = example()
    cfg["stack"]["extra_flags"] = list(flags)
    return smc.normalize(cfg, DIRS)


def values(argv, opt):
    return [argv[i + 1] for i, w in enumerate(argv[:-1]) if w == opt]


def tree(directory):
    files = {}
    for base, _, names in os.walk(directory):
        for name in names:
            path = os.path.join(base, name)
            with open(path) as f:
                files[os.path.relpath(path, directory)] = f.read()
    return files


def test_golden():
    argv, env = smc.normalize(example(), DIRS)
    with tempfile.TemporaryDirectory() as tmp:
        smc.render(example(), tmp)
        rendered = tree(tmp)
        # git keeps no 0600, so the mode is checked here and not in the golden files
        assert os.stat(os.path.join(tmp, "certs/server.key")).st_mode & 0o777 == 0o600
    args_text = "\n".join(argv) + "\n"
    env_text = "\n".join(sorted(env)) + "\n"
    if os.environ.get("UPDATE_GOLDEN"):
        subprocess.run(["rm", "-rf", GOLDEN], check=True)
        for name, text in rendered.items():
            smc.write_file(os.path.join(GOLDEN, "staging", name), text)
        smc.write_file(os.path.join(GOLDEN, "start-all.args"), args_text)
        smc.write_file(os.path.join(GOLDEN, "environment"), env_text)
    assert open(os.path.join(GOLDEN, "start-all.args")).read() == args_text
    assert open(os.path.join(GOLDEN, "environment")).read() == env_text
    assert rendered == tree(os.path.join(GOLDEN, "staging"))


def test_option_table_matches_start_all():
    text = open("start-all.sh").read()
    long_options = set(re.findall(r"^\s*(--[a-z0-9-]+)\)", text, re.M)) | {"--compose"}
    assert long_options == {o for o in smc.OPTIONS if o.startswith("--")}, \
        long_options ^ {o for o in smc.OPTIONS if o.startswith("--")}
    spec = re.search(r"getopts '(:?[^']+)' option", text).group(1).lstrip(":")
    short = {"-" + m.group(1): bool(m.group(2)) for m in re.finditer(r"([A-Za-z])(:?)", spec)}
    assert short == {o: v[0] for o, v in smc.OPTIONS.items() if not o.startswith("--")}


def test_extra_flags_precedence():
    argv, _ = with_extra("-b --storage.tsdb.retention.time=60d", "-c GF_SERVER_ROOT_URL=https://other",
                         "-v 2025.4", "--no-loki")
    assert values(argv, "-b") == ["--storage.tsdb.retention.time=60d", "--web.external-url=https://example.com/prometheus",
                                  "--web.route-prefix=/"]
    assert "GF_SERVER_ROOT_URL=https://other" in values(argv, "-c")
    assert "GF_USERS_DEFAULT_THEME=light" in values(argv, "-c")
    assert values(argv, "-v") == ["2025.4"]
    assert values(argv, "--log-collector") == ["none"]


def test_docker_settings_once_per_container():
    argv, _ = with_extra("-D '--net=host --memory 2g'", "-D --network=monitor-net",
                         "--limit grafana,--memory=1G", "--limit grafana,--cpus=2", "--limit grafana,-m=3G",
                         "--limit prometheus,--memory=4G",
                         "--volume grafana,/a:/etc/x", "--volume grafana,/b:/etc/x:ro",
                         "--param prometheus,--query.timeout=1m", "--param prometheus,--query.timeout=2m")
    assert values(argv, "-D") == ["--restart=unless-stopped", "--network=monitor-net", "--memory 2g"]
    assert values(argv, "--limit") == ["grafana,-m=3G", "grafana,--cpus=2", "prometheus,--memory=4G"]
    assert values(argv, "--volume") == ["grafana,/b:/etc/x:ro"]
    assert values(argv, "--param") == ["prometheus,--query.timeout=2m"]


def test_extra_flags_rejected():
    assert "unknown option --nope" in rejected(with_extra, "--nope")
    assert "set by the watcher" in rejected(with_extra, "-s other.yml")
    assert "needs a value" in rejected(with_extra, "-v")


def test_extra_flags_getopts_forms():
    argv, _ = with_extra("-lv2025.4")
    assert "-l" in argv and values(argv, "-v") == ["2025.4"]


def test_secrets():
    cfg = example()
    cfg["stack"]["extra_flags"] = ["-a from-extra"]
    argv, env = smc.normalize(cfg, DIRS)
    assert "from-extra" not in argv and "-a" not in argv
    assert env == {"GRAFANA_ADMIN_PASSWORD": "from-extra", "SCYLLA_USER": "monitor", "SCYLLA_PSSWD": "change-me"}
    with tempfile.TemporaryDirectory() as tmp:
        bad = example()
        bad["grafana"]["admin_password"] = 987654321
        assert "987654321" not in rejected(smc.load, write_config(tmp, bad))
        path = os.path.join(tmp, "broken.yaml")
        with open(path, "w") as f:
            f.write("version: 1\ngrafana:\n  admin_password: s3cret: [\n")
        message = rejected(smc.load, path)
        assert "s3cret" not in message and message.startswith("line 3")


def test_strict():
    with tempfile.TemporaryDirectory() as tmp:
        cfg = example()
        cfg["stack"]["unknown"] = 1
        cfg["targets"]["scylla"][0]["lables"] = {}
        cfg["grafana"]["env"]["GF_FREE_KEY"] = "1"
        path = write_config(tmp, cfg)
        smc.load(path)
        message = rejected(smc.load, path, True)
        assert "'unknown' was unexpected" in message and "'lables' was unexpected" in message
        assert "GF_FREE_KEY" not in message


def test_rules():
    cfg = example()
    cfg["stack"]["thanos_sidecar"] = True
    del cfg["storage"]["prometheus_dir"]
    assert "needs storage.prometheus_dir" in rejected(smc.normalize, cfg, DIRS)
    del cfg["targets"]["node_exporter"]
    with tempfile.TemporaryDirectory() as tmp:
        cfg["storage"]["prometheus_dir"] = "/p"
        smc.render(cfg, tmp)
        scylla = open(os.path.join(tmp, "targets/scylla_servers.yml")).read()
        assert open(os.path.join(tmp, "targets/node_exporter_servers.yml")).read() == scylla
        del cfg["targets"]["manager"]
        smc.render(cfg, tmp)
        assert yaml.safe_load(open(os.path.join(tmp, "targets/scylla_manager_servers.yml"))) == []


def test_validate():
    calls = []

    def fake(cmd, **kwargs):
        calls.append(cmd)
        failed = "promtool" in cmd
        return SimpleNamespace(returncode=1 if failed else 0,
                               stdout="Checking /c/prometheus.rules.yml\n  FAILED:\nbad expression\n" if failed else "")

    with tempfile.TemporaryDirectory() as tmp:
        smc.render(example(), tmp)
        assert rejected(smc.validate, tmp, ("v1", "v2"), fake) == "alert_rules: FAILED: bad expression"
        assert "prom/prometheus:v1" in calls[0]
        calls.clear()
        os.remove(os.path.join(tmp, "rules/prometheus.rules.yml"))
        os.rmdir(os.path.join(tmp, "rules"))
        smc.validate(tmp, ("v1", "v2"), fake)
        assert len(calls) == 1 and "prom/alertmanager:v2" in calls[0]


def test_check_status():
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["cp", "versions.sh", tmp], check=True)
        ok = lambda cmd, **kwargs: SimpleNamespace(returncode=0, stdout="")
        args = SimpleNamespace(config_file=EXAMPLE, monitoring_dir=tmp, staging_dir=None, strict=False)
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            assert smc.check(args, ok) == 0
        assert out.getvalue().startswith("./start-all.sh -v 2025.3 ")
        status_path = os.path.join(tmp, "config-state", "status.json")
        status = json.load(open(status_path))
        assert status["state"] == "validated" and status["generation"] == example()["generation"]
        assert os.stat(status_path).st_mode & 0o777 == 0o600
        bad = example()
        bad["stack"]["log_collector"] = "loki"
        args.config_file = write_config(tmp, bad)
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            assert smc.check(args, ok) == 1
        status = json.load(open(status_path))
        assert status["state"] == "rejected" and status["generation"] == bad["generation"]
        assert status["error"].startswith("stack.log_collector: must be one of")


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("ok")
