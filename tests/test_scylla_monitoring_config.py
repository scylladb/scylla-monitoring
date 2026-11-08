#!/usr/bin/env python3
# Checks scylla_monitoring_config.py: parse, normalize, render, validate and
# status. The rendered example is compared with the golden files in
# tests/data/scylla_monitoring_config/; UPDATE_GOLDEN=1 rewrites them.
# Run: python3 tests/test_scylla_monitoring_config.py
import contextlib
import copy
import glob
import io
import json
import os
import re
import shlex
import shutil
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


def test_manager_agent_targets():
    """targets.manager_agent replaces the copy of scylla; the rest stays as the golden files."""
    golden = tree(os.path.join(GOLDEN, "staging"))
    cfg = example()
    cfg["targets"]["manager_agent"] = [{"targets": ["10.0.0.1:26090", "10.0.0.2"], "labels": {"cluster": "cluster1"}}]
    with tempfile.TemporaryDirectory() as tmp:
        smc.render(cfg, tmp)
        rendered = tree(tmp)
    assert yaml.safe_load(rendered.pop("targets/scylla_manager_agents.yml")) == cfg["targets"]["manager_agent"]
    assert golden.pop("targets/scylla_manager_agents.yml") == golden["targets/scylla_servers.yml"]
    assert rendered == golden
    # the manager_agent job adds 5090 only to a target without a port
    job = [j for j in yaml.safe_load(open("prometheus/prometheus.yml.template"))["scrape_configs"]
           if j["job_name"] == "manager_agent"][0]
    port, address = job["relabel_configs"][:2]
    assert re.fullmatch(port["regex"], "10.0.0.1:26090") and not re.fullmatch(port["regex"], "10.0.0.2")
    assert address["replacement"] == "${1}:5090" and not re.fullmatch(address["regex"], "10.0.0.1:26090;::")


def test_start_all_values():
    """Values a writer sends as start-all.sh flags today reach start-all.sh unchanged."""
    cfg = example()
    cfg["stack"]["manager_version"] = "none"
    cfg["storage"] = {"prometheus_dir": "/data/prometheus", "alertmanager_dir": "/data/alertmanager",
                      "retention_days": 30}
    cfg["cluster"] = "#1234"
    with tempfile.TemporaryDirectory() as tmp:
        smc.load(write_config(tmp, cfg))
    argv, _ = smc.normalize(cfg, DIRS)
    assert values(argv, "-M") == ["none"]
    assert values(argv, "-d") == ["/data/prometheus"] and values(argv, "-f") == ["/data/alertmanager"]
    assert "-G" not in argv
    assert "--storage.tsdb.retention.time=30d" in values(argv, "-b")
    assert values(argv, "--cluster-label") == ["#1234"]
    # prometheus-config.sh renders the label quoted, and promtool accepts it
    with tempfile.TemporaryDirectory() as tmp:
        staging = render_and_check(tmp, argv)
        prom = yaml.safe_load(open(os.path.join(staging, "prometheus", "prometheus.yml")))
        assert prom["global"]["external_labels"]["cluster"] == "#1234"
        jobs = {j["job_name"]: j for j in prom["scrape_configs"]}
        for job in ("prometheus", "grafana"):
            assert jobs[job]["static_configs"][0]["labels"]["cluster"] == "#1234"


def stack_copy(tmp):
    """The files prometheus-config.sh needs, in a monitoring directory of its own."""
    os.makedirs(os.path.join(tmp, "prometheus"))
    for f in ["prometheus-config.sh", "versions.sh", "network-lib.sh"] + glob.glob("prometheus/*.template"):
        shutil.copy2(f, os.path.join(tmp, f))
    return tmp


def render_and_check(tmp, argv):
    """Renders prometheus.yml into a staging directory as prepare does, and
    checks it with promtool when the image is pulled. Returns the staging directory."""
    monitoring = stack_copy(os.path.join(tmp, "m"))
    # a space in the path checks that prometheus-config.sh quotes --output-dir
    staging = os.path.join(tmp, "staging dir")
    smc.render_prometheus_config(argv, staging, monitoring)
    assert not os.path.exists(os.path.join(monitoring, "prometheus", "build"))
    versions = smc.stack_versions(monitoring)
    if shutil.which("docker") and subprocess.run(["docker", "image", "inspect", "prom/prometheus:" + versions[0]],
                                                 capture_output=True).returncode == 0:
        smc.validate(staging, versions)
    else:
        print("skipped promtool: docker or prom/prometheus:%s is not available" % versions[0])
    return staging


def test_validate_prometheus_config():
    """prepare renders prometheus.yml into staging; promtool's error rejects the file."""
    argv, _ = smc.normalize(example(), DIRS)
    assert smc.prometheus_config_cmd(argv) == ["./prometheus-config.sh", "--cluster-label", "cluster1", "-D",
                                               "--restart=unless-stopped", "-A", "127.0.0.1", "--vector-search"]
    with tempfile.TemporaryDirectory() as tmp:
        staging = render_and_check(tmp, argv)
        calls = []

        def fake(cmd, **kwargs):
            calls.append(cmd)
            return SimpleNamespace(returncode=1, stdout="Checking /c/prometheus.yml\n  FAILED: parsing YAML file\n")
        assert rejected(smc.validate, staging, ("v1", "v2"), fake) == "prometheus config: FAILED: parsing YAML file"
        assert calls[0][-4:] == ["check", "config", "--syntax-only", "/c/prometheus.yml"]
        fail = lambda cmd, **kwargs: SimpleNamespace(returncode=1, stdout="illegal option: -x\n")
        assert rejected(smc.render_prometheus_config, argv, staging, tmp, fail) == \
            "prometheus config: prometheus-config.sh failed: illegal option: -x"
        # a last option without its value fails, and leaves prometheus/build alone
        monitoring = os.path.join(tmp, "m")
        res = subprocess.run(["./prometheus-config.sh", "-m", "aalert:9093", "--output-dir"], cwd=monitoring,
                             capture_output=True, text=True)
        assert res.returncode == 1 and "No value given to --output-dir" in res.stderr
        assert not os.path.exists(os.path.join(monitoring, "prometheus", "build"))


def test_no_manager():
    """manager_version none and --no-manager reach start-all.sh as -M none; Prometheus
    then scrapes neither the manager nor its agents, and no manager dashboards load."""
    cfg = example()
    cfg["stack"]["manager_version"] = "none"
    argv, _ = smc.normalize(cfg, DIRS)
    assert values(argv, "-M") == ["none"] and "--no-manager" in smc.prometheus_config_cmd(argv)
    argv, _ = with_extra("--no-manager")
    assert values(argv, "-M") == ["none"] and "--no-manager" not in argv
    # no manager or agent target files reach the live target directory
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        assert apply(args, stack, host, example()) == 0
        live = os.path.join(tmp, "config-build/live/targets")
        assert "scylla_manager_servers.yml" in os.listdir(live)
        assert apply(args, stack, host, cfg) == 0
        assert sorted(os.listdir(live)) == ["node_exporter_servers.yml", "scylla_servers.yml", "vector_search_servers.yml"]
    with tempfile.TemporaryDirectory() as tmp:
        jobs = lambda staging: {j["job_name"] for j in yaml.safe_load(
            open(os.path.join(staging, "prometheus", "prometheus.yml")))["scrape_configs"]}
        assert {"manager_agent", "scylla_manager"} <= jobs(render_and_check(os.path.join(tmp, "with"), ["-M", "3.5"]))
        without = jobs(render_and_check(os.path.join(tmp, "without"), argv))
        assert not {"manager_agent", "scylla_manager"} & without and {"scylla", "node_exporter"} <= without
        # generate-dashboards.sh -t writes the dashboard loaders only
        for manager, loaders in (("3.5", ["load.2025.3.yaml", "load.manager_3.yaml"]), ("none", ["load.2025.3.yaml"])):
            out = os.path.join(tmp, "dashboards-" + manager)
            os.makedirs(out)
            subprocess.run(["./generate-dashboards.sh", "-t", "-v", "2025.3", "-M", manager, "-B", out],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            assert sorted(os.listdir(out)) == loaders, (manager, os.listdir(out))


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
    assert actions(lambda c: c["targets"].update(manager_agent=[{"targets": ["10.0.0.1:26090"]}])) == set()
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
    assert actions(lambda c: c["tls"].update(thanos_port=10903)) == {"reload_traefik"}
    # start-all.sh reads it on the next restart
    assert actions(lambda c: c["stack"].update(quick_startup=True)) == set()
    # to false, Grafana deletes the data source; to true, start-all.sh writes it
    assert actions(lambda c: c["grafana"].update(thanos_datasource=False)) == {"thanos_datasource"}
    old["grafana"]["thanos_datasource"] = False
    assert actions(lambda c: c["grafana"].update(thanos_datasource=True)) == {"restart_stack"}
    assert actions(lambda c: c["grafana"].pop("thanos_datasource")) == {"restart_stack"}
    old["grafana"]["thanos_datasource"] = True
    # true is the default: adding or removing it changes nothing
    assert actions(lambda c: c["grafana"].pop("thanos_datasource")) == set()
    old["grafana"].pop("thanos_datasource")
    assert actions(lambda c: c["grafana"].update(thanos_datasource=True)) == set()
    old["grafana"]["thanos_datasource"] = True
    assert actions(lambda c: c.update(docker={"http_proxy": "http://10.0.0.5:3128"})) == \
        {"docker_proxy", "restart_stack"}
    # a restart covers the reloads, not the password or the certificates
    assert actions(lambda c: (c["storage"].update(retention_days=60), c.update(cluster="c2"),
                              c["grafana"].update(admin_password="x"), c["tls"].update(server_key="k"))) == \
        {"restart_stack", "grafana_password", "install_certs"}


class FakeHost:
    """Records commands, answers the versions and Grafana name lookups, and
    fails the commands named in fail."""

    def __init__(self, fail=()):
        self.commands = []
        self.envs = []
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
        if cmd[0] == "./prometheus-config.sh" and "--output-dir" in cmd:
            # the render validate checks; test_validate_prometheus_config covers it
            return SimpleNamespace(returncode=0, stdout="")
        self.commands.append((cmd, kwargs.get("input")))
        self.envs.append(kwargs.get("env") or {})
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
    return args, smc.Stack(dirs, args, host.run, http, sleep=lambda s: None, listening=lambda h, port: True)


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
        assert names(host) == ["helper dropin", "helper certs", "kill-all.sh --traefik", "start-all.sh -v",
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
        assert names(host) == ["kill-all.sh --traefik", "start-all.sh -v", "start-traefik.sh"]


def test_apply_traefik_kept_without_tls():
    """kill-all.sh removes traefik only when this configuration runs it, or ran it before."""
    kills = lambda host: [n for n in names(host) if n.startswith("kill-all.sh")]
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        cfg = example()
        cfg["tls"]["enabled"] = False
        assert apply(args, stack, host, cfg) == 0
        assert kills(host) == ["kill-all.sh"]
        # TLS turned off with a restart: the traefik it ran goes too
        cfg["tls"]["enabled"] = True
        assert apply(args, stack, host, cfg) == 0
        host.commands.clear()
        cfg["tls"]["enabled"] = False
        cfg["storage"]["retention_days"] = 60
        assert apply(args, stack, host, cfg) == 0
        assert kills(host) == ["kill-all.sh --traefik"]
        # TLS off before and after: traefik stays
        host.commands.clear()
        cfg["storage"]["retention_days"] = 90
        assert apply(args, stack, host, cfg) == 0
        assert kills(host) == ["kill-all.sh"]
        # turning TLS off fails before the restart; the retry still removes traefik
        cfg["tls"]["enabled"] = True
        assert apply(args, stack, host, cfg) == 0
        host.commands.clear()
        host.fail = {"sudo"}
        cfg["tls"]["enabled"] = False
        cfg["storage"]["retention_days"] = 60
        cfg["systemd"].clear()
        assert apply(args, stack, host, cfg) == 1
        assert kills(host) == []
        host.fail = set()
        assert apply(args, stack, host, cfg) == 0
        assert kills(host) == ["kill-all.sh --traefik"]
        # once applied, the next restart leaves traefik
        host.commands.clear()
        cfg["storage"]["retention_days"] = 90
        assert apply(args, stack, host, cfg) == 0
        assert kills(host) == ["kill-all.sh"]


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

        def restart(argv, env, cfg, first=False, traefik=False):
            calls.append([v for v in smc.option_values(argv, "-b") if "retention" in v][0])
            if len(calls) == 1:
                real_restart(argv, env, cfg, first, traefik)
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



def test_compose_checked_before_apply():
    """In compose mode, make_compose.py builds the stack while the file is prepared:
    its error rejects the file before anything runs, and prometheus.yml is
    rendered with its prometheus-config.sh command."""
    import make_compose
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        stack.compose = True
        renders = []
        recorded = host.run

        def run(cmd, **kwargs):
            if cmd[0] == "./prometheus-config.sh" and "--output-dir" in cmd:
                renders.append((cmd, kwargs.get("env")))
            return recorded(cmd, **kwargs)
        host.run = run
        command = ["./prometheus-config.sh", "-m", "aalert:9093", "-G", "agraf:3000"]

        def build(argv, environ, cwd):
            if "-l" in argv:
                raise smc.ConfigError("Port mapping is not supported with host network")
            result = make_compose.Stack()
            result.commands = [command]
            return result
        stack.compose_build = build
        cfg = example()
        cfg["stack"]["extra_flags"] = ["-l", "-m 9094"]
        assert apply(args, stack, host, cfg) == 1
        status = json.load(open(os.path.join(tmp, "config-state/status.json")))
        assert status["state"] == "rejected" and status["error"].startswith("make_compose.py: Port mapping")
        assert host.commands == [] and not os.path.exists(os.path.join(tmp, "config-state/applied.yaml"))
        cfg["stack"]["extra_flags"] = []
        renders.clear()
        smc.prepare(args, smc.make_dirs(args), write_config(tmp, cfg), host.run, stack)
        cmd, env = renders[0]
        assert cmd[:-2] == command and cmd[-2] == "--output-dir" and env["PRIVATE_IP"] == cfg["tls"]["listen_ip"]


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
        assert names(host) == ["helper dropin", "helper certs", "kill-all.sh --traefik", "prometheus-config.sh -m",
                               "grafana-datasource.sh", "docker compose", "docker exec"]
        argv, environ = builds[-1]
        assert "--traefik" in argv and environ["PRIVATE_IP"] == cfg["tls"]["listen_ip"]
        assert environ["CERT_DIR"] == "/certs" and environ["TRAEFIK_GENERATION"] == cfg["generation"]
        assert environ["THANOS_PORT"] == "10911"
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


def test_full_apply_when_down():
    """A container that went down, whose port refuses connections, is started
    by a stack restart, also when the file's changes start nothing, in
    start-all.sh and in compose mode; the privileged actions that did not
    change do not run again. A component that takes connections is up,
    however slow; ports that cannot be worked out are not a component down;
    a forced apply and a rejected file are not checked."""
    import make_compose
    for compose in (False, True):
        with tempfile.TemporaryDirectory() as tmp:
            host = FakeHost()
            args, stack = make_stack(tmp, host)
            args.auto_revert = True
            if compose:
                stack.compose = True

                def build(argv, environ, cwd):
                    result = make_compose.Stack()
                    result.compose = {"services": {}}
                    result.commands = [["./prometheus-config.sh", "-m", "aalert:9093"]]
                    return result
                stack.compose_build = build
            cfg = example()
            assert apply(args, stack, host, cfg) == 0
            restart = "docker compose" if compose else "start-all.sh -v"
            ports = []

            # Grafana crashed: its port refuses connections, and it is not
            # ready, until the stack restarts
            def listening(h, port):
                ports.append((h, port))
                return port != "3000" or restart in names(host)

            def health(argv, c, timeout=None):
                if restart not in names(host):
                    raise smc.ApplyError("grafana: not ready")
            stack.listening, stack.health = listening, health
            host.commands.clear()
            cfg["generation"] = "g2"
            assert apply(args, stack, host, cfg) == 0
            status = json.load(open(os.path.join(tmp, "config-state/status.json")))
            assert status["state"] == "applied" and status["generation"] == "g2"
            assert yaml.safe_load(open(os.path.join(tmp, "config-state/applied.yaml")))["generation"] == "g2"
            assert ("127.0.0.1", "3000") in ports and restart in names(host)
            # compose up starts the exited container; drop-ins, certificates
            # and the password are left as they are
            assert not [n for n in names(host) if n.startswith("helper") or n == "docker exec"]
            assert ("kill-all.sh --traefik" in names(host)) != compose
            # every port takes connections: the same change starts nothing
            stack.listening = lambda h, port: ports.append(port) or True
            stack.health = lambda argv, c, timeout=None: None
            ports.clear()
            host.commands.clear()
            cfg["generation"] = "g3"
            assert apply(args, stack, host, cfg) == 0
            # Alloy, the renderer, the Thanos sidecar and, with TLS, traefik's ping port too
            assert set(ports) == {"9090", "3000", "9093", "3100", "12345", "8081", "10911", "8080"}
            assert restart not in names(host)
            # Promtail, on its port, when it is the collector
            cfg["stack"]["log_collector"] = "promtail"
            cfg["generation"] = "g3a"
            assert apply(args, stack, host, cfg) == 0
            ports.clear()
            cfg["generation"] = "g3a2"
            assert apply(args, stack, host, cfg) == 0 and "9080" in ports and "12345" not in ports

            def probed(env):
                """The ports the check probes with env as env.sh."""
                smc.write_file(os.path.join(tmp, "env.sh"), env)
                seen, listening = [], stack.listening
                stack.listening = lambda h, port: seen.append(port) or True
                assert smc.container_down(smc.make_dirs(args), stack) is False
                stack.listening = listening
                os.remove(os.path.join(tmp, "env.sh"))
                return seen
            # start-loki.sh takes PROMTAIL_PORT, compose does not; both take LOKI_PORT_CMD
            assert ("19080" in probed("PROMTAIL_PORT=19080\n")) != compose
            assert "19081" in probed('LOKI_PORT_CMD="-t 19081"\n')
            # start-loki.sh runs no Promtail with NO_PROMTAIL=1, compose does
            assert ("9080" in probed("NO_PROMTAIL=1\n")) == compose
            assert "8081" in probed("")
            # under host networking Promtail listens on 9080, whatever its port
            applied = os.path.join(tmp, "config-state/applied.yaml")
            text = open(applied).read()
            host_net = yaml.safe_load(text)
            host_net["stack"]["docker_args"].append("--net=host")
            smc.write_file(applied, yaml.safe_dump(host_net), 0o600)
            seen = probed('LOKI_PORT_CMD="-t 19081"\n')
            assert "9080" in seen and "19081" not in seen
            # no renderer with --no-renderer
            host_net["stack"]["extra_flags"].append("--no-renderer")
            smc.write_file(applied, yaml.safe_dump(host_net), 0o600)
            assert "8081" not in probed("")
            smc.write_file(applied, text, 0o600)
            # Thanos that env.sh starts
            assert "10903" in probed("RUN_LOCAL_THANOS=1\n")
            # the collector's port from env.sh, as start-all.sh takes it
            cfg["stack"]["log_collector"] = "alloy"
            cfg["generation"] = "g3e"
            assert apply(args, stack, host, cfg) == 0
            # and the sidecar's, which compose publishes on 10911 anyway
            smc.write_file(os.path.join(tmp, "env.sh"), "ALLOY_PORT=12346\nTHANOS_SC_PORT=10921\n")
            ports.clear()
            cfg["generation"] = "g3e2"
            assert apply(args, stack, host, cfg) == 0 and "12346" in ports and "12345" not in ports
            assert ("10911" in ports, "10921" in ports) == (compose, not compose)
            # an override that is not a port: a warning, and nothing is known to be down
            smc.write_file(os.path.join(tmp, "env.sh"), "ALLOY_PORT=abc\n")
            assert quiet(smc.container_down, smc.make_dirs(args), stack) == (
                False, "warning: cannot check the stack's ports: ValueError\n")
            smc.write_file(os.path.join(tmp, "env.sh"), "ALLOY_PORT=70000\n")
            assert quiet(smc.container_down, smc.make_dirs(args), stack) == (
                False, "warning: cannot check the stack's ports: ValueError\n")
            # -h in env.sh, on which make_compose.py exits
            smc.write_file(os.path.join(tmp, "env.sh"), 'LOKI_PORT_CMD="-h"\n')
            down, out = quiet(smc.container_down, smc.make_dirs(args), stack)
            assert down is False and out.endswith("warning: cannot check the stack's ports: SystemExit\n")
            os.remove(os.path.join(tmp, "env.sh"))
            # the Thanos query, when the stack runs it
            cfg["stack"]["local_thanos"] = True
            cfg["generation"] = "g3b"
            assert apply(args, stack, host, cfg) == 0
            stack.listening = lambda h, port: port != "10903"
            host.commands.clear()
            cfg["generation"] = "g3c"
            assert apply(args, stack, host, cfg) == 0 and restart in names(host)
            # ports that cannot be worked out: nothing is known to be down
            stack.listening = lambda h, port: False
            components = stack.components

            def no_ports(argv):
                raise smc.ApplyError("--stack 2: versions.sh assigns it no ports")
            stack.components = no_ports
            host.commands.clear()
            cfg["generation"] = "g3d"
            assert apply(args, stack, host, cfg) == 0 and restart not in names(host)
            stack.components = components
            # nor is a malformed applied.yaml
            applied = os.path.join(tmp, "config-state/applied.yaml")
            text = open(applied).read()
            smc.write_file(applied, "stack: 1\n", 0o600)
            # the warning names the error, not the file's values
            assert quiet(smc.container_down, smc.make_dirs(args), stack) == (
                False, "warning: cannot check the stack's ports: AttributeError\n")
            smc.write_file(applied, text, 0o600)
            # a forced apply runs everything anyway, and a rejected file runs nothing
            stack.listening = lambda h, port: ports.append(port) or True
            ports.clear()
            args.force = True
            cfg["generation"] = "g4"
            assert apply(args, stack, host, cfg) == 0 and ports == []
            args.force = False
            cfg["generation"] = "g5"
            cfg["tls"]["listen_ip"] = ""
            assert apply(args, stack, host, cfg) == 1 and ports == []
            assert json.load(open(os.path.join(tmp, "config-state/status.json")))["state"] == "rejected"


def test_port_listening():
    """Only a refused connection is a port nobody listens on."""
    import socket
    server = socket.socket()
    server.bind(("127.0.0.1", 0))
    server.listen()
    port = server.getsockname()[1]
    assert smc.port_listening("127.0.0.1", port)
    server.close()
    assert not smc.port_listening("127.0.0.1", port)


def test_stack_flags():
    """stack.quick_startup and grafana.thanos_datasource are start-all.sh
    flags; their defaults add none."""
    cfg = example()
    argv, _ = smc.normalize(cfg, DIRS)
    assert "--quick-startup" not in argv and "--no-thanos-datasource" not in argv
    cfg["stack"]["quick_startup"] = True
    cfg["grafana"]["thanos_datasource"] = False
    with tempfile.TemporaryDirectory() as tmp:
        smc.load(write_config(tmp, cfg))
    argv, _ = smc.normalize(cfg, DIRS)
    assert "--quick-startup" in argv and "--no-thanos-datasource" in argv


def test_docker_proxy():
    """docker's proxy environment file: one quoted line per proxy, 0600 since
    a URL can hold credentials, and no value that could add a line or another
    variable."""
    cfg = example()
    cfg["docker"] = {"http_proxy": "http://10.0.0.5:3128", "https_proxy": "http://u:p%40$s@10.0.0.5:3128"}
    with tempfile.TemporaryDirectory() as tmp:
        smc.load(write_config(tmp, cfg))
        smc.render(cfg, tmp)
        path = os.path.join(tmp, "docker/proxy.env")
        assert open(path).read() == 'HTTP_PROXY="http://10.0.0.5:3128"\nHTTPS_PROXY="http://u:p%40$s@10.0.0.5:3128"\n'
        assert os.stat(path).st_mode & 0o777 == 0o600
        cfg["docker"] = {}
        smc.render(cfg, tmp)
        assert not os.path.exists(os.path.join(tmp, "docker"))
        for bad in ('http://a" "LD_PRELOAD=/x', "http://a\nExecStartPre=/x", "10.0.0.5:3128", "http://a\\b",
                    "http:///x", "http://?q", "http://#f", "http://user@", "http://:3128", "http://a:3128\n",
                    "http://a\x01b:3128", "http://a\x7f:3128"):
            cfg["docker"] = {"http_proxy": bad}
            assert rejected(smc.load, write_config(tmp, cfg)).startswith("docker.http_proxy: must match")
        # a section without a proxy, a misspelled one, is rejected, not
        # taken as the proxy removed
        for bad in ({}, {"htp_proxy": "http://10.0.0.5:3128"}):
            cfg["docker"] = bad
            assert rejected(smc.load, write_config(tmp, cfg)).startswith("docker")
        cfg["docker"] = {"https_proxy": "http://10.0.0.5:3128"}
        smc.load(write_config(tmp, cfg))


def test_thanos_datasource():
    """--no-thanos-datasource, from grafana.thanos_datasource or
    stack.extra_flags, writes thanos.yaml as a file that deletes the data
    source, also when the file is gone, since Grafana keeps the data source.
    Grafana restarts once: on its own, with the stack, or with
    grafana_datasource."""
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        cfg = example()
        assert apply(args, stack, host, cfg) == 0
        path = os.path.join(tmp, "grafana/provisioning/datasources/thanos.yaml")
        smc.write_file(path, "apiVersion: 1\ndatasources:\n- name: thanos\n")
        host.commands.clear()
        cfg["generation"] = "g2"
        cfg["grafana"]["thanos_datasource"] = False
        assert apply(args, stack, host, cfg) == 0
        assert names(host) == ["docker restart"]
        assert yaml.safe_load(open(path)) == {"apiVersion": 1, "deleteDatasources": [{"name": "thanos", "orgId": 1}]}
        # a first apply finds it deleted already
        host.commands.clear()
        args.force = True
        assert apply(args, stack, host, cfg) == 0
        assert "docker restart" not in names(host)
        # with a stack restart, Grafana is not restarted on its own
        smc.write_file(path, "apiVersion: 1\ndatasources:\n- name: thanos\n")
        host.commands.clear()
        assert apply(args, stack, host, cfg) == 0
        assert "docker restart" not in names(host) and "start-all.sh -v" in names(host)
        assert open(path).read() == smc.DELETE_THANOS_DATASOURCE
        args.force = False
        # back to true: the stack restarts, the delete file goes, and
        # start-all.sh writes the data source
        host.commands.clear()
        cfg["generation"] = "g3"
        cfg["grafana"]["thanos_datasource"] = True
        assert apply(args, stack, host, cfg) == 0
        assert "start-all.sh -v" in names(host) and "docker restart" not in names(host)
        assert not os.path.exists(path)
        # with the file gone, the delete file is written all the same; with
        # the Scylla data source changed too, Grafana restarts once
        cfg["generation"] = "g4"
        cfg["grafana"]["thanos_datasource"] = False
        cfg["grafana"]["datasource"]["scylla_password"] = "other"
        host.commands.clear()
        assert apply(args, stack, host, cfg) == 0
        assert names(host) == ["docker restart"] and open(path).read() == smc.DELETE_THANOS_DATASOURCE
        # the flag in stack.extra_flags restarts the stack and deletes it too
        cfg["grafana"]["thanos_datasource"] = True
        cfg["generation"] = "g5"
        assert apply(args, stack, host, cfg) == 0
        smc.write_file(path, "apiVersion: 1\ndatasources:\n- name: thanos\n")
        cfg["stack"]["extra_flags"] = ["--no-thanos-datasource"]
        cfg["generation"] = "g6"
        host.commands.clear()
        assert apply(args, stack, host, cfg) == 0
        assert "start-all.sh -v" in names(host) and "docker restart" not in names(host)
        assert open(path).read() == smc.DELETE_THANOS_DATASOURCE
        # a named stack changes its own Grafana's file, not the main stack's
        main = "apiVersion: 1\ndatasources:\n- name: thanos\n"
        named = os.path.join(tmp, "grafana/stack/2/provisioning/datasources/thanos.yaml")
        smc.write_file(path, main)
        smc.write_file(named, main)
        assert stack.thanos_datasource(["--stack", "2"], True) is None
        assert open(path).read() == main and open(named).read() == smc.DELETE_THANOS_DATASOURCE
        # back to true, a stack restart removes the named stack's delete
        # file, which start-thanos.sh does not replace; other files stay
        stack.thanos_datasource(["--stack", "2"], False)
        assert not os.path.exists(named) and open(path).read() == main
        stack.thanos_datasource(["--stack", "2"], False)
        cfg["stack"]["extra_flags"] = ["--stack", "2"]
        cfg["grafana"]["thanos_datasource"] = False
        cfg["generation"] = "g7"
        assert apply(args, stack, host, cfg) == 0
        assert open(named).read() == smc.DELETE_THANOS_DATASOURCE
        cfg["grafana"]["thanos_datasource"] = True
        cfg["generation"] = "g8"
        host.commands.clear()
        assert apply(args, stack, host, cfg) == 0
        assert "start-all.sh -v" in names(host) and not os.path.exists(named)


def test_pattern_trailing_newline():
    """jsonschema matches a pattern with re.search, where $ also matches before
    a final newline: unit names and Grafana settings reject one too."""
    with tempfile.TemporaryDirectory() as tmp:
        for change in (lambda c: c["systemd"].update({"node-exporter.service\n": "[Service]\n"}),
                       lambda c: c["grafana"]["env"].update({"GF_X\n": "1"})):
            cfg = example()
            change(cfg)
            assert rejected(smc.load, write_config(tmp, cfg))
            cfg = example()
            smc.load(write_config(tmp, cfg))


def test_apply_docker_proxy():
    """docker's proxy is set first. Its docker restart restarts the watcher,
    and the next pass, finding the proxy in place, completes the apply.
    Without the section on either side docker is left alone, and a revert
    keeps the proxy."""
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        cfg = example()
        assert apply(args, stack, host, cfg) == 0
        assert "helper docker-proxy" not in names(host)
        host.commands.clear()
        cfg["generation"] = "g2"
        cfg["docker"] = {"http_proxy": "http://10.0.0.5:3128", "https_proxy": "http://10.0.0.5:3128"}

        def restarts_docker(cmd, **kwargs):
            if cmd[0] == "sudo" and cmd[3] == "docker-proxy":
                stack.run = host.run  # docker is back, with the proxy in place
                raise SystemExit("the watcher is restarted with docker")
            return host.run(cmd, **kwargs)
        stack.run = restarts_docker
        try:
            apply(args, stack, host, cfg)
            raise AssertionError("the pass was not interrupted")
        except SystemExit:
            pass
        assert host.commands == [] and "g2" not in open(os.path.join(tmp, "config-state/applied.yaml")).read()
        # the next pass: the helper finds the proxy unchanged, then the stack starts
        assert apply(args, stack, host, cfg) == 0
        assert names(host) == ["helper docker-proxy", "kill-all.sh --traefik", "start-all.sh -v", "start-traefik.sh"]
        assert host.commands[0][0][-1] == tmp + "/config-build/staging/docker/proxy.env"
        assert json.load(open(os.path.join(tmp, "config-state/status.json")))["generation"] == "g2"
        # a first apply sets it again; the helper restarts docker only on a change
        host.commands.clear()
        args.force = True
        assert apply(args, stack, host, cfg) == 0
        assert names(host)[0] == "helper docker-proxy"
        args.force = False
        # a failed apply is reverted without touching docker
        host.commands.clear()
        args.auto_revert = True
        g2 = copy.deepcopy(cfg)
        cfg["generation"] = "g3"
        cfg["docker"]["http_proxy"] = "http://10.0.0.6:3128"
        checks = []

        def ready_once(argv, c, timeout=None):
            checks.append(c["generation"])
            if len(checks) == 1:
                raise smc.ApplyError("grafana: not ready")
        stack.health = ready_once
        assert apply(args, stack, host, cfg) == 1
        assert json.load(open(os.path.join(tmp, "config-state/status.json")))["state"] == "reverted"
        assert names(host).count("helper docker-proxy") == 1
        args.auto_revert = False
        stack.health = lambda argv, c, timeout=None: None
        # docker kept g3's proxy: writing g2's file again, though it is the
        # applied one, sets g2's proxy, and only once
        stale = os.path.join(tmp, "config-state/proxy.stale")
        assert os.path.exists(stale)
        host.commands.clear()
        assert apply(args, stack, host, g2) == 0
        assert names(host)[0] == "helper docker-proxy" and "start-all.sh -v" in names(host)
        assert names(host).count("helper docker-proxy") == 1 and not os.path.exists(stale)
        host.commands.clear()
        assert apply(args, stack, host, g2) == 0 and host.commands == []
        # a revert to a configuration without the section removes the proxy
        cfg = copy.deepcopy(g2)
        cfg.pop("docker")
        assert apply(args, stack, host, cfg) == 0
        cfg["generation"] = "g3"
        cfg["docker"] = {"http_proxy": "http://10.0.0.6:3128"}
        checks.clear()
        stack.health = ready_once
        args.auto_revert = True
        assert apply(args, stack, host, cfg) == 1 and os.path.exists(stale)
        args.auto_revert = False
        stack.health = lambda argv, c, timeout=None: None
        cfg.pop("docker")
        cfg["generation"] = "g3b"
        host.commands.clear()
        assert apply(args, stack, host, cfg) == 0
        assert host.commands[0][0][3:] == ["docker-proxy", "--remove"] and not os.path.exists(stale)
        assert apply(args, stack, host, g2) == 0
        cfg = g2
        # the section removed: the proxy goes, and the stack starts again
        host.commands.clear()
        cfg["generation"] = "g4"
        cfg.pop("docker")
        assert apply(args, stack, host, cfg) == 0
        assert host.commands[0][0][3:] == ["docker-proxy", "--remove"]
        assert "start-all.sh -v" in names(host)
        # with no section before or after, a first apply leaves docker alone
        host.commands.clear()
        args.force = True
        assert apply(args, stack, host, cfg) == 0
        assert "helper docker-proxy" not in names(host)


def test_root_helper_docker_proxy():
    """The helper installs docker's proxy as a root-only environment file
    with a drop-in that reads it, restarts docker only when either changes
    or when a restart it started did not happen, and refuses a file with
    any other line."""
    with tempfile.TemporaryDirectory() as tmp:
        etc, bin_dir, log = os.path.join(tmp, "etc"), os.path.join(tmp, "bin"), os.path.join(tmp, "systemctl.log")
        os.makedirs(bin_dir)
        # docker's invocation id changes on each restart; "down" makes docker
        # inactive, "fail" makes the restart fail without running
        q = lambda name: shlex.quote(os.path.join(tmp, name))
        smc.write_file(os.path.join(tmp, "id"), "1\n")
        smc.write_file(os.path.join(bin_dir, "systemctl"), """#!/bin/sh
case "$1" in
is-active) [ ! -e {down} ] ;;
show) cat {id} ;;
restart) [ ! -e {fail} ] || exit 1; echo "$*" >> {log}; echo $(( $(cat {id}) + 1 )) > {id} ;;
*) echo "$*" >> {log} ;;
esac
""".format(down=q("down"), fail=q("fail"), id=q("id"), log=shlex.quote(log)), 0o755)
        helper = os.path.join(tmp, "root.sh")
        pending = os.path.join(tmp, "pending")
        text = open("scylla-monitoring-root.sh").read()
        for old, new in (("SYSTEMD_DIR=/etc/systemd/system\n", "SYSTEMD_DIR=%s\n" % etc),
                         ("PENDING=/run/scylla-monitoring-docker-proxy\n", "PENDING=%s\n" % pending)):
            assert old in text
            text = text.replace(old, new)
        smc.write_file(helper, text, 0o755)
        env = dict(os.environ, PATH=bin_dir + ":" + os.environ["PATH"])
        src = os.path.join(tmp, "proxy.env")
        dropin = os.path.join(etc, "docker.service.d/50-scylla-monitoring.conf")
        envfile = os.path.join(etc, "docker.service.d/50-scylla-monitoring.env")
        unit = "[Service]\nEnvironmentFile=%s\n" % envfile

        def run_helper(arg, content=None):
            if content is not None:
                smc.write_file(src, content)
            res = subprocess.run([helper, "docker-proxy", arg], env=env, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, universal_newlines=True)
            calls = open(log).read().splitlines() if os.path.exists(log) else []
            if calls:
                os.remove(log)
            return res.returncode, calls

        good = 'HTTP_PROXY="http://10.0.0.5:3128"\nHTTPS_PROXY="http://u:p@10.0.0.5:3128"\n'
        restart = (0, ["daemon-reload", "restart docker.service"])
        assert run_helper(src, good) == restart
        assert open(envfile).read() == good and os.stat(envfile).st_mode & 0o777 == 0o600
        assert open(dropin).read() == unit
        assert run_helper(src) == (0, [])
        # a drop-in changed by hand is written again
        smc.write_file(dropin, "[Service]\nExecStartPre=/bin/true\n")
        assert run_helper(src) == restart and open(dropin).read() == unit
        for bad in ('ExecStartPre=/bin/sh -c id\n', '[Service]\nHTTP_PROXY="http://a"\n', 'LD_PRELOAD="/x"\n',
                    'HTTP_PROXY="a" LD_PRELOAD="/x"\n', 'NO_PROXY="x"\n', 'HTTP_PROXY=http://a\n',
                    'HTTP_PROXY="http://a\x01b"\n'):
            rc, calls = run_helper(src, bad)
            assert rc != 0 and calls == []
        assert open(envfile).read() == good
        assert run_helper("--remove") == restart
        assert not os.path.exists(os.path.dirname(dropin))
        assert run_helper("--remove") == (0, [])
        assert not os.path.exists(pending)
        # a restart that did not happen runs again, once
        fail = os.path.join(tmp, "fail")
        smc.write_file(fail, "")
        assert run_helper(src, good)[0] != 0 and os.path.exists(pending)
        os.remove(fail)
        assert run_helper(src) == restart and not os.path.exists(pending)
        assert run_helper(src) == (0, [])
        # so does a removal
        smc.write_file(fail, "")
        assert run_helper("--remove")[0] != 0
        os.remove(fail)
        assert run_helper("--remove") == restart and not os.path.exists(pending)
        # a docker that failed to start reads the proxy when it starts: no restart
        smc.write_file(fail, "")
        assert run_helper(src, good)[0] != 0
        os.remove(fail)
        smc.write_file(os.path.join(tmp, "down"), "")
        assert run_helper(src) == (0, []) and not os.path.exists(pending)


def test_traefik_thanos_port():
    """traefik's 10911 entry point forwards to THANOS_PORT, by default the
    sidecar; the watcher passes tls.thanos_port, and a change reloads traefik."""
    with tempfile.TemporaryDirectory() as tmp:
        for f in ("start-traefik.sh", "versions.sh"):
            shutil.copy2(f, tmp)

        def url(**env):
            res = subprocess.run(["./start-traefik.sh", "--config-only"], cwd=tmp, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, universal_newlines=True,
                                 env=dict(os.environ, PRIVATE_IP="10.0.0.10", **env))
            if res.returncode != 0:
                return None
            conf = yaml.safe_load(open(os.path.join(tmp, "traefik/build/confs/traefik-conf.yml")))
            return conf["http"]["services"]["sidecar1"]["loadBalancer"]["servers"][0]["url"]
        assert url() == "h2c://127.0.0.1:10911"
        assert url(THANOS_PORT="10903") == "h2c://127.0.0.1:10903"
        assert url(THANOS_PORT="70000") is None and url(THANOS_PORT="1;x") is None
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        cfg = example()
        assert apply(args, stack, host, cfg) == 0
        assert host.envs[names(host).index("start-traefik.sh")]["THANOS_PORT"] == "10911"
        host.commands.clear()
        host.envs.clear()
        cfg["generation"] = "g2"
        cfg["tls"]["thanos_port"] = 10903
        assert apply(args, stack, host, cfg) == 0
        assert names(host) == ["start-traefik.sh --reload"] and host.envs[0]["THANOS_PORT"] == "10903"


def test_path_unit():
    """The path unit watches each --config-file of the watcher's unit and
    starts it, and the image installs it."""
    service = open("packer/files/scylla-monitoring-config.service").read()
    path_unit = open("packer/files/scylla-monitoring-config.path").read()
    words = re.search(r"^ExecStart=(.*)$", service, re.M).group(1).split()
    config_files = [words[i + 1] for i, w in enumerate(words[:-1]) if w == "--config-file"]
    assert config_files and re.findall(r"^PathChanged=(.*)$", path_unit, re.M) == config_files
    assert re.findall(r"^Unit=(.*)$", path_unit, re.M) == ["scylla-monitoring-config.service"]
    installer = open("packer/files/scylla_monitoring_install_ami").read()
    assert "'scylla-monitoring-config.path'" in installer and "run('systemctl enable ' + ' '.join(units))" in installer


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
        assert rc == 0 and "several config files exist" in out and "applied generation from-b" in out
        for status_dir in (args.state_dir, a, b):
            name = "status.json" if status_dir == args.state_dir else "scylla-monitoring.status.json"
            path = os.path.join(status_dir, name)
            assert json.load(open(path))["generation"] == "from-b", path
            assert os.stat(path).st_mode & 0o777 == 0o600
        assert not os.path.exists(os.path.join(tmp, "missing"))
        assert os.path.exists(os.path.join(args.state_dir, "applied.yaml"))


def test_status_in_new_config_dir():
    """A config directory the writer just created, 0700: the status appears beside the file after the first apply."""
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        config_dir = os.path.join(tmp, "home", "scylla-monitoring")
        os.makedirs(config_dir, mode=0o700)
        os.chmod(config_dir, 0o700)
        path = write_config(config_dir, example())
        os.chmod(path, 0o600)
        args.config_file = [path]
        rc, _ = quiet(smc.apply_once, args, stack, host.run)
        status = os.path.join(config_dir, "scylla-monitoring.status.json")
        assert rc == 0 and json.load(open(status))["state"] == "applied"
        assert os.stat(status).st_mode & 0o777 == 0o600


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

        stack.apply = lambda old, new, argv, env, previous=None, ran_traefik=False, proxy_stale=False, restart=False: \
            generations.append(new["generation"]) or set()
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

        def fake_apply(old, new, argv, env, previous=None, ran_traefik=False, proxy_stale=False, restart=False):
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


def test_run_loop_internal_error():
    """An unexpected error names the generation of the file being applied,
    once it is known; the loop goes on, and the next file is applied whole."""
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        args.poll_interval = 1
        cfg = example()
        assert apply(args, stack, host, cfg) == 0
        state = os.path.join(tmp, "config-state")
        applied = open(os.path.join(state, "applied.yaml")).read()
        olds = []

        def fake_apply(old, new, argv, env, previous=None, ran_traefik=False, proxy_stale=False, restart=False):
            olds.append(old)
            if new["generation"] == "g2":
                raise RuntimeError("secret value")
            return set()
        stack.apply = fake_apply
        statuses = []

        def status():
            statuses.append(json.load(open(os.path.join(state, "status.json"))))
            assert open(os.path.join(state, "applied.yaml")).read() == applied
            assert os.path.exists(os.path.join(state, "applied.incomplete"))
        load, render = smc.load, smc.render

        def fail(error):
            def raise_(*a, **kw):
                raise error
            return raise_
        steps = [status,
                 # before the file is loaded, its generation is not known
                 lambda: setattr(smc, "load", fail(KeyError("x"))),
                 lambda: write_config(args.monitoring_dir, dict(cfg, generation="g3")),
                 status,
                 lambda: setattr(smc, "load", load),
                 # after it is loaded, an error while preparing it names it
                 lambda: setattr(smc, "render", fail(RuntimeError("secret value"))),
                 lambda: write_config(args.monitoring_dir, dict(cfg, generation="g4")),
                 status,
                 lambda: setattr(smc, "render", render),
                 lambda: write_config(args.monitoring_dir, dict(cfg, generation="g5"))]

        def step(seconds):
            if not steps:
                raise StopIteration
            steps.pop(0)()
        stack.sleep = step
        write_config(args.monitoring_dir, dict(cfg, generation="g2"))
        try:
            quiet(smc.run_loop, args, stack, host.run)
        except StopIteration:
            pass
        finally:
            smc.load, smc.render = load, render
        g2, g3, g4 = statuses
        assert g2["state"] == "failed" and g2["generation"] == g2["applied_generation"] == "g2", g2
        assert g2["error"] == "internal error: RuntimeError", g2
        assert g3["state"] == "failed" and g3["generation"] is None and g3["applied_generation"] is None, g3
        assert g3["error"] == "internal error: KeyError", g3
        assert g4["state"] == "failed" and g4["generation"] == g4["applied_generation"] == "g4", g4
        assert g4["error"] == "internal error: RuntimeError", g4
        final = json.load(open(os.path.join(state, "status.json")))
        assert final["state"] == "applied" and final["generation"] == "g5", final
        assert not os.path.exists(os.path.join(state, "applied.incomplete"))
        # g5 is a first apply, since g2's failed apply left the stack incomplete
        assert len(olds) == 2 and olds[1] is None, olds



@contextlib.contextmanager
def fake_clock(stack):
    """time.monotonic follows a clock that only stack.sleep advances, so the
    logged durations are exact; yields a buffer with stderr."""
    t = [0.0]
    monotonic, smc.time.monotonic = smc.time.monotonic, lambda: t[0]
    stack.sleep = lambda s: t.__setitem__(0, t[0] + s)
    err = io.StringIO()
    try:
        with contextlib.redirect_stderr(err):
            yield err
    finally:
        smc.time.monotonic = monotonic


def ready_after(polls):
    """An http that answers 200, and for each component in polls only from that poll on."""
    seen = {}

    def http(method, url):
        name = next((n for n in polls if (":%s/" % polls[n][0]) in url), None)
        if name is None:
            return 200
        seen[name] = seen.get(name, 0) + 1
        return 200 if seen[name] >= polls[name][1] else None
    return http


def test_health_logs():
    with tempfile.TemporaryDirectory() as tmp:
        args, stack = make_stack(tmp, FakeHost())
        # grafana answers on its fourth poll, at 6s
        stack.http = ready_after({"grafana": ("3000", 4)})
        with fake_clock(stack) as err:
            stack.health([], {}, timeout=100)
        assert err.getvalue().splitlines() == [
            "health: waiting for prometheus, grafana, alertmanager, loki",
            "health: prometheus ready after 0s",
            "health: alertmanager ready after 0s",
            "health: loki ready after 0s",
            "health: grafana ready after 6s",
            "health: ready after 6s",
        ]


def test_health_logs_pending():
    with tempfile.TemporaryDirectory() as tmp:
        args, stack = make_stack(tmp, FakeHost())
        # loki answers at 40s: one line at 30s, none at every poll
        stack.http = ready_after({"loki": ("3100", 21)})
        with fake_clock(stack) as err:
            stack.health([], {}, timeout=100)
        lines = err.getvalue().splitlines()
        assert [l for l in lines if "still waiting" in l] == ["health: still waiting after 30s for loki"], lines
        assert lines[-2:] == ["health: loki ready after 40s", "health: ready after 40s"]
        # a timeout prints the pending list and raises as before
        stack.http = ready_after({"loki": ("3100", 1000), "grafana": ("3000", 1000)})
        with fake_clock(stack) as err:
            try:
                stack.health([], {}, timeout=5)
            except smc.ApplyError as e:
                assert e.args[0] == "grafana, loki: not ready"
            else:
                raise AssertionError("no timeout")
        assert err.getvalue().splitlines()[-1] == "health: not ready after 6s: grafana, loki"


def steps(text):
    return [l.split()[1] for l in text.splitlines() if l.startswith("apply: ")]


def test_apply_logs_steps():
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        cfg = example()
        args.config_file = [write_config(tmp, cfg)]
        with fake_clock(stack) as err, contextlib.redirect_stdout(io.StringIO()):
            assert smc.apply_once(args, stack, host.run) == 0
        assert steps(err.getvalue()) == ["prepare", "docker_proxy", "move_staged", "systemd_dropins", "install_certs",
                                         "thanos_datasource", "restart_stack", "health", "grafana_password"], err.getvalue()
        # a certificate rotation: only the steps that run
        cfg["generation"] = "g2"
        cfg["tls"]["server_key"] = "-----BEGIN PRIVATE KEY-----\nnew\n-----END PRIVATE KEY-----\n"
        write_config(tmp, cfg)
        with fake_clock(stack) as err, contextlib.redirect_stdout(io.StringIO()):
            assert smc.apply_once(args, stack, host.run) == 0
        assert steps(err.getvalue()) == ["prepare", "move_staged", "install_certs", "reload_traefik", "health"], err.getvalue()


def test_apply_once_summary():
    with tempfile.TemporaryDirectory() as tmp:
        host = FakeHost()
        args, stack = make_stack(tmp, host)
        cfg = example()
        args.health_timeout = 100
        args.config_file = [write_config(tmp, cfg)]
        stack.http = ready_after({"grafana": ("3000", 2)})
        with fake_clock(stack) as err, contextlib.redirect_stdout(io.StringIO()):
            assert smc.apply_once(args, stack, host.run) == 0
        lines = err.getvalue().splitlines()
        assert lines[0].startswith("picked up %s " % args.config_file[0]) and lines[0].endswith("s after it was written")
        assert lines[-1] == "applied generation %s in 2s (full; actions: docker_proxy, grafana_password, install_certs, " \
                            "restart_stack, systemd_dropins, thanos_datasource)" % cfg["generation"], lines
        # a failed apply
        host = FakeHost(fail=("start-all.sh",))
        os.makedirs(tmp + "/b")
        args, stack = make_stack(tmp + "/b", host)
        args.config_file = [write_config(args.monitoring_dir, cfg)]
        with fake_clock(stack) as err, contextlib.redirect_stdout(io.StringIO()):
            assert smc.apply_once(args, stack, host.run) == 1
        lines = err.getvalue().splitlines()
        assert "apply: restart_stack failed after 0s" in lines, lines
        assert lines[-2].startswith("failed: ")
        assert lines[-1] == "failed generation %s in 0s (full)" % cfg["generation"], lines

if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("ok")
