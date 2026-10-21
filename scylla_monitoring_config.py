#!/usr/bin/env python3
#
# Configures the monitoring stack from one declarative file, defined by
# scylla-monitoring.schema.json (scylla-monitoring.example.yaml is an example).
#
#   scylla_monitoring_config.py check --config-file F --monitoring-dir D [--staging-dir S] [--strict]
#
# check parses and validates the file, renders the derived files into the
# staging directory, checks them with promtool and amtool, writes the status
# file and prints the start-all.sh command line the file stands for.
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
import subprocess
import sys
import tempfile

import jsonschema
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

# Options written another way: --no-loki is --log-collector none.
CANONICAL = {"--no-loki": ("--log-collector", "none"), "--no-log-collector": ("--log-collector", "none")}

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


def parse_flags(words):
    """Parses start-all.sh arguments into [(option, value or None)]."""
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
            raise ConfigError("extra_flags: an argument without an option")
        for opt in opts:
            if isinstance(opt, tuple):
                result.append(opt)
                continue
            if opt not in OPTIONS:
                raise ConfigError("extra_flags: unknown option %s" % opt)
            if OPTIONS[opt][0]:
                if i + 1 >= len(words):
                    raise ConfigError("extra_flags: %s needs a value" % opt)
                i += 1
                result.append((opt, words[i]))
            else:
                result.append((opt, None))
        i += 1
    for opt, _ in result:
        if opt in WATCHER_OWNED:
            raise ConfigError("extra_flags: %s is set by the watcher from the file" % opt)
    return result


class Dirs:
    """The watcher's directories: staging holds the rendered files, live the
    ones the containers mount."""

    def __init__(self, monitoring_dir, staging_dir=None):
        self.monitoring = monitoring_dir
        build = staging_dir or os.path.join(monitoring_dir, "config-build")
        self.staging = os.path.join(build, "staging")
        self.live = os.path.join(build, "live")
        self.state = os.path.join(monitoring_dir, "config-state")


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


def render(cfg, staging):
    """Writes every derived file into the staging directory."""
    for sub in ("targets", "rules", "alertmanager", "certs", "systemd"):
        shutil.rmtree(os.path.join(staging, sub), ignore_errors=True)
    targets = cfg["targets"]
    scylla = dump_yaml(targets["scylla"])
    files = {
        "targets/scylla_servers.yml": scylla,
        "targets/node_exporter_servers.yml": dump_yaml(targets["node_exporter"]) if "node_exporter" in targets else scylla,
        "targets/scylla_manager_agents.yml": scylla,
        # An empty list, so Prometheus has a file to read without a manager.
        "targets/scylla_manager_servers.yml": dump_yaml(targets.get("manager", [])),
    }
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


def validate(staging, versions, run=subprocess.run):
    """Checks the staged rules and Alertmanager config with the stack's own tools."""
    prometheus, alertmanager = versions
    user = "%d:%d" % (os.getuid(), os.getgid())
    checks = [
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


def make_strict(node):
    """Forbids unknown fields in every object that does not say otherwise."""
    if isinstance(node, dict):
        if "properties" in node and "additionalProperties" not in node:
            node["additionalProperties"] = False
        for value in node.values():
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
    errors = sorted(jsonschema.Draft7Validator(schema(strict)).iter_errors(cfg),
                    key=lambda e: [str(p) for p in e.absolute_path])
    if errors:
        raise ConfigError("; ".join(describe(e) for e in errors[:5]), cfg.get("generation"))
    return cfg


def write_status(dirs, status):
    """Writes the status file atomically, 0600."""
    os.makedirs(dirs.state, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=dirs.state, prefix=".status.")
    with os.fdopen(fd, "w") as f:
        json.dump(status, f)
        f.write("\n")
    os.replace(tmp, os.path.join(dirs.state, "status.json"))


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def check(args, run=subprocess.run):
    dirs = Dirs(os.path.abspath(args.monitoring_dir), args.staging_dir and os.path.abspath(args.staging_dir))
    if os.path.exists(os.path.join(dirs.monitoring, "env.sh")):
        print("warning: %s/env.sh is sourced by the start scripts and can override the file" % dirs.monitoring,
              file=sys.stderr)
    generation = None
    try:
        cfg = load(args.config_file, args.strict)
        generation = cfg["generation"]
        argv, env = normalize(cfg, dirs)
        render(cfg, dirs.staging)
        validate(dirs.staging, stack_versions(dirs.monitoring), run)
    except ConfigError as e:
        if generation is None and len(e.args) > 1 and isinstance(e.args[1], str):
            generation = e.args[1]
        write_status(dirs, {"generation": generation, "state": "rejected", "error": e.args[0], "time": now()})
        print("rejected: " + e.args[0], file=sys.stderr)
        return 1
    write_status(dirs, {"generation": generation, "state": "validated", "time": now()})
    print(" ".join(shlex.quote(w) for w in ["./start-all.sh"] + argv))
    print("environment: " + " ".join(sorted(env)))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="Configure the monitoring stack from one file.")
    sub = parser.add_subparsers(dest="command")
    p = sub.add_parser("check", help="validate and render the file, without applying it")
    p.add_argument("--config-file", required=True, help="the configuration file")
    p.add_argument("--monitoring-dir", required=True, help="the monitoring stack directory")
    p.add_argument("--staging-dir", help="where the derived files go (default: <monitoring-dir>/config-build)")
    p.add_argument("--strict", action="store_true", help="reject fields the schema does not know")
    args = parser.parse_args(argv)
    if args.command != "check":
        parser.error("a command is required")
    return check(args)


if __name__ == "__main__":
    sys.exit(main())
