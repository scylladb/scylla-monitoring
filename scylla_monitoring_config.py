#!/usr/bin/env python3
#
# Configures the monitoring stack from one declarative file, defined by
# scylla-monitoring.schema.json (scylla-monitoring.example.yaml is an example).
#
#   scylla_monitoring_config.py check|apply|run --config-file F [--config-file F2 ...] --monitoring-dir D
#
# check parses and validates the file, renders the derived files into the
# staging directory, checks them with promtool and amtool, writes the status
# file and prints the start-all.sh command line the file stands for. apply
# also applies it, and run applies it whenever it changes. With several
# --config-file paths the newest file is used, and run applies whichever one
# changes; the status is also written next to each of them.
#
# Error messages name the field and its position and never quote values,
# since the file carries secrets.

import argparse
import datetime
import json
import os
import re
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import traceback
import urllib.error
import urllib.request

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA_PATH = os.path.join(HERE, "scylla-monitoring.schema.json")


class ConfigError(Exception):
    """The file cannot be applied; the message is safe to report."""


# start-all.sh options: option -> (takes a value, component). The component
# is the container a change of the option recreates; "stack" options reach
# every container, and --limit, --volume and --param name theirs in the value.
OPTIONS = {
    "-d": (True, "prometheus"), "-g": (True, "grafana"), "-p": (True, "prometheus"),
    "-v": (True, "grafana"), "-s": (True, "prometheus"), "-n": (True, "prometheus"),
    "-a": (True, "grafana"), "-c": (True, "grafana"), "-j": (True, "grafana"),
    "-b": (True, "prometheus"), "-m": (True, "alertmanager"), "-r": (True, "alertmanager"),
    "-R": (True, "prometheus"), "-M": (True, "grafana"), "-G": (True, "grafana"),
    "-D": (True, "stack"), "-L": (True, "prometheus"), "-N": (True, "prometheus"),
    "-C": (True, "alertmanager"), "-Q": (True, "grafana"), "-A": (True, "stack"),
    "-f": (True, "alertmanager"), "-P": (True, "grafana"), "-S": (True, "grafana"),
    "-T": (True, "prometheus"), "-k": (True, "loki"),
    "-h": (False, "stack"), "-l": (False, "stack"), "-e": (False, "stack"), "-E": (False, "grafana"),
    "--log-collector": (True, "loki"), "--alloy-port": (True, "loki"),
    "--alloy-syslog-port": (True, "loki"), "--loki-port": (True, "loki"),
    "--promtail-port": (True, "loki"), "--promtail-binary-port": (True, "loki"),
    "--limit": (True, None), "--volume": (True, None), "--param": (True, None),
    "--evaluation-interval": (True, "prometheus"), "--manager-agents": (True, "prometheus"),
    "--datadog-api-keys": (True, "datadog"), "--datadog-hostname": (True, "datadog"),
    "--stack": (True, "stack"), "--scrap": (True, "prometheus"),
    "--vector-store": (True, "prometheus"), "--vector-search": (True, "prometheus"),
    "--grafana-render-token": (True, "grafana"), "--grafana-render-token-to-file": (True, "grafana"),
    "--target-directory": (True, "prometheus"), "--servers": (True, "prometheus"),
    "--archive": (True, "stack"), "--cluster-label": (True, "prometheus"),
    "--verbose": (False, "stack"), "--no-loki": (False, "loki"), "--no-log-collector": (False, "loki"),
    "--no-alertmanager": (False, "alertmanager"), "--quick-startup": (False, "stack"),
    "--no-manager": (False, "stack"),
    "--no-renderer": (False, "grafana"), "--thanos-sc": (False, "thanos-sc"),
    "--thanos": (False, "thanos"), "--local-thanos": (False, "thanos"),
    "--no-thanos-datasource": (False, "grafana"), "--auto-restart": (False, "stack"),
    "--victoria-metrics": (False, "prometheus"), "--auth": (False, "grafana"),
    "--support-dashboard": (False, "grafana"), "--clear": (False, "grafana"),
    "--disable-anonymous": (False, "grafana"), "--allow-embedding": (False, "grafana"),
    "--disable-embedding": (False, "grafana"), "--enable-protobuf": (False, "prometheus"),
    "--native-histogram": (False, "prometheus"), "--alternator": (False, "grafana"),
    "--no-cas-cdc": (False, "prometheus"), "--no-cas": (False, "prometheus"),
    "--no-cdc": (False, "prometheus"), "--help": (False, "stack"), "--compose": (False, "stack"),
}

# Options the watcher sets from the file itself; extra_flags cannot carry them.
WATCHER_OWNED = {"-s", "-n", "-N", "-R", "-r", "--manager-agents", "--servers",
                 "--target-directory", "--vector-store", "--vector-search", "--cluster-label",
                 "--archive", "--compose", "-h", "--help"}

# Options written another way: --no-loki is --log-collector none, and
# --no-manager is -M none.
CANONICAL = {"--no-loki": ("--log-collector", "none"), "--no-log-collector": ("--log-collector", "none"),
             "--no-manager": ("-M", "none")}

# Options whose value is a secret go to the start scripts in the environment.
SECRET_OPTIONS = {"-a": "GRAFANA_ADMIN_PASSWORD"}

# Docker flags: aliases, flags without a value, flags repeated once per key
# (the key taken from the value), and flags repeated once per value.
DOCKER_ALIASES = {"--net": "--network", "-m": "--memory", "-e": "--env", "-v": "--volume",
                  "-p": "--publish", "-u": "--user", "-l": "--label", "-h": "--hostname",
                  "-w": "--workdir", "-c": "--cpu-shares"}
DOCKER_NO_VALUE = {"--rm", "--privileged", "--init", "--read-only", "-d", "--detach", "-i",
                   "--interactive", "-t", "--tty", "-P", "--publish-all", "--oom-kill-disable",
                   "--no-healthcheck"}
DOCKER_KEYED = {
    "--env": lambda v: v.partition("=")[0],
    "--volume": lambda v: v.split(":")[1] if ":" in v else v,
    "--publish": lambda v: v.rsplit(":", 1)[-1],
    "--label": lambda v: v.partition("=")[0],
    "--log-opt": lambda v: v.partition("=")[0],
    "--ulimit": lambda v: v.partition("=")[0],
    "--sysctl": lambda v: v.partition("=")[0],
}
DOCKER_MULTI = {"--cap-add", "--cap-drop", "--dns", "--add-host", "--device", "--security-opt",
                "--group-add", "--mount", "--tmpfs"}


def split_words(text, what):
    """shlex.split, with an unclosed quote reported as a ConfigError."""
    try:
        return shlex.split(text)
    except ValueError as e:
        raise ConfigError("%s: %s" % (what, e))


def docker_groups(text):
    """Splits docker arguments into [(setting key, text)], one per flag."""
    # ponytail: a flag followed by a word not starting with - takes it as its
    # value unless it is in DOCKER_NO_VALUE; add flags there as they come up.
    tokens = split_words(text, "docker arguments")
    groups = []
    i = 0
    while i < len(tokens):
        flag = tokens[i]
        if not flag.startswith("-"):
            raise ConfigError("docker arguments: a value without a flag")
        name, eq, value = flag.partition("=")
        words = [flag]
        if not eq and name not in DOCKER_NO_VALUE and i + 1 < len(tokens) and not tokens[i + 1].startswith("-"):
            value = tokens[i + 1]
            words.append(value)
            i += 1
        name = DOCKER_ALIASES.get(name, name)
        if name in DOCKER_KEYED:
            key = (name, DOCKER_KEYED[name](value))
        elif name in DOCKER_MULTI:
            key = (name, value)
        else:
            key = (name,)
        groups.append((key, " ".join(words)))
        i += 1
    return groups


def split_container(opt, value):
    container, comma, rest = value.partition(",")
    if not comma or not container or not rest:
        raise ConfigError("%s: the value is <container>,<setting>" % opt)
    return container, rest


def expand(opt, value):
    """Splits one option into [(key, option, value)], one per setting it holds."""
    if opt == "-D":
        return [(("-D",) + key, "-D", text) for key, text in docker_groups(value)]
    if opt == "--limit":
        container, rest = split_container(opt, value)
        return [(("--limit", container) + key, opt, container + "," + text)
                for key, text in docker_groups(rest)]
    if opt == "--param":
        container, rest = split_container(opt, value)
        if not rest.split():
            raise ConfigError("--param: the flag is empty")
        return [(("--param", container, rest.split()[0].partition("=")[0]), opt, value)]
    if opt == "--volume":
        container, rest = split_container(opt, value)
        dst = rest.split(":")[1] if ":" in rest else rest
        return [(("--volume", container, dst), opt, value)]
    if opt == "-b":
        if not value.split():
            raise ConfigError("-b: the value is empty")
        flag = "--" + value.split()[0].partition("=")[0].lstrip("-")
        return [(("-b", flag), opt, value)]
    if opt == "-c":
        return [(("-c", value.partition("=")[0]), opt, value)]
    if opt in ("-j", "-T", "-C"):
        return [((opt, value), opt, value)]
    return [((opt,), opt, value)]


def parse_flags(words, owned=WATCHER_OWNED, what="extra_flags"):
    """Parses start-all.sh arguments into [(option, value or None)]; owned
    are the options rejected, what names the arguments in errors."""
    result = []
    i = 0
    while i < len(words):
        word = words[i]
        if word.startswith("--"):
            opts = [word]
        elif word.startswith("-") and len(word) > 1:
            # getopts: bundled flags (-le), or a value attached to its option (-v2025.1)
            opts = []
            for j, letter in enumerate(word[1:], 1):
                opt = "-" + letter
                if opt in OPTIONS and OPTIONS[opt][0] and j < len(word) - 1:
                    opts.append((opt, word[j + 1:]))
                    break
                opts.append(opt)
        else:
            raise ConfigError("%s: an argument without an option" % what)
        for opt in opts:
            if isinstance(opt, tuple):
                result.append(opt)
                continue
            if opt not in OPTIONS:
                # the name only: a value attached with = may be a secret
                raise ConfigError("%s: unknown option %s" % (what, opt.partition("=")[0]))
            if OPTIONS[opt][0]:
                if i + 1 >= len(words):
                    raise ConfigError("%s: %s needs a value" % (what, opt))
                i += 1
                result.append((opt, words[i]))
            else:
                result.append((opt, None))
        i += 1
    for opt, _ in result:
        if opt in owned:
            raise ConfigError("%s: %s is set by the watcher from the file" % (what, opt))
    return result


class Dirs:
    """The watcher's paths: staging holds the rendered files, live the ones
    the containers mount, state the applied file and the status, and
    config_files the config paths, each written by its own writer."""

    def __init__(self, monitoring_dir, staging_dir=None, state_dir=None, config_files=()):
        self.monitoring = monitoring_dir
        build = staging_dir or os.path.join(monitoring_dir, "config-build")
        self.staging = os.path.join(build, "staging")
        self.live = os.path.join(build, "live")
        self.state = state_dir or os.path.join(monitoring_dir, "config-state")
        self.config_files = list(config_files)


def derive(cfg, dirs):
    """The start-all.sh options the file stands for, before extra_flags."""
    stack = cfg["stack"]
    storage = cfg.get("storage", {})
    grafana = cfg.get("grafana", {})
    opts = [("-v", stack["scylla_version"])]
    if "manager_version" in stack:
        opts.append(("-M", stack["manager_version"]))
    if stack.get("alertmanager") is False:
        opts.append(("--no-alertmanager", None))
    if "log_collector" in stack:
        opts.append(("--log-collector", stack["log_collector"]))
    if stack.get("thanos_sidecar"):
        if "prometheus_dir" not in storage:
            raise ConfigError("stack.thanos_sidecar: needs storage.prometheus_dir")
        opts.append(("--thanos-sc", None))
    if stack.get("local_thanos"):
        opts.append(("--local-thanos", None))
    if stack.get("quick_startup"):
        opts.append(("--quick-startup", None))
    if "bind_address" in stack:
        opts.append(("-A", stack["bind_address"]))
    opts += [("-D", d) for d in stack.get("docker_args", [])]
    for field, opt in (("prometheus_dir", "-d"), ("grafana_dir", "-G"), ("alertmanager_dir", "-f")):
        if field in storage:
            opts.append((opt, storage[field]))
    if "retention_days" in storage:
        opts.append(("-b", "--storage.tsdb.retention.time=%dd" % storage["retention_days"]))
    if "external_url" in cfg.get("prometheus", {}):
        opts.append(("-b", "--web.external-url=" + cfg["prometheus"]["external_url"]))
        opts.append(("-b", "--web.route-prefix=/"))
    if "root_url" in grafana:
        opts.append(("-c", "GF_SERVER_ROOT_URL=" + grafana["root_url"]))
    if "default_theme" in grafana:
        opts.append(("-c", "GF_USERS_DEFAULT_THEME=" + grafana["default_theme"]))
    opts += [("-c", "%s=%s" % kv) for kv in grafana.get("env", {}).items()]
    if "anonymous_role" in grafana:
        opts.append(("-Q", grafana["anonymous_role"]))
    if grafana.get("thanos_datasource") is False:
        opts.append(("--no-thanos-datasource", None))
    if "cluster" in cfg:
        opts.append(("--cluster-label", cfg["cluster"]))
    opts.append(("--target-directory", os.path.join(dirs.live, "targets")))
    if "vector_search" in cfg["targets"]:
        opts.append(("--vector-search", "vector_search_servers.yml"))
    if "alert_rules" in cfg:
        opts.append(("-R", os.path.join(dirs.live, "rules")))
    if "alertmanager_config" in cfg:
        opts.append(("-r", os.path.join(dirs.live, "alertmanager")))
    return opts


def normalize(cfg, dirs):
    """Returns the start-all.sh arguments and the environment for the secrets.

    A value in extra_flags replaces the derived value with the same key: one
    value per single-value option, per -b flag, -c variable, docker setting,
    and --limit, --param or --volume setting of a container."""
    extra = parse_flags([w for item in cfg["stack"].get("extra_flags", []) for w in split_words(item, "extra_flags")])
    env = {}
    grafana = cfg.get("grafana", {})
    if "admin_password" in grafana:
        env["GRAFANA_ADMIN_PASSWORD"] = grafana["admin_password"]
    datasource = grafana.get("datasource", {})
    if "scylla_user" in datasource:
        env["SCYLLA_USER"] = datasource["scylla_user"]
    if "scylla_password" in datasource:
        env["SCYLLA_PSSWD"] = datasource["scylla_password"]
    merged = {}
    for opt, value in derive(cfg, dirs) + extra:
        if opt in SECRET_OPTIONS:
            env[SECRET_OPTIONS[opt]] = value
            continue
        opt, value = CANONICAL.get(opt, (opt, value))
        if value is None:
            merged[(opt,)] = (opt, None)
            continue
        for key, o, v in expand(opt, value):
            merged[key] = (o, v)
    argv = []
    for opt, value in merged.values():
        argv += [opt] if value is None else [opt, value]
    return argv, env


def dump_yaml(data):
    return yaml.safe_dump(data, default_flow_style=False, sort_keys=False)


def write_file(path, text, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(path, mode)


def render(cfg, staging, no_manager=False):
    """Writes every derived file into the staging directory; without Scylla
    Manager (no_manager), no manager or agent targets."""
    for sub in ("targets", "rules", "alertmanager", "certs", "systemd", "docker", "prometheus"):
        shutil.rmtree(os.path.join(staging, sub), ignore_errors=True)
    targets = cfg["targets"]
    scylla = dump_yaml(targets["scylla"])
    files = {
        "targets/scylla_servers.yml": scylla,
        "targets/node_exporter_servers.yml": dump_yaml(targets["node_exporter"]) if "node_exporter" in targets else scylla,
    }
    if not no_manager:
        files["targets/scylla_manager_agents.yml"] = \
            dump_yaml(targets["manager_agent"]) if "manager_agent" in targets else scylla
        # An empty list, so Prometheus has a file to read without targets.manager.
        files["targets/scylla_manager_servers.yml"] = dump_yaml(targets.get("manager", []))
    if "vector_search" in targets:
        files["targets/vector_search_servers.yml"] = dump_yaml(targets["vector_search"])
    if "alert_rules" in cfg:
        files["rules/prometheus.rules.yml"] = dump_yaml(cfg["alert_rules"])
    if "alertmanager_config" in cfg:
        files["alertmanager/config.yml"] = dump_yaml(cfg["alertmanager_config"])
    tls = cfg.get("tls", {})
    if tls.get("enabled"):
        files["certs/rootCA.crt"] = tls["ca_crt"]
        files["certs/server.crt"] = tls["server_crt"]
    for unit, dropin in cfg.get("systemd", {}).items():
        files["systemd/%s.conf" % unit] = dropin
    for name, text in files.items():
        write_file(os.path.join(staging, name), text)
    if tls.get("enabled"):
        write_file(os.path.join(staging, "certs/server.key"), tls["server_key"], 0o600)
    # docker's EnvironmentFile=, which takes a quoted value as is; the URLs
    # can hold credentials
    docker = cfg.get("docker", {})
    proxy = "".join('%s="%s"\n' % (var, docker[field])
                    for field, var in (("http_proxy", "HTTP_PROXY"), ("https_proxy", "HTTPS_PROXY")) if field in docker)
    if proxy:
        write_file(os.path.join(staging, "docker/proxy.env"), proxy, 0o600)


def stack_versions(monitoring_dir):
    """The Prometheus and Alertmanager image versions from versions.sh."""
    out = subprocess.run(["bash", "-c", '. ./versions.sh && echo "$PROMETHEUS_VERSION $ALERT_MANAGER_VERSION"'],
                         cwd=monitoring_dir, stdout=subprocess.PIPE, universal_newlines=True, check=True).stdout
    prometheus, alertmanager = out.split()
    return prometheus, alertmanager


def tool_output(text):
    # promtool and amtool name the file, the rule and the problem, not config
    # values; amtool puts its error on the "Checking '<file>'" line.
    lines = [re.sub(r"^Checking \S+", "", l).strip() for l in text.splitlines()]
    # a URL in an error can carry credentials (a webhook, an SMTP smarthost)
    text = re.sub(r"://[^/@\s]+@", "://***@", " ".join(l for l in lines if l))
    return text[:500] or "failed"


def prometheus_config_cmd(argv):
    """The prometheus-config.sh command for the start-all.sh arguments, with
    the Alertmanager and Grafana addresses worked out as start-all.sh does."""
    cmd = ["./prometheus-config.sh"]
    for opt, to in (("-L", "-L"), ("-T", "-T"), ("--evaluation-interval", "-E"), ("--scrap", "--scrap"),
                    ("--cluster-label", "--cluster-label"), ("--stack", "-s"), ("-D", "-D"), ("-A", "-A"),
                    ("-m", "--alertmanager-port"), ("-g", "--grafana-port")):
        for value in option_values(argv, opt):
            cmd += [to, value]
    for flag in ("--no-cas", "--no-cdc", "--no-cas-cdc", "--native-histogram", "--vector-search",
                 "--no-alertmanager"):
        if flag in argv:
            cmd.append(flag)
    if option(argv, "-M") == "none":
        cmd.append("--no-manager")
    if "-l" in argv:
        cmd += ["-D", "--net=host"]
    return cmd


def render_prometheus_config(argv, staging, monitoring_dir, run=subprocess.run, cmd=None, env=None):
    """Renders prometheus.yml into the staging directory, so validate checks it
    before anything restarts. cmd is the prometheus-config.sh command, by
    default the one start-all.sh runs for argv; env its environment."""
    out = os.path.join(staging, "prometheus")
    res = run((cmd or prometheus_config_cmd(argv)) + ["--output-dir", out], cwd=monitoring_dir, env=env,
              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    if res.returncode != 0:
        raise ConfigError("prometheus config: prometheus-config.sh failed: %s" % tool_output(res.stdout))


def validate(staging, versions, run=subprocess.run):
    """Checks the staged Prometheus config, rules and Alertmanager config with
    the stack's own tools."""
    prometheus, alertmanager = versions
    user = "%d:%d" % (os.getuid(), os.getgid())
    checks = [
        # the rules and target files are checked on their own, or written by the apply
        ("prometheus config", "prometheus", "prom/prometheus:" + prometheus, "promtool",
         ["check", "config", "--syntax-only", "/c/prometheus.yml"]),
        ("alert_rules", "rules", "prom/prometheus:" + prometheus, "promtool", ["check", "rules", "/c/prometheus.rules.yml"]),
        ("alertmanager_config", "alertmanager", "prom/alertmanager:" + alertmanager, "amtool", ["check-config", "/c/config.yml"]),
    ]
    for section, sub, image, tool, tool_args in checks:
        path = os.path.join(staging, sub)
        if not os.path.isdir(path):
            continue
        cmd = ["docker", "run", "--rm", "-u", user, "-v", path + ":/c:ro,z", "--entrypoint", tool, image] + tool_args
        res = run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
        if res.returncode != 0:
            raise ConfigError("%s: %s" % (section, tool_output(res.stdout)))


def schema(strict=False):
    with open(SCHEMA_PATH) as f:
        s = json.load(f)
    if strict:
        make_strict(s)
    return s


# Subschemas that test or combine a value rather than define it; forbidding
# fields in them would change what they match (a tls "if" would stop matching).
CONDITIONS = {"if", "then", "else", "not", "allOf", "anyOf", "oneOf"}


def make_strict(node):
    """Forbids unknown fields in every object that does not say otherwise."""
    if isinstance(node, dict):
        if "properties" in node and "additionalProperties" not in node:
            node["additionalProperties"] = False
        for key, value in node.items():
            if key not in CONDITIONS:
                make_strict(value)
    elif isinstance(node, list):
        for value in node:
            make_strict(value)


def describe(error):
    """A schema error, naming the field and the rule without its value."""
    path = ".".join(str(p) for p in error.absolute_path) or "<root>"
    rule, expected = error.validator, error.validator_value
    if rule in ("required", "additionalProperties", "propertyNames"):
        # these name fields, never values
        return "%s: %s" % (path, error.message)
    if rule == "type":
        return "%s: must be of type %s" % (path, expected)
    if rule == "enum":
        return "%s: must be one of %s" % (path, ", ".join(str(v) for v in expected))
    if rule == "pattern":
        return "%s: must match %s" % (path, expected)
    return "%s: fails %s %s" % (path, rule, json.dumps(expected))


def load(path, strict=False):
    """Parses the file and checks it against the schema."""
    try:
        with open(path) as f:
            cfg = yaml.safe_load(f)
    except yaml.MarkedYAMLError as e:
        # str(e) quotes the line, which may hold a secret
        mark = e.problem_mark
        raise ConfigError("line %d, column %d: %s" % (mark.line + 1, mark.column + 1, e.problem))
    except yaml.YAMLError:
        raise ConfigError("not a valid YAML file")
    except OSError as e:
        raise ConfigError("%s: %s" % (path, e.strerror))
    if not isinstance(cfg, dict):
        raise ConfigError("the file is not a YAML mapping")
    import jsonschema  # only the watcher needs it, not make_compose.py
    errors = sorted(jsonschema.Draft7Validator(schema(strict)).iter_errors(cfg),
                    key=lambda e: [str(p) for p in e.absolute_path])
    if errors:
        raise ConfigError("; ".join(describe(e) for e in errors[:5]), cfg.get("generation"))
    return cfg


def write_private(path, text):
    """Writes a file atomically, 0600."""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix="." + os.path.basename(path) + ".")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def write_status(dirs, status):
    """Writes the status to the state directory, and next to each config
    path as scylla-monitoring.status.json, so a writer finds it beside the
    file it wrote."""
    text = json.dumps(status) + "\n"
    os.makedirs(dirs.state, mode=0o700, exist_ok=True)
    write_private(os.path.join(dirs.state, "status.json"), text)
    for path in dirs.config_files:
        if os.path.isdir(os.path.dirname(path)):
            try:
                write_private(os.path.join(os.path.dirname(path), "scylla-monitoring.status.json"), text)
            except OSError as e:
                # the config directory may be closed to the watcher's user
                print("warning: cannot write the status next to %s: %s" % (path, e.strerror), file=sys.stderr)


def newest(paths):
    """The existing config path written last; warns when several exist."""
    existing = [p for p in paths if os.path.exists(p)]
    if len(existing) > 1:
        print("warning: several config files exist, using the newest: " + ", ".join(existing), file=sys.stderr)
    return max(existing, key=os.path.getmtime) if existing else None


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def prepare(args, dirs, path, run=subprocess.run, stack=None):
    """Loads, normalizes, renders and validates the file. In compose mode
    (stack.compose), make_compose.py builds the stack too, so its checks
    reject the file, and prometheus.yml is rendered with its command.

    Returns (cfg, argv, env); raises ConfigError with the generation, when the
    file has one, as its second argument."""
    if os.path.exists(os.path.join(dirs.monitoring, "env.sh")):
        print("warning: %s/env.sh is sourced by the start scripts and can override the file" % dirs.monitoring,
              file=sys.stderr)
    cfg = load(path, args.strict)
    try:
        argv, env = normalize(cfg, dirs)
        # The derived files hold secrets (the Alertmanager config, the TLS
        # key). The containers read them through their bind mounts, so
        # closing the build directory keeps out other host users only.
        build = os.path.dirname(dirs.staging)
        os.makedirs(build, exist_ok=True)
        os.chmod(build, 0o700)
        render(cfg, dirs.staging, option(argv, "-M") == "none")
        cmd = environ = None
        if stack is not None and stack.compose:
            try:
                built, environ = stack.compose_config(argv, env, cfg)
            except ConfigError as e:
                raise ConfigError("make_compose.py: %s" % e.args[0])
            cmd = next(c for c in built.commands if c[0] == "./prometheus-config.sh")
        render_prometheus_config(argv, dirs.staging, dirs.monitoring, run, cmd, environ)
        validate(dirs.staging, stack_versions(dirs.monitoring), run)
    except ConfigError as e:
        raise ConfigError(e.args[0], cfg["generation"])
    return cfg, argv, env


def rejected(dirs, e):
    generation = e.args[1] if len(e.args) > 1 and isinstance(e.args[1], str) else None
    write_status(dirs, {"generation": generation, "state": "rejected", "error": e.args[0], "time": now()})
    print("rejected: " + e.args[0], file=sys.stderr)
    return 1


def make_dirs(args):
    absolute = lambda p: p and os.path.abspath(p)
    return Dirs(absolute(args.monitoring_dir), absolute(args.staging_dir), absolute(getattr(args, "state_dir", None)),
                [os.path.abspath(p) for p in args.config_file])


# What check prints in place of a secret: the options that carry one, and
# the -c and -D variables whose name says it is one.
SECRET_VALUE_OPTIONS = {"--grafana-render-token", "--datadog-api-keys"}
SECRET_NAME = re.compile(r"PASSWORD|PASSWD|PSSWD|SECRET|TOKEN|KEY", re.I)


def masked(argv):
    words = []
    for i, w in enumerate(argv):
        prev = argv[i - 1] if i else None
        if prev in SECRET_VALUE_OPTIONS:
            w = "***"
        elif prev in ("-c", "-D"):
            # NAME=value at the start of a word or after = (--env=NAME=value)
            w = re.sub(r"(^|[\s=])([A-Za-z_][A-Za-z0-9_]*)=(\S+)",
                       lambda m: m.group(1) + m.group(2) + "=***" if SECRET_NAME.search(m.group(2)) else m.group(0), w)
        words.append(w)
    return words


def check(args, run=subprocess.run):
    """Validates and renders the file into a scratch staging directory, and
    prints the start-all.sh command line; the running watcher's staging and
    status stay as they are."""
    dirs = make_dirs(args)
    path = newest(dirs.config_files)
    if path is None:
        print("error: no config file exists", file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory() as build:
        dirs.staging = os.path.join(build, "staging")
        try:
            cfg, argv, env = prepare(args, dirs, path, run)
        except ConfigError as e:
            print("rejected: " + e.args[0], file=sys.stderr)
            return 1
    print(" ".join(shlex.quote(w) for w in ["./start-all.sh"] + masked(argv)))
    print("environment: " + " ".join(sorted(env)))
    return 0


# What a change in each section needs. A change is looked up under its most
# specific path, so "grafana" covers the grafana fields not listed on their
# own. Every apply also moves the staged targets, rules and Alertmanager
# config into the live directories, which is all a targets change needs.
RESTART = "restart_stack"
ACTIONS = {
    "cluster": ["render_prometheus_config", "reload_prometheus"],
    "targets": [],
    "targets.vector_search": [],
    "alert_rules": ["reload_prometheus"],
    "alertmanager_config": ["reload_alertmanager"],
    "prometheus": [RESTART],
    "storage": [RESTART],
    "stack": [RESTART],
    # start-all.sh reads it when it next starts the stack
    "stack.quick_startup": [],
    "grafana": [RESTART],
    "grafana.admin_password": ["grafana_password"],
    "grafana.datasource": ["grafana_datasource"],
    # from true to false; to true, the stack restarts (see plan)
    "grafana.thanos_datasource": ["thanos_datasource"],
    "tls.ca_crt": ["install_certs", "reload_traefik"],
    "tls.server_crt": ["install_certs", "reload_traefik"],
    "tls.server_key": ["install_certs", "reload_traefik"],
    "tls.enabled": ["install_certs", "start_traefik"],
    "tls.listen_ip": ["start_traefik"],
    "tls.thanos_port": ["reload_traefik"],
    "systemd": ["systemd_dropins"],
    # restarting docker stops the containers, so the stack is started again
    "docker": ["docker_proxy", RESTART],
}
# Adding or removing these changes start-all.sh's arguments (-R, -r, and
# --vector-search, which changes prometheus.yml and the dashboards), so it
# restarts the stack; a change of their content is the action above.
PRESENCE = {"alert_rules", "alertmanager_config", "targets.vector_search"}
# The actions a stack restart already covers.
COVERED_BY_RESTART = {"render_prometheus_config", "reload_prometheus", "reload_alertmanager",
                      "grafana_datasource", "reload_traefik", "start_traefik"}
FIRST_APPLY = {RESTART, "systemd_dropins", "install_certs", "grafana_password", "docker_proxy", "thanos_datasource"}
# start-all.sh --no-thanos-datasource only stops writing thanos.yaml, and
# Grafana keeps a data source it stored; this file tells Grafana to delete it.
DELETE_THANOS_DATASOURCE = "apiVersion: 1\ndeleteDatasources:\n- name: thanos\n  orgId: 1\n"


def section(cfg, path):
    """The value at a dotted path, without the sub-paths ACTIONS lists on their own."""
    value = cfg
    for part in path.split("."):
        if not isinstance(value, dict) or part not in value:
            return None
        value = value[part]
    children = [k[len(path) + 1:] for k in ACTIONS if k.startswith(path + ".")]
    if children and isinstance(value, dict):
        value = {k: v for k, v in value.items() if k not in children}
    return value


def plan(old, new):
    """The actions that take the stack from the old configuration to the new."""
    if old is None:
        return set(FIRST_APPLY)
    actions = set()
    for path, path_actions in ACTIONS.items():
        before, after = section(old, path), section(new, path)
        if before == after:
            continue
        if path in PRESENCE and (before is None) != (after is None):
            actions.add(RESTART)
        else:
            actions.update(path_actions)
    # to true, start-thanos.sh writes the data source with the Thanos query's
    # address; between true and missing, the default, nothing changes
    if "thanos_datasource" in actions and new.get("grafana", {}).get("thanos_datasource") is not False:
        actions.discard("thanos_datasource")
        if section(old, "grafana.thanos_datasource") is False:
            actions.add(RESTART)
    if RESTART in actions:
        actions -= COVERED_BY_RESTART
    return actions


def option_values(argv, opt):
    return [argv[i + 1] for i, w in enumerate(argv[:-1]) if w == opt]


def option(argv, opt, default=None):
    values = option_values(argv, opt)
    return values[-1] if values else default


class Stack:
    """Runs the actions against the stack in the monitoring directory."""

    def __init__(self, dirs, args, run=subprocess.run, http=None, sleep=time.sleep, listening=None):
        self.dirs = dirs
        self.args = args
        self.run = run
        self.http = http or http_status
        self.listening = listening or port_listening
        self.sleep = sleep
        self.compose = getattr(args, "compose", False)
        self.compose_build = None  # make_compose.build, set on first use; tests replace it

    def sh(self, cmd, env=None, input=None):
        res = self.run(cmd, cwd=self.dirs.monitoring, env=dict(os.environ, **(env or {})), input=input,
                       universal_newlines=True)
        if res.returncode != 0:
            raise ApplyError("%s failed" % os.path.basename(cmd[0]) if cmd[0] != "sudo" else "%s %s failed" % (
                os.path.basename(cmd[2]), cmd[3]))

    def host(self, argv):
        bind = option(argv, "-A")
        return bind if bind and bind != "0.0.0.0" else "127.0.0.1"

    def ports(self, argv):
        """The published ports, as start-all.sh works them out: the defaults,
        the port options, and for a secondary stack the ports versions.sh
        assigns it, which replace the options."""
        ports = {"prometheus": option(argv, "-p", "9090"), "grafana": option(argv, "-g", "3000"),
                 "alertmanager": option(argv, "-m", "9093"), "loki": option(argv, "--loki-port", "3100")}
        stack = option(argv, "--stack")
        if stack:
            out = self.run(["bash", "-c", '. ./versions.sh && echo "${STACK_PROMETHEUS[$1]} ${STACK_GRAFANA[$1]} '
                                          '${STACK_ALERTMANAGER[$1]}"', "_", stack],
                           cwd=self.dirs.monitoring, stdout=subprocess.PIPE, universal_newlines=True).stdout.split()
            if len(out) != 3:
                raise ApplyError("--stack %s: versions.sh assigns it no ports" % stack)
            ports.update(zip(("prometheus", "grafana", "alertmanager"), out))
        return ports

    def components(self, argv):
        """The components the configuration runs: (name, port, ready path)."""
        ports = self.ports(argv)
        prometheus_ready = "/health" if "--victoria-metrics" in argv else "/-/ready"
        result = [("prometheus", ports["prometheus"], prometheus_ready), ("grafana", ports["grafana"], "/api/health")]
        if "--no-alertmanager" not in argv:
            result.append(("alertmanager", ports["alertmanager"], "/-/ready"))
        # a secondary stack runs no Loki
        if option(argv, "--log-collector", "alloy") != "none" and not option(argv, "--stack"):
            result.append(("loki", ports["loki"], "/ready"))
        return result

    def extra_ports(self, argv, loki):
        """The ports of the log collector, which runs with Loki, of the
        Grafana renderer and of the Thanos sidecar and query, with env.sh's
        overrides: make_compose.py takes start-all.sh's options over env.sh
        as start-all.sh does."""
        import make_compose
        cwd = self.dirs.monitoring
        v = make_compose.shell_vars(cwd, dict(os.environ), os.path.join(cwd, "env.sh"))
        o = make_compose.options(argv, v, make_compose.Paths(cwd))
        ports = []
        if loki and o["log_collector"] == "alloy":
            ports.append(o["alloy_port"] or "12345")
        # start-loki.sh skips Promtail with NO_PROMTAIL=1; compose does not
        elif loki and o["log_collector"] == "promtail" and (self.compose or v.get("NO_PROMTAIL") != "1"):
            # under host networking Promtail listens on 9080, whatever its
            # port; start-loki.sh takes PROMTAIL_PORT too, compose does not
            host_net = make_compose.HOST_NET.search(o["docker_param"])
            ports.append("9080" if host_net else o["promtail_port"] or
                         (not self.compose and v.get("PROMTAIL_PORT")) or "9080")
        # a secondary stack runs no renderer
        if o["renderer"] and not o["stack"]:
            ports.append("8081")
        if o["thanos_sc"] and o["data_dir"]:
            # start-thanos-sc.sh takes THANOS_SC_PORT; compose publishes 10911
            ports.append((not self.compose and v.get("THANOS_SC_PORT")) or "10911")
        if o["thanos"] or o["local_thanos"]:
            ports.append("10903")
        return ports

    def move_staged(self):
        """Renames each staged file into its live directory; the directories
        stay in place, since the containers' bind mounts hold them."""
        for sub in ("targets", "rules", "alertmanager"):
            staged = os.path.join(self.dirs.staging, sub)
            live = os.path.join(self.dirs.live, sub)
            os.makedirs(live, exist_ok=True)
            names = set(os.listdir(staged)) if os.path.isdir(staged) else set()
            for name in names:
                tmp = os.path.join(live, "." + name + ".new")
                shutil.copy2(os.path.join(staged, name), tmp)
                os.replace(tmp, os.path.join(live, name))
            for name in set(os.listdir(live)) - names:
                os.remove(os.path.join(live, name))

    def stack_dir(self, argv, base):
        stack = option(argv, "--stack")
        return os.path.join(self.dirs.monitoring, base, "stack", stack) if stack else os.path.join(self.dirs.monitoring, base)

    def kill_all(self, argv, traefik):
        cmd = ["./kill-all.sh"]
        for opt in ("-p", "-g", "-m", "--loki-port", "--promtail-port", "--alloy-port", "--stack"):
            if option(argv, opt):
                cmd += [opt, option(argv, opt)]
        # traefik is shared by every stack in the directory; removed only
        # when this configuration runs it, or ran it before
        self.sh(cmd + (["--traefik"] if traefik else []))

    def restart_stack(self, argv, env, cfg, first=False, traefik=False):
        if not self.compose:
            self.kill_all(argv, traefik)
            self.sh(["./start-all.sh"] + argv, env)
            if cfg.get("tls", {}).get("enabled"):
                self.traefik(cfg)
            return
        import make_compose
        stack, environ = self.compose_stack(argv, env, cfg)
        # the containers a start-all.sh run left have the same names
        if first:
            self.kill_all(argv, traefik)
        stack.up = True
        make_compose.write(stack, self.dirs.monitoring, environ,
                           run=lambda cmd, cwd=None, env=None, check=True: self.sh(cmd, env))

    def compose_stack(self, argv, env, cfg):
        try:
            return self.compose_config(argv, env, cfg)
        except ConfigError as e:
            raise ApplyError("make_compose.py: %s" % e)

    def compose_config(self, argv, env, cfg):
        """make_compose.py's stack for argv, and the environment it runs in;
        traefik is one of its services when TLS is on. Raises ConfigError."""
        if self.compose_build is None:
            import make_compose
            self.compose_build = make_compose.build
        environ = dict(os.environ, **env)
        tls = cfg.get("tls", {})
        if tls.get("enabled"):
            argv = argv + ["--traefik"]
            environ.update(PRIVATE_IP=tls["listen_ip"], CERT_DIR=self.args.cert_dir,
                           TRAEFIK_GENERATION=str(cfg["generation"]), THANOS_PORT=thanos_port(cfg))
        return self.compose_build(argv, environ=environ, cwd=self.dirs.monitoring), environ

    def render_prometheus_config(self, argv, env=None, cfg=None):
        if self.compose:
            # the command make_compose.py runs, with the compose service names
            stack, environ = self.compose_stack(argv, env or {}, cfg or {})
            self.sh(next(c for c in stack.commands if c[0] == "./prometheus-config.sh"), environ)
            return
        self.sh(prometheus_config_cmd(argv))

    def reload(self, argv, name):
        url = "http://%s:%s/-/reload" % (self.host(argv), self.ports(argv)[name])
        if self.http("POST", url) != 200:
            raise ApplyError("%s: reload failed" % name)

    def grafana_name(self, argv):
        out = self.run(["bash", "-c", '[ -f env.sh ] && . ./env.sh; . ./network-lib.sh; grafana_container_name "$1"',
                        "_", self.ports(argv)["grafana"] if option(argv, "--stack") else option(argv, "-g", "")],
                       cwd=self.dirs.monitoring, stdout=subprocess.PIPE,
                       universal_newlines=True)
        return out.stdout.strip()

    def grafana_datasource(self, argv, cfg):
        datasource = cfg.get("grafana", {}).get("datasource", {})
        path = os.path.join(self.stack_dir(argv, "grafana"), "provisioning", "datasources", "datasource.scylla.yml")
        if datasource.get("scylla_user") and datasource.get("scylla_password"):
            # as grafana-datasource.sh writes it: YAML single-quoted strings
            text = open(os.path.join(self.dirs.monitoring, "grafana", "datasource.psswd.scylla.yml")).read()
            for key, value in (("SCYLLA_USER", datasource["scylla_user"]), ("SCYLLA_PSSWD", datasource["scylla_password"])):
                text = text.replace("'%s'" % key, "'%s'" % value.replace("'", "''"))
        else:
            text = open(os.path.join(self.dirs.monitoring, "grafana", "datasource.scylla.yml")).read()
        write_file(path, text, 0o600)
        self.sh(["docker", "restart", self.grafana_name(argv)])

    def thanos_datasource(self, argv, delete, restart=False):
        """With delete, writes thanos.yaml as a file that deletes the Thanos
        data source, in place of the one start-all.sh wrote or of none, since
        Grafana keeps a data source whose file is gone; restarts Grafana when
        asked. Without, removes that file: start-thanos.sh writes only the
        main stack's thanos.yaml. A named stack's Grafana reads its own
        provisioning directory."""
        path = os.path.join(self.stack_dir(argv, "grafana"), "provisioning", "datasources", "thanos.yaml")
        deleting = os.path.exists(path) and open(path).read() == DELETE_THANOS_DATASOURCE
        if not delete:
            if deleting:
                os.remove(path)
            return
        if deleting:
            return
        write_file(path, DELETE_THANOS_DATASOURCE)
        if restart:
            self.sh(["docker", "restart", self.grafana_name(argv)])

    def grafana_password(self, argv, cfg):
        password = cfg.get("grafana", {}).get("admin_password")
        if password:
            self.sh(["docker", "exec", "-i", self.grafana_name(argv), "grafana", "cli", "admin",
                     "reset-admin-password", "--password-from-stdin"], input=password)

    def root(self, *args):
        self.sh(["sudo", "-n", self.args.root_helper] + list(args))

    def install_certs(self, cfg):
        if cfg.get("tls", {}).get("enabled"):
            self.root("certs", os.path.join(self.dirs.staging, "certs"), self.args.cert_dir)

    def systemd_dropins(self, old, new, previous=None):
        """Writes the drop-ins that changed; on a first apply (no old) all of
        them, and removes those of the units previous had and new does not."""
        before, after = (old or {}).get("systemd", {}), new.get("systemd", {})
        for unit in sorted(set((old or previous or {}).get("systemd", {})) - set(after)):
            self.root("dropin", unit, "--remove")
        for unit in sorted(after):
            if before.get(unit) != after[unit]:
                self.root("dropin", unit, os.path.join(self.dirs.staging, "systemd", unit + ".conf"))

    def docker_proxy(self, old, new, previous=None, stale=False):
        """Sets docker's proxy, or removes it when the section is gone;
        without the section on either side, docker is left alone, unless a
        revert left docker with another proxy (stale). The helper restarts
        docker only when the proxy changes. That restarts the watcher too
        (PartOf=docker.service), and its next pass, finding the proxy in
        place, completes the apply."""
        if not stale and "docker" not in new and "docker" not in (old or previous or {}):
            return
        staged = os.path.join(self.dirs.staging, "docker", "proxy.env")
        self.root("docker-proxy", staged if os.path.exists(staged) else "--remove")

    def traefik(self, cfg, reload_only=False):
        tls = cfg.get("tls", {})
        env = {"TRAEFIK_GENERATION": cfg["generation"], "THANOS_PORT": thanos_port(cfg)}
        if reload_only:
            self.sh(["./start-traefik.sh", "--reload"], env)
        elif tls.get("enabled"):
            env.update(PRIVATE_IP=tls["listen_ip"], CERT_DIR=self.args.cert_dir)
            self.sh(["./start-traefik.sh"], env)
        else:
            self.run(["docker", "rm", "-f", "traefik"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def health(self, argv, cfg, timeout=None):
        """Waits until every component answers its readiness endpoint."""
        pending = {name: "http://%s:%s%s" % (self.host(argv), port, path) for name, port, path in self.components(argv)}
        if cfg.get("tls", {}).get("enabled"):
            pending["traefik"] = "http://localhost:8080/ping"
        deadline = time.monotonic() + (self.args.health_timeout if timeout is None else timeout)
        while pending:
            for name, url in list(pending.items()):
                if self.http("GET", url) == 200:
                    del pending[name]
            if not pending:
                return
            if time.monotonic() >= deadline:
                raise ApplyError("%s: not ready" % ", ".join(sorted(pending)))
            self.sleep(2)

    def apply(self, old, new, argv, env, previous=None, ran_traefik=False, revert=False, proxy_stale=False,
              restart=False):
        """Applies the actions that take the stack from old to new; with no
        old, a first apply, which also removes the drop-ins previous had.
        ran_traefik: a failed apply may have left traefik running. A revert
        keeps docker's proxy as it is, so it runs without restarting docker;
        proxy_stale: docker runs a proxy a revert kept, so it is set again.
        restart: the stack restarts too, as for a container that went down."""
        actions = plan(old, new)
        if (proxy_stale and not revert) or restart:
            # as for a docker change: docker's restart stops the containers
            actions = (actions | {RESTART}) - COVERED_BY_RESTART
        traefik = ran_traefik or any(tls_on(c) for c in (old, new, previous))
        # first, so a docker restart, which restarts the watcher, interrupts
        # the apply before anything else changed
        if ("docker_proxy" in actions or proxy_stale) and not revert:
            self.docker_proxy(old, new, previous, stale=proxy_stale)
        self.move_staged()
        if "systemd_dropins" in actions:
            self.systemd_dropins(old, new, previous)
        if "install_certs" in actions:
            self.install_certs(new)
        # the flag comes from grafana.thanos_datasource or stack.extra_flags;
        # a stack restart, or grafana_datasource, restarts Grafana anyway
        if "--no-thanos-datasource" in argv:
            if {"thanos_datasource", RESTART} & actions:
                self.thanos_datasource(argv, True, restart=not ({RESTART, "grafana_datasource"} & actions))
        elif RESTART in actions:
            self.thanos_datasource(argv, False)
        if RESTART in actions:
            self.restart_stack(argv, env, new, first=old is None, traefik=traefik)
        else:
            if "render_prometheus_config" in actions:
                self.render_prometheus_config(argv, env, new)
            if "reload_prometheus" in actions:
                self.reload(argv, "prometheus")
            if "reload_alertmanager" in actions and "--no-alertmanager" not in argv:
                self.reload(argv, "alertmanager")
            if "grafana_datasource" in actions:
                self.grafana_datasource(argv, new)
            if "start_traefik" in actions and self.compose:
                # traefik is a compose service; up recreates only what changed
                self.restart_stack(argv, env, new, traefik=traefik)
            elif "start_traefik" in actions:
                self.traefik(new)
            elif "reload_traefik" in actions:
                self.traefik(new, reload_only=True)
        self.health(argv, new)
        if "grafana_password" in actions:
            self.grafana_password(argv, new)
        return actions


class ApplyError(Exception):
    """A step of an apply failed; the message is safe to report."""


def http_status(method, url):
    try:
        req = urllib.request.Request(url, method=method)
        with urllib.request.urlopen(req, timeout=5) as res:
            return res.status
    except urllib.error.HTTPError as e:
        return e.code
    except (urllib.error.URLError, OSError):
        return None


def port_listening(host, port):
    """Whether host:port takes a connection. Only a refused one counts: a
    busy service that is slow to answer is listening."""
    try:
        socket.create_connection((host, int(port)), timeout=5).close()
    except ConnectionRefusedError:
        return False
    except OSError:
        pass
    return True


def applied_path(dirs):
    return os.path.join(dirs.state, "applied.yaml")


def read_applied(dirs):
    try:
        with open(applied_path(dirs)) as f:
            return f.read()
    except FileNotFoundError:
        return None


def store_applied(dirs, text):
    os.makedirs(dirs.state, mode=0o700, exist_ok=True)
    write_private(applied_path(dirs), text)


def tls_on(cfg):
    return bool(cfg and cfg.get("tls", {}).get("enabled"))


def thanos_port(cfg):
    """The local port traefik's 10911 entry point forwards to."""
    return str(cfg.get("tls", {}).get("thanos_port", 10911))


def incomplete_path(dirs):
    """Marks applied.yaml as only partly applied: the next apply is a first
    apply. It holds "traefik" when traefik may still be running, since
    applied.yaml then no longer shows the configuration that ran it."""
    return os.path.join(dirs.state, "applied.incomplete")


def traefik_may_run(dirs):
    try:
        with open(incomplete_path(dirs)) as f:
            return f.read().strip() == "traefik"
    except FileNotFoundError:
        return False


def failed(dirs, text, cfg, error, traefik=False):
    """An apply that stopped part way: the file is stored as applied, marked
    incomplete, so the next apply runs every action. With no text (an
    internal error), applied.yaml stays as it is. traefik: a configuration
    involved ran traefik."""
    traefik = traefik or traefik_may_run(dirs)
    if text is not None:
        store_applied(dirs, text)
    os.makedirs(dirs.state, mode=0o700, exist_ok=True)
    write_private(incomplete_path(dirs), "traefik\n" if traefik else "")
    write_status(dirs, {"generation": cfg and cfg["generation"], "state": "failed", "error": error,
                        "applied_generation": cfg and cfg["generation"], "time": now()})
    print("failed: " + error, file=sys.stderr)
    return 1


def proxy_stale_path(dirs):
    """Marks docker's proxy as another than applied.yaml's: a revert kept the
    proxy of the failed apply, so the next apply sets it again."""
    return os.path.join(dirs.state, "proxy.stale")


def done(dirs, text):
    store_applied(dirs, text)
    for path in (incomplete_path(dirs), proxy_stale_path(dirs)):
        if os.path.exists(path):
            os.remove(path)


def apply_once(args, stack=None, run=subprocess.run, path=None):
    """Applies a config file once, by default the newest; returns 0 when it is
    applied or already was."""
    dirs = make_dirs(args)
    stack = stack or Stack(dirs, args, run)
    path = path or newest(dirs.config_files)
    if path is None:
        print("error: no config file exists", file=sys.stderr)
        return 1
    try:
        with open(path) as f:
            text = f.read()
    except OSError as e:
        return rejected(dirs, ConfigError("%s: %s" % (path, e.strerror)))
    applied_text = read_applied(dirs)
    incomplete = os.path.exists(incomplete_path(dirs))
    force = getattr(args, "force", False) or incomplete
    proxy_stale = os.path.exists(proxy_stale_path(dirs))
    if text == applied_text and not force and not proxy_stale:
        return 0
    try:
        new, argv, env = prepare(args, dirs, path, run, stack)
    except ConfigError as e:
        return rejected(dirs, e)
    previous = yaml.safe_load(applied_text) if applied_text else None
    old = None if force else previous
    # Only a stack restart starts a container that went down (one that
    # crashed): without it, a file whose changes start nothing fails the
    # health check and is reverted. The changes' other actions run as planned.
    restart = old is not None and container_down(dirs, stack)
    if restart:
        print("a component is down: the stack restarts", file=sys.stderr)
    ran_traefik = traefik_may_run(dirs) or tls_on(previous) or tls_on(new)
    try:
        actions = stack.apply(old, new, argv, env, previous, ran_traefik=traefik_may_run(dirs),
                              proxy_stale=proxy_stale, restart=restart)
    except ApplyError as failure:
        error = str(failure)
        if not (args.auto_revert and previous is not None and not incomplete):
            return failed(dirs, text, new, error, ran_traefik)
        # back to the previous configuration, still in applied.yaml; a first
        # apply, since the failed one may have stopped anywhere
        try:
            old_cfg, old_argv, old_env = prepare(args, dirs, applied_path(dirs), run, stack)
            stack.apply(None, old_cfg, old_argv, old_env, new, revert=True)
        except (ApplyError, ConfigError) as e:
            return failed(dirs, text, new, "%s; revert failed: %s" % (error, e.args[0]), ran_traefik)
        if new.get("docker") != old_cfg.get("docker"):
            write_private(proxy_stale_path(dirs), "")
        write_status(dirs, {"generation": new["generation"], "state": "reverted", "error": error,
                            "applied_generation": old_cfg["generation"], "time": now()})
        print("reverted: " + error, file=sys.stderr)
        return 1
    done(dirs, text)
    write_status(dirs, {"generation": new["generation"], "state": "applied", "time": now()})
    print("applied %s: %s" % (new["generation"], ", ".join(sorted(actions)) or "files only"))
    return 0


def signature(path):
    try:
        st = os.stat(path)
    except FileNotFoundError:
        return None
    return (st.st_ino, st.st_mtime_ns, st.st_size)


def container_down(dirs, stack):
    """Whether a component of the applied file's stack refuses connections on
    its port, as when its container exited (it crashed). A component that is
    starting or busy takes the connection, so it is not restarted for it.
    When the ports cannot be worked out, nothing is known to be down."""
    applied = read_applied(dirs)
    if applied is None:
        return False
    try:
        cfg = yaml.safe_load(applied)
        argv, _ = normalize(cfg, dirs)
        host = stack.host(argv)
        components = stack.components(argv)
        ports = [(host, port) for _, port, _ in components]
        loki = "loki" in [c[0] for c in components]
        ports += [(host, port) for port in stack.extra_ports(argv, loki)]
        if tls_on(cfg):
            ports.append(("localhost", "8080"))  # traefik's ping
        for _, port in ports:
            if not 0 < int(port) < 65536:
                raise ValueError("port out of range")
    except (ApplyError, ConfigError) as e:
        print("warning: cannot check the stack's ports: %s" % e.args[0], file=sys.stderr)
        return False
    # a malformed applied.yaml or port, or -h in env.sh, on which make_compose.py
    # exits; the values may be secrets
    except (Exception, SystemExit) as e:
        print("warning: cannot check the stack's ports: %s" % type(e).__name__, file=sys.stderr)
        return False
    return not all(stack.listening(host, port) for host, port in ports)


def stack_up(dirs, stack):
    """Whether the stack of the applied file answers, with a short timeout."""
    applied = read_applied(dirs)
    if applied is None:
        return True  # nothing applied yet: the apply is a first apply anyway
    try:
        cfg = yaml.safe_load(applied)
        argv, _ = normalize(cfg, dirs)
        stack.health(argv, cfg, timeout=10)
    except (ApplyError, ConfigError, yaml.YAMLError):
        return False
    return True


def run_loop(args, stack=None, run=subprocess.run):
    """Applies the newest config file on start, and then whichever one
    changes, polling them; on a fresh host it waits for the first one."""
    dirs = make_dirs(args)
    stack = stack or Stack(dirs, args, run)
    seen = {}
    first = True
    while True:
        current = {p: signature(p) for p in dirs.config_files}
        changed = [p for p, sig in current.items() if sig is not None and sig != seen.get(p)]
        seen = current
        if changed:
            # on start, and when several changed in one poll, the newest wins
            path = newest(dirs.config_files if first else changed)
            try:
                # On start the stack may be down, after a reboot or a docker
                # restart; then the file is applied whole.
                args.force = first and not stack_up(dirs, stack)
                apply_once(args, stack, run, path)
            except Exception as e:
                # one bad pass must not stop the watcher; the next change retries
                traceback.print_exc()
                failed(dirs, None, None, "internal error: %s" % type(e).__name__)
            first = False
        stack.sleep(args.poll_interval)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Configure the monitoring stack from one file.")
    sub = parser.add_subparsers(dest="command")
    commands = {
        "check": "validate and render the file, without applying it",
        "apply": "apply the file once",
        "run": "apply the file on start and whenever it changes",
    }
    for name, help_text in commands.items():
        p = sub.add_parser(name, help=help_text)
        p.add_argument("--config-file", required=True, action="append",
                       help="a configuration file; can be given more than once, the newest one is used")
        p.add_argument("--monitoring-dir", required=True, help="the monitoring stack directory")
        p.add_argument("--staging-dir", help="where the derived files go (default: <monitoring-dir>/config-build)")
        p.add_argument("--strict", action="store_true", help="reject fields the schema does not know")
        p.add_argument("--state-dir", help="where the applied file and the status go "
                                           "(default: <monitoring-dir>/config-state)")
        if name == "check":
            continue
        p.add_argument("--auto-revert", action="store_true",
                       help="re-apply the previous configuration when an apply fails")
        p.add_argument("--cert-dir", default="/etc/scylla-monitoring/certs",
                       help="where the TLS certificates are installed (default: %(default)s)")
        p.add_argument("--root-helper", help="the root helper, run with sudo -n "
                                             "(default: <monitoring-dir>/scylla-monitoring-root.sh)")
        p.add_argument("--health-timeout", type=int, default=180,
                       help="seconds to wait for the components to be ready (default: %(default)s)")
        p.add_argument("--compose", action="store_true",
                       help="run the stack with docker compose, through make_compose.py")
        if name == "apply":
            p.add_argument("--force", action="store_true",
                           help="apply the whole file, as on a first apply, even if it was applied")
        if name == "run":
            p.add_argument("--poll-interval", type=int, default=30,
                           help="seconds between checks of the file (default: %(default)s)")
    args = parser.parse_args(argv)
    if args.command is None:
        parser.error("a command is required")
    if args.command != "check" and not args.root_helper:
        args.root_helper = os.path.join(os.path.abspath(args.monitoring_dir), "scylla-monitoring-root.sh")
    return {"check": check, "apply": apply_once, "run": run_loop}[args.command](args)


if __name__ == "__main__":
    # make_compose.py imports this module by name; one module keeps one
    # ConfigError, so the errors it raises are caught here
    sys.modules.setdefault("scylla_monitoring_config", sys.modules["__main__"])
    sys.exit(main())
