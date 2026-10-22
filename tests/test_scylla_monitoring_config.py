#!/usr/bin/env python3
# Checks scylla_monitoring_config.py: parse, normalize, render, validate and
# status. The rendered example is compared with the golden files in
# tests/data/scylla_monitoring_config/; UPDATE_GOLDEN=1 rewrites them.
# Run: python3 tests/test_scylla_monitoring_config.py
import contextlib
import copy
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
        args = SimpleNamespace(config_file=[EXAMPLE], monitoring_dir=tmp, staging_dir=None, strict=False)
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            assert smc.check(args, ok) == 0
        assert out.getvalue().startswith("./start-all.sh -v 2025.3 ")
        # check leaves the running watcher's status and staging alone
        assert not os.path.exists(os.path.join(tmp, "config-state"))
        assert not os.path.exists(os.path.join(tmp, "config-build"))
        bad = example()
        bad["stack"]["log_collector"] = "loki"
        args.config_file = [write_config(tmp, bad)]
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            assert smc.check(args, ok) == 1
        assert out.getvalue().startswith("rejected: stack.log_collector: must be one of")
        # secrets are masked in the printed command line
        cfg = example()
        cfg["grafana"]["env"]["GF_AUTH_CLIENT_SECRET"] = "s3cret"
        cfg["stack"]["extra_flags"] = ["--grafana-render-token tok3n"]
        args.config_file = [write_config(tmp, cfg)]
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            assert smc.check(args, ok) == 0
        assert "s3cret" not in out.getvalue() and "tok3n" not in out.getvalue()
        assert "GF_AUTH_CLIENT_SECRET=***" in out.getvalue()


def test_strict_tls():
    """--strict keeps the tls if/then: enabled TLS still needs every field."""
    for field in ("ca_crt", "server_crt", "server_key", "listen_ip"):
        cfg = example()
        cfg["tls"].pop(field)
        with tempfile.TemporaryDirectory() as tmp:
            try:
                smc.load(write_config(tmp, cfg), strict=True)
            except smc.ConfigError as e:
                assert field in e.args[0], e.args[0]
                continue
        raise AssertionError(field)


def test_unknown_option_value_hidden():
    try:
        smc.parse_flags(["--grafana-render-token=s3cret"])
        raise AssertionError("accepted")
    except smc.ConfigError as e:
        assert "s3cret" not in e.args[0] and "--grafana-render-token" in e.args[0]
    assert smc.masked(["-D", "--env=SCYLLA_PASSWORD=s3cret -e FOO=1"]) == ["-D", "--env=SCYLLA_PASSWORD=*** -e FOO=1"]


def test_stack_components():
    """A secondary stack: the ports versions.sh assigns it, and no Loki."""
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        argv = ["--stack", "2", "-p", "9999", "--log-collector", "alloy"]
        assert stack.components(argv) == [("prometheus", "9052", "/-/ready"), ("grafana", "3002", "/api/health"),
                                          ("alertmanager", "9042", "/-/ready")]
        assert ("loki", "3100", "/ready") in stack.components(["--log-collector", "alloy"])


def test_bad_values_rejected():
    for flags in (['-c "x'], ['-b ""'], ['--param "grafana, "']):
        cfg = example()
        cfg["stack"]["extra_flags"] = flags
        try:
            smc.normalize(cfg, smc.Dirs("/m"))
        except smc.ConfigError:
            continue
        raise AssertionError(flags)
    cfg = example()
    cfg["stack"]["docker_args"] = ['"x']
    try:
        smc.normalize(cfg, smc.Dirs("/m"))
        raise AssertionError("docker_args")
    except smc.ConfigError:
        pass


def test_plan():
    old = example()

    def actions(change):
        new = copy.deepcopy(old)
        change(new)
        return smc.plan(old, new)

    assert smc.plan(None, old) == smc.FIRST_APPLY
    assert actions(lambda c: c["targets"]["scylla"][0]["targets"].append("10.0.0.9")) == set()
    assert actions(lambda c: c["targets"]["vector_search"][0]["targets"].append("10.0.0.9")) == set()
    assert actions(lambda c: c["targets"].pop("vector_search")) == {"restart_stack"}
    assert actions(lambda c: c["alert_rules"]["groups"].append({"name": "x", "rules": []})) == {"reload_prometheus"}
    assert actions(lambda c: c.pop("alert_rules")) == {"restart_stack"}
    assert actions(lambda c: c["alertmanager_config"].update(receivers=[])) == {"reload_alertmanager"}
    assert actions(lambda c: c.update(cluster="c2")) == {"render_prometheus_config", "reload_prometheus"}
    assert actions(lambda c: c["grafana"].update(admin_password="x")) == {"grafana_password"}
    assert actions(lambda c: c["grafana"]["datasource"].update(scylla_password="x")) == {"grafana_datasource"}
    assert actions(lambda c: c["grafana"].update(default_theme="dark")) == {"restart_stack"}
    assert actions(lambda c: c["storage"].update(retention_days=60)) == {"restart_stack"}
    assert actions(lambda c: c["stack"].update(scylla_version="2025.4")) == {"restart_stack"}
    assert actions(lambda c: c["tls"].update(server_key="k")) == {"install_certs", "reload_traefik"}
    assert actions(lambda c: c["tls"].update(listen_ip="10.0.0.11")) == {"start_traefik"}
    assert actions(lambda c: c["systemd"].clear()) == {"systemd_dropins"}
    # a restart covers the reloads, not the password or the certificates
    assert actions(lambda c: (c["storage"].update(retention_days=60), c.update(cluster="c2"),
                              c["grafana"].update(admin_password="x"), c["tls"].update(server_key="k"))) == \
        {"restart_stack", "grafana_password", "install_certs"}


class FakeHost:
    """Records commands, answers the versions and Grafana name lookups, and
    fails the commands named in fail."""

    def __init__(self, fail=()):
        self.commands = []
        self.fail = set(fail)

    def run(self, cmd, **kwargs):
        if cmd[0] == "bash" and "STACK_PROMETHEUS" in cmd[2]:
            return SimpleNamespace(returncode=0, stdout="9052 3002 9042\n")
        if cmd[0] == "bash" and "versions.sh" in cmd[2]:
            return SimpleNamespace(returncode=0, stdout="v1 v2\n")
        if cmd[0] == "bash":
            return SimpleNamespace(returncode=0, stdout="agraf\n")
        if cmd[0] == "docker" and cmd[1] == "run":
            return SimpleNamespace(returncode=0, stdout="")
        self.commands.append((cmd, kwargs.get("input")))
        return SimpleNamespace(returncode=1 if os.path.basename(cmd[0]) in self.fail else 0, stdout="")


def make_stack(tmp, host):
    for f in ("versions.sh", "network-lib.sh"):
        subprocess.run(["cp", f, tmp], check=True)
    os.makedirs(os.path.join(tmp, "grafana"))
    for f in ("datasource.scylla.yml", "datasource.psswd.scylla.yml"):
        subprocess.run(["cp", os.path.join("grafana", f), os.path.join(tmp, "grafana")], check=True)
    args = SimpleNamespace(monitoring_dir=tmp, staging_dir=None, strict=False, auto_revert=False, force=False,
                           cert_dir="/certs", root_helper="/helper", health_timeout=0, config_file=[], state_dir=None)
    dirs = smc.make_dirs(args)
    http = lambda method, url: 200
    return args, smc.Stack(dirs, args, host.run, http, sleep=lambda s: None)


def apply(args, stack, host, cfg):
    args.config_file = [write_config(args.monitoring_dir, cfg)]
    out = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
        return smc.apply_once(args, stack, host.run)


def names(host):
    """Each command: its program, and the root helper's subcommand."""
    out = []
    for cmd, _ in host.commands:
        if cmd[0] == "sudo":
            out.append("helper " + cmd[3])
        else:
            out.append(" ".join([os.path.basename(cmd[0])] + [w for w in cmd[1:2] if w.startswith("-") or cmd[0] == "docker"]))
    return out


def test_apply():
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        cfg = example()
        assert apply(args, stack, host, cfg) == 0
        assert names(host) == ["helper dropin", "helper certs", "kill-all.sh", "start-all.sh -v",
                               "start-traefik.sh", "docker exec"]
        assert host.commands[0][0][-2:] == ["node-exporter.service",
                                            tmp + "/config-build/staging/systemd/node-exporter.service.conf"]
        assert host.commands[-1][1] == cfg["grafana"]["admin_password"]
        assert os.path.exists(os.path.join(tmp, "config-build/live/targets/scylla_servers.yml"))
        # the same file again does nothing
        host.commands.clear()
        assert apply(args, stack, host, cfg) == 0 and host.commands == []
        # a certificate rotation installs them and reloads traefik
        cfg["generation"] = "g2"
        cfg["tls"]["server_key"] = "-----BEGIN PRIVATE KEY-----\nnew\n-----END PRIVATE KEY-----\n"
        assert apply(args, stack, host, cfg) == 0
        assert names(host) == ["helper certs", "start-traefik.sh --reload"]
        # removing vector search restarts the stack and removes its target file
        host.commands.clear()
        cfg["generation"] = "g3"
        cfg["targets"].pop("vector_search")
        assert apply(args, stack, host, cfg) == 0
        assert not os.path.exists(os.path.join(tmp, "config-build/live/targets/vector_search_servers.yml"))
        assert names(host) == ["kill-all.sh", "start-all.sh -v", "start-traefik.sh"]


def test_apply_failure():
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        good = example()
        assert apply(args, stack, host, good) == 0
        bad = copy.deepcopy(good)
        bad["generation"] = "bad"
        bad["storage"]["retention_days"] = 60
        host.fail = {"start-all.sh"}
        assert apply(args, stack, host, bad) == 1
        status = json.load(open(os.path.join(tmp, "config-state/status.json")))
        assert status["state"] == "failed" and status["error"] == "start-all.sh failed"
        # the stack stays on the failed configuration, so a fix is planned from it
        host.fail = set()
        host.commands.clear()
        fixed = copy.deepcopy(good)
        fixed["generation"] = "fixed"
        assert apply(args, stack, host, fixed) == 0
        assert "start-all.sh" in [c.split()[0] for c in names(host)]
        # with --auto-revert the previous configuration comes back
        args.auto_revert = True
        host.fail = {"start-all.sh"}
        calls = []
        real_restart = stack.restart_stack

        def restart(argv, env, cfg, first=False):
            calls.append([v for v in smc.option_values(argv, "-b") if "retention" in v][0])
            if len(calls) == 1:
                real_restart(argv, env, cfg, first)
            host.fail = set()
        stack.restart_stack = restart
        assert apply(args, stack, host, bad) == 1
        status = json.load(open(os.path.join(tmp, "config-state/status.json")))
        assert status["state"] == "reverted" and status["applied_generation"] == "fixed"
        assert calls == ["--storage.tsdb.retention.time=60d", "--storage.tsdb.retention.time=30d"]


def test_apply_incomplete():
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        good = example()
        assert apply(args, stack, host, good) == 0
        # the drop-in fails before the restart the new version needs
        bad = copy.deepcopy(good)
        bad["generation"] = "g2"
        bad["stack"]["scylla_version"] = "2025.4"
        bad["systemd"]["missing.service"] = "[Service]\n"
        host.fail = {"sudo"}
        assert apply(args, stack, host, bad) == 1
        assert os.path.exists(os.path.join(tmp, "config-state/applied.incomplete"))
        # the fix runs every action, so the version change is not lost, and
        # removes the drop-in of the unit it dropped
        host.fail = set()
        host.commands.clear()
        fixed = copy.deepcopy(bad)
        fixed["generation"] = "g3"
        fixed["systemd"].pop("missing.service")
        assert apply(args, stack, host, fixed) == 0
        assert "start-all.sh -v" in names(host)
        assert [c[3:5] for c, _ in host.commands if c[0] == "sudo" and c[3] == "dropin"] == \
            [["dropin", "missing.service"], ["dropin", "node-exporter.service"]]
        assert not os.path.exists(os.path.join(tmp, "config-state/applied.incomplete"))


def test_force_removes_dropins():
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        cfg = example()
        assert apply(args, stack, host, cfg) == 0
        host.commands.clear()
        cfg["generation"] = "g2"
        cfg["systemd"].clear()
        args.force = True
        assert apply(args, stack, host, cfg) == 0
        assert ["dropin", "node-exporter.service", "--remove"] == host.commands[0][0][3:]



def test_apply_compose():
    import make_compose
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        stack.compose = True
        builds = []

        def build(argv, environ, cwd):
            builds.append((argv, environ))
            result = make_compose.Stack()
            result.compose = {"services": {}}
            result.env = {"GRAFANA_ADMIN_PASSWORD": environ["GRAFANA_ADMIN_PASSWORD"]}
            result.commands = [["./prometheus-config.sh", "-m", "aalert:9093"], ["./grafana-datasource.sh"]]
            return result
        stack.compose_build = build
        cfg = example()
        # the first apply removes what start-all.sh left, then compose brings the stack up
        assert apply(args, stack, host, cfg) == 0
        assert names(host) == ["helper dropin", "helper certs", "kill-all.sh", "prometheus-config.sh -m",
                               "grafana-datasource.sh", "docker compose", "docker exec"]
        argv, environ = builds[-1]
        assert "--traefik" in argv and environ["PRIVATE_IP"] == cfg["tls"]["listen_ip"]
        assert environ["CERT_DIR"] == "/certs" and environ["TRAEFIK_GENERATION"] == cfg["generation"]
        assert os.stat(os.path.join(tmp, ".env")).st_mode & 0o777 == 0o600
        assert os.path.exists(os.path.join(tmp, "docker-compose.yml"))
        # the cluster label: make_compose.py's prometheus-config.sh command, then a reload
        host.commands.clear()
        cfg["generation"] = "g2"
        cfg["cluster"] = "cluster2"
        assert apply(args, stack, host, cfg) == 0
        assert names(host) == ["prometheus-config.sh -m"]
        # a restart is compose up alone, which recreates only what changed
        host.commands.clear()
        cfg["generation"] = "g3"
        cfg["storage"]["retention_days"] = 60
        assert apply(args, stack, host, cfg) == 0
        assert names(host) == ["prometheus-config.sh -m", "grafana-datasource.sh", "docker compose"]
        # TLS off: compose up without traefik, which --remove-orphans removes
        host.commands.clear()
        cfg["generation"] = "g4"
        cfg["tls"]["enabled"] = False
        assert apply(args, stack, host, cfg) == 0
        assert names(host) == ["prometheus-config.sh -m", "grafana-datasource.sh", "docker compose"]
        assert "--traefik" not in builds[-1][0]


def quiet(fn, *args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
        return fn(*args), out.getvalue()


def test_several_config_files():
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        a, b = os.path.join(tmp, "a"), os.path.join(tmp, "b")
        os.makedirs(a)
        os.makedirs(b)
        os.makedirs(os.path.join(tmp, "gone"))
        args.state_dir = os.path.join(tmp, "state")
        cfg = example()
        cfg["generation"] = "from-a"
        path_a = write_config(a, cfg)
        cfg["generation"] = "from-b"
        path_b = write_config(b, cfg)
        os.utime(path_a, (1, 1))
        args.config_file = [path_a, path_b, os.path.join(tmp, "missing", "config.yaml")]
        rc, out = quiet(smc.apply_once, args, stack, host.run)
        assert rc == 0 and "several config files exist" in out and "applied from-b" in out
        for status_dir in (args.state_dir, a, b):
            name = "status.json" if status_dir == args.state_dir else "scylla-monitoring.status.json"
            path = os.path.join(status_dir, name)
            assert json.load(open(path))["generation"] == "from-b", path
            assert os.stat(path).st_mode & 0o777 == 0o600
        assert not os.path.exists(os.path.join(tmp, "missing"))
        assert os.path.exists(os.path.join(args.state_dir, "applied.yaml"))


def test_run_loop():
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        args.poll_interval = 1
        a, b = os.path.join(tmp, "a"), os.path.join(tmp, "b")
        os.makedirs(a)
        os.makedirs(b)
        args.config_file = [os.path.join(a, "config.yaml"), os.path.join(b, "config.yaml")]
        generations = []
        steps = []

        def step(seconds):
            # each poll: run the next change, then stop when none is left
            if not steps:
                raise StopIteration
            steps.pop(0)()

        def write(directory, generation, mtime):
            cfg = example()
            cfg["generation"] = generation
            path = write_config(directory, cfg)
            os.utime(path, (mtime, mtime))

        stack.apply = lambda old, new, argv, env, previous=None: generations.append(new["generation"]) or set()
        stack.sleep = step
        # nothing there yet: the loop waits; then a writes, then b, then a again
        steps += [lambda: None, lambda: write(a, "a1", 100), lambda: write(b, "b1", 200),
                  lambda: write(a, "a2", 300), lambda: None]
        try:
            quiet(smc.run_loop, args, stack, host.run)
        except StopIteration:
            pass
        assert generations == ["a1", "b1", "a2"], generations


def test_run_loop_start():
    """On start, a file that changed while the watcher was down is applied
    whole when the stack is down, and an error does not stop the loop."""
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        args.poll_interval = 1
        cfg = example()
        assert apply(args, stack, host, cfg) == 0
        cfg["generation"] = "g2"
        cfg["targets"]["scylla"][0]["targets"].append("10.0.0.9")
        write_config(args.monitoring_dir, cfg)

        def down(argv, cfg, timeout=None):
            raise smc.ApplyError("prometheus: not ready")
        stack.health = down
        olds = []

        def fake_apply(old, new, argv, env, previous=None):
            olds.append(old)
            if len(olds) == 1:
                raise RuntimeError("boom")
            return set()
        stack.apply = fake_apply
        steps = [lambda: write_config(args.monitoring_dir, dict(cfg, generation="g3"))]

        def step(seconds):
            if not steps:
                raise StopIteration
            steps.pop(0)()
        stack.sleep = step
        try:
            quiet(smc.run_loop, args, stack, host.run)
        except StopIteration:
            pass
        # the first pass is a first apply; it fails, and the next change is
        # applied whole too, since the failed one is incomplete
        assert olds == [None, None]
        assert json.load(open(os.path.join(tmp, "config-state/status.json")))["state"] == "applied"


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("ok")
