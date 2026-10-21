#!/usr/bin/env python3
#
# Generates the docker compose stack: docker-compose.yml, .env and the config
# files the containers read, from start-all.sh's command line and env.sh.
#
#   make_compose.py [start-all.sh options] [--traefik] [--compose]
#
# Each container start-all.sh runs is a service with the same name, image,
# ports, mounts, environment and command. Services reach each other by name
# on the compose network, or over localhost with host networking (-l).
# --compose also runs docker compose up -d --remove-orphans. --traefik adds
# traefik, configured by start-traefik.sh --config-only from PRIVATE_IP,
# CERT_DIR and TRAEFIK_GENERATION in the environment.
#
# .env (0600) holds the secrets only: the Grafana admin password, the
# renderer token and the Datadog API key. Needs Python 3 and PyYAML.
#
# As a library: build() returns a Stack, write() writes it.

import datetime
import hashlib
import os
import re
import secrets
import shlex
import subprocess
import sys

import yaml

from scylla_monitoring_config import CANONICAL, DOCKER_ALIASES, DOCKER_NO_VALUE, ConfigError, parse_flags

HERE = os.path.dirname(os.path.abspath(__file__))

# Every variable after sourcing versions.sh and env.sh, the way the start
# scripts see them: S name value, or A name (key value)... \1 for arrays.
SHELL_VARS = r'''
. ./versions.sh
[ -f "$1" ] && . "$1"
for __v in $(compgen -v); do
	case "$__v" in __*) continue ;; esac
	case "$(declare -p "$__v" 2>/dev/null)" in
	"declare -A"* | "declare -a"*)
		declare -n __r="$__v"
		printf 'A\0%s\0' "$__v"
		for __k in "${!__r[@]}"; do printf '%s\0%s\0' "$__k" "${__r[$__k]}"; done
		printf '\1\0'
		unset -n __r
		;;
	*) printf 'S\0%s\0%s\0' "$__v" "${!__v}" ;;
	esac
done
'''

# start-all.sh options whose value scylla.txt leaves out
SECRET_FLAGS = {"-a", "--grafana-render-token", "--datadog-api-keys"}

USAGE = """usage: make_compose.py [start-all.sh options] [--traefik] [--compose]

Writes docker-compose.yml, .env and the config files for the stack that
start-all.sh would run with the same options (see ./start-all.sh -h).
  --traefik   add traefik, from PRIVATE_IP and CERT_DIR in the environment
  --compose   also run docker compose up -d --remove-orphans"""

HOST_NET = re.compile(r"(^|\s)--(net|network)(=|\s)host($|\s)")

# docker run flags and the compose keys they become. Lists are appended to,
# the others replace an earlier value.
COMPOSE_SCALARS = {
    "--memory": "mem_limit", "--memory-swap": "memswap_limit", "--memory-reservation": "mem_reservation",
    "--cpus": "cpus", "--cpu-shares": "cpu_shares", "--cpuset-cpus": "cpuset", "--shm-size": "shm_size",
    "--restart": "restart", "--user": "user", "--pid": "pid", "--hostname": "hostname",
    "--userns": "userns_mode", "--workdir": "working_dir", "--stop-timeout": "stop_grace_period",
}
COMPOSE_LISTS = {
    "--volume": "volumes", "--env": "environment", "--cap-add": "cap_add", "--cap-drop": "cap_drop",
    "--security-opt": "security_opt", "--add-host": "extra_hosts", "--dns": "dns", "--label": "labels",
    "--device": "devices", "--group-add": "group_add", "--tmpfs": "tmpfs", "--sysctl": "sysctls",
    "--publish": "ports",
}
COMPOSE_FLAGS = {"--privileged": "privileged", "--init": "init", "--read-only": "read_only"}
# What docker run needs and compose does on its own.
DOCKER_IGNORED = {"-i", "--interactive", "-d", "--detach", "-t", "--tty", "--rm"}


class Stack:
    """What make_compose.py writes: the compose definition, the .env values,
    the files to write as {path: (text, mode)}, and the helper scripts to
    run, in order."""

    def __init__(self):
        self.compose = {}
        self.env = {}
        self.files = {}
        self.commands = []
        self.dirs = []
        self.warnings = []
        self.scylla_txt = None
        self.up = False
        # host paths of config the containers read only on start, other than
        # files; their content goes into each service's config-hash label
        self.config = []


def shell_vars(cwd, environ, env_file):
    out = subprocess.run(["bash", "-c", SHELL_VARS, "_", env_file], cwd=cwd, env=environ,
                         stdout=subprocess.PIPE, check=True).stdout.decode()
    words = out.split("\0")
    result = {}
    i = 0
    while i < len(words) - 1:
        kind, name = words[i], words[i + 1]
        i += 2
        if kind == "S":
            result[name] = words[i]
            i += 1
            continue
        values = {}
        while words[i] != "\1":
            values[words[i]] = words[i + 1]
            i += 2
        result[name] = values
        i += 1
    return result


def compose_settings(text, what):
    """docker run arguments as compose keys: {key: value}, lists as lists."""
    out = {}
    tokens = shlex.split(text)
    i = 0
    while i < len(tokens):
        flag = tokens[i]
        name, eq, value = flag.partition("=")
        if not name.startswith("-"):
            raise ConfigError("%s: a value without a flag: %s" % (what, flag))
        if not eq and name not in DOCKER_NO_VALUE and name not in COMPOSE_FLAGS and name not in DOCKER_IGNORED:
            if i + 1 >= len(tokens):
                raise ConfigError("%s: %s needs a value" % (what, name))
            i += 1
            value = tokens[i]
        i += 1
        name = DOCKER_ALIASES.get(name, name)
        if name in DOCKER_IGNORED:
            continue
        if name == "--network":
            out["network"] = value
        elif name in COMPOSE_SCALARS:
            out[COMPOSE_SCALARS[name]] = value
        elif name in COMPOSE_LISTS:
            out.setdefault(COMPOSE_LISTS[name], []).append(value)
        elif name in COMPOSE_FLAGS:
            out[COMPOSE_FLAGS[name]] = True
        elif name == "--log-driver":
            out.setdefault("logging", {})["driver"] = value
        elif name == "--log-opt":
            key, _, val = value.partition("=")
            out.setdefault("logging", {}).setdefault("options", {})[key] = val
        elif name == "--ulimit":
            key, _, val = value.partition("=")
            soft, _, hard = val.partition(":")
            out.setdefault("ulimits", {})[key] = {"soft": int(soft), "hard": int(hard or soft)}
        else:
            raise ConfigError("%s: %s has no docker compose equivalent" % (what, name))
    return out


def merge(service, settings):
    for key, value in settings.items():
        if key == "network":
            continue
        if isinstance(value, list):
            service.setdefault(key, []).extend(value)
        elif isinstance(value, dict):
            target = service.setdefault(key, {})
            for k, v in value.items():
                if isinstance(v, dict):
                    target.setdefault(k, {}).update(v)
                else:
                    target[k] = v
        else:
            service[key] = value


def escape(node):
    """Compose interpolates $; every literal value keeps its $ as $$."""
    if isinstance(node, str):
        return node.replace("$", "$$")
    if isinstance(node, list):
        return [escape(v) for v in node]
    if isinstance(node, dict):
        return {k: escape(v) for k, v in node.items()}
    return node


def env_value(value):
    if "\n" in value:
        raise ConfigError(".env: a value cannot hold a newline")
    return '"%s"' % value.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$")


def read_env_file(path):
    """The values in an existing .env, as env_value() wrote them."""
    values = {}
    try:
        lines = open(path).read().splitlines()
    except OSError:
        return values
    for line in lines:
        key, eq, value = line.partition("=")
        if not eq:
            continue
        if len(value) >= 2 and value[0] == value[-1] == '"':
            value = re.sub(r'\\(.)', r'\1', value[1:-1])
        values[key] = value
    return values


def read_scylla_txt(path):
    values = {}
    if os.path.isfile(path):
        for line in open(path).read().splitlines():
            key, eq, value = line.partition("=")
            if eq:
                values[key] = value.strip('"')
    return values


class Paths:
    """Paths as compose sees them: ./ relative inside the stack directory,
    absolute outside it, like start-all.sh's readlink -f."""

    def __init__(self, cwd):
        self.cwd = cwd

    def abs(self, path):
        return os.path.realpath(os.path.join(self.cwd, os.path.expanduser(path)))

    def __call__(self, path, slash=False):
        full = self.abs(path)
        rel = os.path.relpath(full, self.cwd)
        out = full if rel.startswith("..") else ("." if rel == "." else "./" + rel)
        return out + "/" if slash and not out.endswith("/") else out


def split_container(value, opt):
    container, comma, rest = value.partition(",")
    if not comma or not container or not rest:
        raise ConfigError("%s: the value is <container>,<setting>" % opt)
    return container, rest.replace("#", " ")


def listed(v, name):
    """An env.sh variable set as a bash array or as one value, as a list."""
    value = v.get(name, "")
    if isinstance(value, dict):
        return [value[k] for k in sorted(value, key=int)]
    return [value] if value else []


def options(argv, v, paths):
    """start-all.sh's option handling, over the variables from env.sh."""
    o = {
        "versions": v.get("VERSIONS", ""), "manager_version": v.get("MANAGER_VERSION", ""),
        "data_dir": v.get("DATA_DIR", ""), "grafana_dir": "", "bind": v.get("BIND_ADDRESS", ""),
        "am_rules": "", "prom_rules": v.get("PROMETHEUS_RULES", ""),
        "grafana_port": v.get("GRAFANA_PORT", ""), "am_port": v.get("ALERTMANAGER_PORT", ""),
        "prom_port": v.get("PROMETHEUS_PORT", ""), "loki_port": v.get("LOKI_PORT", ""),
        "promtail_port": "", "promtail_bin_port": "",
        "alloy_port": v.get("ALLOY_PORT", ""), "alloy_syslog_port": v.get("ALLOY_SYSLOG_PORT", ""),
        "prom_targets": shlex.split(v.get("PROMETHEUS_TARGETS", "")), "anonymous_role": v.get("ANONYMOUS_ROLE", "Admin"),
        "scylla_files": listed(v, "SCYLLA_TARGET_FILES"), "node_file": "", "manager_agents": "",
        "manager_files": listed(v, "SCYLLA_MANGER_TARGET_FILES"),
        "consul": "", "ldap": "", "admin_password": v.get("GRAFANA_ADMIN_PASSWORD", ""),
        "dashboards": [], "grafana_env": [], "am_commands": [], "prom_args": [],
        "solution": "", "am_dir": "", "loki_dir": "", "log_collector": v.get("LOG_COLLECTOR", "") or "alloy",
        "run_loki": v.get("RUN_LOKI", "1") == "1", "renderer": (v.get("RUN_RENDERER", "-E") or "-E") != "",
        "thanos_sc": v.get("RUN_THANOS_SC", "0") == "1", "thanos": v.get("RUN_THANOS", "0") == "1",
        "local_thanos": v.get("RUN_LOCAL_THANOS", "") == "1", "no_thanos_datasource": bool(v.get("NO_THANOS_DATASOURCE")),
        "auto_restart": False, "victoria_metrics": False, "auth": v.get("GRAFANA_AUTH", "false"),
        "anonymous": v.get("GRAFANA_AUTH_ANONYMOUS", "true"), "embedding": None,
        "support_dashboard": bool(v.get("SUPPORT_DASHBOARD")), "clear": False,
        "native_histogram": False, "alternator": False, "skip_alertmanager": v.get("SKIP_ALERTMANAGER") == "1",
        "stack": "", "scrap": "", "cluster_label": None, "vector_search": "", "target_directory": "",
        "servers": "", "archive": False, "datadog_key": "", "datadog_hostname": "",
        "render_token": v.get("GRAFANA_RENDERER_TOKEN", ""),
        "render_token_file": v.get("GRAFANA_RENDERER_TOKEN_FILE", "") or v.get("GRAFANA_RENDERER_TOKEN_TO_FILE", ""),
        "limits": {k: val for k, val in v.get("DOCKER_LIMITS", {}).items()},
        "params": {k: val for k, val in v.get("DOCKER_PARAMS", {}).items()},
        "docker_param": v.get("DOCKER_PARAM", ""), "docker_param_from_file": bool(v.get("DOCKER_PARAM")),
        "traefik": False, "up": False, "enterprise": argv[:1] == ["-e"],
    }
    # env.sh can set start-all.sh's option variables, which hold the option
    # with its value ("-L <address>"); the command line comes after them
    words = []
    for name in ("CONSUL_ADDRESS", "LDAP_FILE", "SPECIFIC_SOLUTION", "ALERT_MANAGER_DIR", "LOKI_DIR",
                 "GRAFNA_ANONYMOUS_ROLE"):
        words += shlex.split(v.get(name, ""))
    words += [{"-p": "-m"}.get(w, w) for w in shlex.split(v.get("ALERTMANAGER_PORT_CMD", ""))]
    loki_flags = {"-p": "--loki-port", "-t": "--promtail-port", "-T": "--promtail-binary-port"}
    words += [loki_flags.get(w, w) for w in shlex.split(v.get("LOKI_PORT_CMD", ""))]
    for word in argv:
        if word == "--traefik":
            o["traefik"] = True
        elif word == "--compose":
            o["up"] = True
        else:
            words.append(word)
    for opt, value in parse_flags(words, owned=(), what="make_compose.py"):
        opt, value = CANONICAL.get(opt, (opt, value))
        if opt in ("-h", "--help"):
            print(USAGE)
            sys.exit(0)
        elif opt == "-v":
            o["versions"] = value
        elif opt == "-M":
            o["manager_version"] = value
        elif opt == "-d":
            o["data_dir"] = value
        elif opt == "-G":
            o["grafana_dir"] = value
        elif opt == "-A":
            o["bind"] = value + ":"
        elif opt == "-r":
            o["am_rules"] = value
        elif opt == "-R":
            o["prom_rules"] = paths(value) + (":/etc/prometheus/prom_rules/" if os.path.isdir(paths.abs(value))
                                               else ":/etc/prometheus/prometheus.rules.yml")
        elif opt == "-g":
            o["grafana_port"] = value
        elif opt == "-m":
            o["am_port"] = value
        elif opt == "-p":
            o["prom_port"] = value
        elif opt == "-T":
            o["prom_targets"] += ["-T", value]
        elif opt == "-Q":
            o["anonymous_role"] = value
        elif opt == "-s":
            o["scylla_files"] = [value]
        elif opt == "-n":
            o["node_file"] = value
        elif opt == "-l":
            if not HOST_NET.search(o["docker_param"]):
                o["docker_param"] += " --net=host"
        elif opt == "-L":
            o["consul"] = value
        elif opt == "-P":
            o["ldap"] = value
        elif opt == "-a":
            o["admin_password"] = value
        elif opt == "-j":
            o["dashboards"].append(value)
        elif opt == "-c":
            o["grafana_env"].append(value)
        elif opt == "-C":
            o["am_commands"].append(value)
        elif opt == "-D":
            if o["docker_param_from_file"]:
                o["docker_param"] = ""
                o["docker_param_from_file"] = False
            o["docker_param"] += " " + value
        elif opt == "-b":
            o["prom_args"].append(value)
        elif opt == "-N":
            o["manager_files"] = [value]
        elif opt == "-S":
            o["solution"] = value
        elif opt == "-E":
            o["renderer"] = True
        elif opt == "-f":
            o["am_dir"] = value
        elif opt == "-k":
            o["loki_dir"] = value
        elif opt == "--log-collector":
            o["log_collector"] = value
        elif opt == "--loki-port":
            o["loki_port"] = value
        elif opt == "--promtail-port":
            o["promtail_port"] = value
        elif opt == "--promtail-binary-port":
            o["promtail_bin_port"] = value
        elif opt == "--alloy-port":
            o["alloy_port"] = value
        elif opt == "--alloy-syslog-port":
            o["alloy_syslog_port"] = value
        elif opt == "--limit":
            container, rest = split_container(value, opt)
            o["limits"][container] = o["limits"].get(container, "") + " " + rest
        elif opt == "--volume":
            container, rest = split_container(value, opt)
            src, _, dst = rest.partition(":")
            o["limits"][container] = o["limits"].get(container, "") + " -v " + shlex.quote(paths(src) + ":" + dst)
        elif opt == "--param":
            container, rest = split_container(value, opt)
            o["params"][container] = o["params"].get(container, "") + " " + rest
        elif opt == "--evaluation-interval":
            o["prom_targets"] += ["-E", value]
        elif opt == "--manager-agents":
            o["manager_agents"] = value
        elif opt == "--datadog-api-keys":
            o["datadog_key"] = value
        elif opt == "--datadog-hostname":
            o["datadog_hostname"] = value
        elif opt == "--stack":
            o["stack"] = value
        elif opt == "--scrap":
            o["scrap"] = value
        elif opt in ("--vector-search", "--vector-store"):
            o["vector_search"] = value
        elif opt == "--grafana-render-token":
            o["render_token"] = value
        elif opt == "--grafana-render-token-to-file":
            o["render_token_file"] = value
        elif opt == "--target-directory":
            o["target_directory"] = value
        elif opt == "--servers":
            o["servers"] = value
        elif opt == "--archive":
            o["archive"] = True
            o["data_dir"] = value
            o["prom_args"].append("--storage.tsdb.retention.time=100y")
        elif opt == "--cluster-label":
            o["cluster_label"] = value
        elif opt == "--no-alertmanager":
            o["skip_alertmanager"] = True
        elif opt == "--no-renderer":
            o["renderer"] = False
        elif opt == "--thanos-sc":
            o["thanos_sc"] = True
        elif opt == "--thanos":
            o["thanos"] = True
        elif opt == "--local-thanos":
            o["local_thanos"] = True
        elif opt == "--no-thanos-datasource":
            o["no_thanos_datasource"] = True
        elif opt == "--auto-restart":
            o["auto_restart"] = True
        elif opt == "--victoria-metrics":
            o["victoria_metrics"] = True
        elif opt == "--auth":
            o["auth"] = "true"
        elif opt == "--disable-anonymous":
            o["anonymous"] = "false"
        elif opt == "--allow-embedding":
            o["embedding"] = True
        elif opt == "--disable-embedding":
            o["embedding"] = False
        elif opt == "--support-dashboard":
            o["support_dashboard"] = True
        elif opt == "--clear":
            o["clear"] = True
        elif opt in ("--native-histogram", "--enable-protobuf"):
            o["native_histogram"] = True
        elif opt == "--alternator":
            o["alternator"] = True
        elif opt in ("--no-cas-cdc", "--no-cas", "--no-cdc"):
            o["prom_targets"].append(opt)
        elif opt in ("-e", "--verbose", "--quick-startup"):
            pass  # -e only matters for -v latest; nothing waits to be quick about
    if o["auto_restart"]:
        o["docker_param"] += " --restart=unless-stopped"
    return o


def podman():
    """Whether docker is podman, as start-all.sh checks it."""
    try:
        out = subprocess.run(["docker", "--help"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout
    except OSError:
        return False
    return b"podman" in out


def build(argv, environ=None, cwd=None, env_file=None, ids=None):
    """The Stack the start-all.sh options in argv stand for."""
    cwd = os.path.abspath(cwd or os.getcwd())
    environ = dict(os.environ if environ is None else environ)
    v = shell_vars(cwd, environ, env_file or os.path.join(cwd, "env.sh"))
    # as start-grafana.sh takes it: an exported password wins over env.sh,
    # which may set it in the start-all.sh form, "-a <password>"
    v["GRAFANA_ADMIN_PASSWORD"] = environ.get("GRAFANA_ADMIN_PASSWORD") or \
        re.sub(r"^-a ", "", v.get("GRAFANA_ADMIN_PASSWORD", ""))
    paths = Paths(cwd)
    stack = Stack()
    o = options(argv, v, paths)
    uid, gid = ids or (os.getuid(), os.getgid())
    # as start-all.sh and start-grafana.sh run them on podman
    userns = "keep-id" if podman() else None
    user = "0:0" if uid == 0 else "%d:%d" % (uid, gid)

    current = v.get("CURRENT_VERSION") or "master"
    if os.path.isfile(os.path.join(cwd, "CURRENT_VERSION.sh")):
        current = open(os.path.join(cwd, "CURRENT_VERSION.sh")).read().strip()
    default_version = v.get("DEFAULT_VERSION", {})
    branch = v.get("BRANCH_VERSION") or current
    if current not in default_version:
        branch = ".".join(current.split(".")[:2])
    if not o["manager_version"]:
        o["manager_version"] = v.get("MANAGER_DEFAULT_VERSION", {}).get(branch, "")
    if not o["versions"]:
        o["versions"] = default_version.get(branch, "")
    if o["archive"]:
        txt = read_scylla_txt(os.path.join(paths.abs(o["data_dir"]), "scylla.txt"))
        o["versions"] = txt.get("VERSIONS", o["versions"])
        o["manager_version"] = txt.get("MANAGER_VERSION", o["manager_version"])
        o["alternator"] = o["alternator"] or txt.get("RUN_ALTERNATOR") == "1"
    if o["versions"] == "latest":
        if branch in ("", "master"):
            raise ConfigError("-v latest is not supported on the master branch, use a specific version")
        o["versions"] = (v.get("DEFAULT_ENTERPRISE_VERSION", {}) if o["enterprise"] else default_version).get(branch, "")
    elif o["versions"] == "all":
        o["versions"] = v.get("ALL", "")
    if not o["versions"]:
        raise ConfigError("Scylla-version was not found, add -v with a specific version (i.e. -v 2021.1)")
    if o["log_collector"] not in ("alloy", "promtail", "none"):
        raise ConfigError("Unknown --log-collector '%s', use alloy, promtail or none" % o["log_collector"])
    run_loki = o["run_loki"] and o["log_collector"] != "none"
    renderer = o["renderer"]
    skip_am = o["skip_alertmanager"]
    consul = o["consul"]
    if o["archive"]:
        run_loki, skip_am, renderer, consul = False, True, False, "127.0.0.1:0"
        if not os.path.isdir(paths.abs(o["data_dir"])):
            raise ConfigError("The given data directory %s does not exist" % o["data_dir"])
    stack_id = o["stack"]
    stack_dir = "/stack/" + stack_id if stack_id else ""
    if stack_id:
        if stack_id not in v.get("STACK_PROMETHEUS", {}):
            raise ConfigError("--stack %s: use 1 to 4" % stack_id)
        run_loki, renderer = False, False
        o["prom_port"] = v["STACK_PROMETHEUS"][stack_id]
        o["grafana_port"] = v["STACK_GRAFANA"][stack_id]
        o["am_port"] = v["STACK_ALERTMANAGER"][stack_id]

    docker = compose_settings(o["docker_param"], "-D")
    network = docker.get("network", "")
    host = network == "host"
    if host and ((o["am_port"] and o["am_port"] != "9093") or o["grafana_port"] or o["prom_port"]):
        raise ConfigError("Port mapping is not supported with host network, remove the -l flag from the command line")
    if network and not host and (network in ("bridge", "none", "default") or network.startswith("container:")):
        raise ConfigError("-D --network %s: compose mode needs a network that resolves names, or host" % network)
    if o["servers"] and (o["target_directory"] or consul):
        raise ConfigError("--servers cannot be used with --target-directory or with -L (Scylla Manager based targets)")

    bind = o["bind"]
    local = "127.0.0.1" if host else None

    def ports(*pairs):
        return [] if host else ["%s%s:%s" % (bind, h, c) for h, c in pairs]

    def address(name, port):
        return "%s:%s" % (local or name, port)

    services = {}

    def service(name, component, image, params_at=None, **fields):
        """A service; --param values go at params_at in the command, at its
        end by default, where the start scripts put them."""
        svc = {"container_name": name, "image": image}
        svc.update({k: val for k, val in fields.items() if val not in (None, [], "")})
        merge(svc, docker)
        limits = compose_settings(o["limits"].get(component, ""), "--limit %s" % component)
        if "network" in limits:
            # the services find each other by name on one network
            raise ConfigError("--limit %s: --network can only be set for every container, with -D" % component)
        merge(svc, limits)
        params = shlex.split(o["params"].get(component, ""))
        if params:
            command = svc.get("command", [])
            at = len(command) if params_at is None else params_at
            svc["command"] = command[:at] + params + command[at:]
        if host:
            svc["network_mode"] = "host"
        services[name] = svc
        return svc

    # Alertmanager
    am_port = o["am_port"] or "9093"
    am_name = "aalert" if am_port == "9093" else "aalert-" + am_port
    if skip_am:
        am_address = "127.0.0.1:9093"
    else:
        am_address = address(am_name, 9093)
        rules = paths.abs(o["am_rules"] or "prometheus/rule_config.yml")
        stack.config.append(rules)
        if os.path.isdir(rules):
            mount, config = paths(rules, slash=True) + ":/etc/alertmanager/conf/:z", "/etc/alertmanager/conf/config.yml"
        else:
            mount, config = paths(rules) + ":/etc/alertmanager/config.yml:z", "/etc/alertmanager/config.yml"
        volumes = [mount]
        am_user = None
        if o["am_dir"]:
            volumes.append(paths(o["am_dir"]) + ":/alertmanager/data:z")
            am_user = user
            stack.dirs.append(paths.abs(o["am_dir"]))
        command = [w for c in o["am_commands"] for w in shlex.split(c)]
        service(am_name, "alertmanager", "docker.io/prom/alertmanager:" + v["ALERT_MANAGER_VERSION"],
                ports=ports((am_port, 9093)), volumes=volumes, user=am_user,
                command=command + ["--log.level=debug", "--config.file=" + config])

    # Loki and its log collector
    loki_flag = ""
    if run_loki:
        loki_name = "loki-" + o["loki_port"] if o["loki_port"] else "loki"
        loki_port = o["loki_port"] or "3100"
        loki_address = address(loki_name, 3100)
        loki_flag = loki_address
        conf_dir = v.get("LOKI_CONF_DIR") or "loki/conf"
        template = open(os.path.join(cwd, conf_dir, "loki-config.template.yaml")).read()
        stack.files[os.path.join(conf_dir, "loki-config.yaml")] = (template.replace("ALERTMANAGER", am_address), 0o644)
        volumes = [paths(v.get("LOKI_RULE_DIR") or "loki/rules/scylla") + ":/etc/loki/rules/fake:z",
                   paths(conf_dir) + ":/mnt/config:z"]
        loki_user = None
        if o["loki_dir"]:
            volumes.append(paths(o["loki_dir"]) + ":/tmp/loki:z")
            loki_user = user
            stack.dirs.append(paths.abs(o["loki_dir"]))
        service(loki_name, "loki", "docker.io/grafana/loki:" + v["LOKI_VERSION"], ports=ports((loki_port, 3100)),
                volumes=volumes, user=loki_user,
                command=["--ingester.wal-enabled=false", "--config.file=/mnt/config/loki-config.yaml"])
        if o["log_collector"] == "alloy":
            alloy_port = o["alloy_port"] or "12345"
            syslog = o["alloy_syslog_port"] or "1514"
            name = "alloy-" + o["alloy_port"] if o["alloy_port"] else "alloy"
            template = open(os.path.join(cwd, "loki/alloy/config.template.alloy")).read()
            text = template.replace("LOKI_IP", loki_address).replace("0.0.0.0:1514", "0.0.0.0:" + syslog)
            stack.files["loki/alloy/build/config.alloy"] = (text, 0o644)
            service(name, "alloy", "docker.io/grafana/alloy:" + v["ALLOY_VERSION"],
                    ports=ports((alloy_port, alloy_port), (syslog, syslog)),
                    volumes=["./loki/alloy/build:/etc/alloy/conf:ro,z"],
                    command=["run", "--server.http.listen-addr=0.0.0.0:" + alloy_port,
                             "--storage.path=/var/lib/alloy/data", "/etc/alloy/conf/config.alloy"])
        else:
            pt_port = o["promtail_port"] or "9080"
            name = "promtail-" + o["promtail_port"] if o["promtail_port"] else "promtail"
            template = open(os.path.join(cwd, "loki/promtail/promtail_config.template.yml")).read()
            stack.files["loki/promtail/build/config.yml"] = (template.replace("LOKI_IP", loki_address), 0o644)
            service(name, "promtail", "docker.io/grafana/promtail:" + v["PROMTAIL_VERSION"],
                    ports=ports((pt_port, 9080), (o["promtail_bin_port"] or "1514", 1514)),
                    volumes=["./loki/promtail/build:/etc/promtail/conf:ro,z"],
                    command=["--config.file=/etc/promtail/conf/config.yml"])

    # Prometheus targets
    target = "/etc/scylla.d/prometheus/targets/"
    target_mounts = []
    prom_targets = list(o["prom_targets"])
    if o["servers"]:
        path = "prometheus/build%s/scylla_servers.yml" % stack_dir
        lines = ["# Generated by make_compose.py --servers %s, do not edit" % o["servers"], "- targets:"]
        lines += ["  - " + s for s in o["servers"].split(",")]
        stack.files[path] = ("\n".join(lines) + "\n", 0o644)
        o["scylla_files"] = [path]
    if not o["target_directory"] and not consul:
        candidates = o["scylla_files"] or ["prometheus/scylla_servers.yml", "scylla_servers.yml"]
        found = [f for f in candidates if os.path.isfile(paths.abs(f)) or f in stack.files]
        if not found:
            raise ConfigError("Scylla target file '%s' does not exist, you can use "
                              "prometheus/scylla_servers.example.yml as an example." % candidates[0])
        scylla = found[0]
        node = o["node_file"]
        if not node:
            prom_targets.append("--no-node-exporter-file")
            node = scylla
        agents = o["manager_agents"]
        if not agents:
            prom_targets.append("--no-manager-agent-file")
            agents = scylla
        if not os.path.isfile(paths.abs(node)) and node not in stack.files:
            raise ConfigError("Node target file '%s' does not exist" % node)
        managers = o["manager_files"] or ["prometheus/scylla_manager_servers.yml", "scylla_manager_servers.yml",
                                          "prometheus/scylla_manager_servers.example.yml"]
        found = [f for f in managers if os.path.isfile(paths.abs(f))]
        if not found:
            raise ConfigError("Scylla-Manager target file '%s' does not exist, you can use "
                              "prometheus/scylla_manager_servers.example.yml as an example." % managers[0])
        target_mounts = [paths(scylla) + ":" + target + "scylla_servers.yml",
                         paths(found[0]) + ":" + target + "scylla_manager_servers.yml",
                         paths(node) + ":" + target + "node_exporter_servers.yml"]
        if o["vector_search"]:
            target_mounts.append(paths(o["vector_search"]) + ":" + target + "vector_search_servers.yml")
        target_mounts.append(paths(agents) + ":" + target + "scylla_manager_agents.yml")
    elif o["vector_search"] and o["vector_search"] != "vector_search_servers.yml":
        stack.warnings.append("With a target directory the vector-search file is called vector_search_servers.yml "
                              "and should be inside the target directory")
    if o["target_directory"]:
        target_mounts = [paths(o["target_directory"], slash=True) + ":" + target + ":z"]
        for f in ("scylla_servers.yml", "node_exporter_servers.yml", "scylla_manager_agents.yml",
                  "scylla_manager_servers.yml"):
            if not os.path.isfile(os.path.join(paths.abs(o["target_directory"]), f)):
                stack.warnings.append("Using %s for Prometheus target directory, %s is missing"
                                      % (o["target_directory"], f))

    # Prometheus or VictoriaMetrics
    prom_port = o["prom_port"] or "9090"
    prom_name = "aprom-" + o["prom_port"] if o["prom_port"] else "aprom"
    db_address = address(prom_name, 9090)
    prom_args = []
    for arg in o["prom_args"]:
        for word in shlex.split(arg):
            if not word.startswith("--"):
                stack.warnings.append("Using single hyphen is deprecated, use -%s instead" % word)
                word = "-" + word
            prom_args.append(word)
    data_volumes = []
    if o["data_dir"]:
        stack.dirs.append(paths.abs(o["data_dir"]))
    else:
        stack.warnings.append("Without an external Prometheus directory, Prometheus data will be deleted on "
                              "shutdown, use the -d command line flag for data persistence.")
    stack.config += [paths.abs("prometheus/build" + stack_dir),
                     paths.abs((o["prom_rules"] or "prometheus/prom_rules/:").split(":")[0])]
    if o["victoria_metrics"]:
        if o["data_dir"]:
            data_volumes = [paths(o["data_dir"]) + ":/victoria-metrics-data"]
        target_mounts = [m for m in target_mounts if not m.endswith("vector_search_servers.yml")]
        service(prom_name, "prometheus", "victoriametrics/victoria-metrics:" + v["VICTORIA_METRICS_VERSION"],
                ports=ports((prom_port, 9090)),
                volumes=data_volumes + ["./prometheus/build%s/:/etc/prometheus/config/:z" % stack_dir] + target_mounts,
                command=prom_args + ["-promscrape.config=/etc/prometheus/config/prometheus.yml",
                                     "-promscrape.config.strictParse=false", "-httpListenAddr=:9090"])
        service("vmalert", "vmalert", "victoriametrics/vmalert:" + v["VICTORIA_METRICS_VERSION"],
                volumes=[(o["prom_rules"] or "./prometheus/prom_rules/:/etc/prometheus/prom_rules/") + ":z"],
                command=["-rule=/etc/prometheus/prom_rules/*yml", "-datasource.url=http://" + db_address,
                         "-notifier.url=http://" + am_address, "-remoteWrite.url=http://" + db_address,
                         "-remoteRead.url=http://" + db_address])
    else:
        if o["data_dir"]:
            data_volumes = [paths(o["data_dir"]) + ":/prometheus/data:Z"]
        service(prom_name, "prometheus", "docker.io/prom/prometheus:" + v["PROMETHEUS_VERSION"],
                ports=ports((prom_port, 9090)), user=user if o["data_dir"] else None, userns_mode=userns,
                volumes=data_volumes + ["./prometheus/build%s/:/etc/prometheus/config/:z" % stack_dir,
                                        (o["prom_rules"] or "./prometheus/prom_rules/:/etc/prometheus/prom_rules/")
                                        + ":z"] + target_mounts,
                command=["--web.enable-lifecycle", "--enable-feature=promql-experimental-functions",
                         "--config.file=/etc/prometheus/config/prometheus.yml"] + prom_args)

    grafana_port = o["grafana_port"] or "3000"
    grafana_name = v.get("GRAFANA_NAME") or ("agraf-" + o["grafana_port"] if o["grafana_port"] else "agraf")
    cmd = ["./prometheus-config.sh", "-m", am_address]
    if stack_id:
        cmd += ["-s", stack_id]
    cmd += ["-G", address(grafana_name, 3000) if not host else "localhost:3000"]
    if o["native_histogram"]:
        cmd.append("--native-histogram")
    if o["scrap"]:
        cmd += ["--scrap", o["scrap"]]
    if consul:
        cmd += ["-L", consul]
    cmd += prom_targets
    if o["vector_search"]:
        cmd.append("--vector-search")
    if o["cluster_label"] is not None:
        cmd += ["--cluster-label", o["cluster_label"]]
    stack.commands.append(cmd)
    if o["data_dir"] and not o["archive"]:
        stack.scylla_txt = (os.path.join(paths.abs(o["data_dir"]), "scylla.txt"),
                            ["LAST_COMMAND_LINE=" + shlex.quote(" ".join(
                                "***" if prev in SECRET_FLAGS else w for prev, w in zip([None] + argv, argv))),
                             'VERSIONS="%s"' % o["versions"],
                             'MANAGER_VERSION="%s"' % o["manager_version"], 'MONITORING_VERSION="%s"' % current,
                             'PROMETHEUS_VERSION="%s"' % v["PROMETHEUS_VERSION"]]
                            + (["RUN_ALTERNATOR=1"] if o["alternator"] else []))

    # Thanos sidecar and query
    sidecar = o["thanos_sc"] and o["data_dir"]
    if o["thanos_sc"] and not o["data_dir"]:
        stack.warnings.append("You must use external prometheus directory to use the thanos side cart")
    if sidecar:
        service("sidecar1", "sidecar", "docker.io/thanosio/thanos:" + v["THANOS_VERSION"], params_at=2,
                user=None if uid == 0 else user, ports=ports((10911, 10911), (10912, 10912)),
                volumes=[paths(o["data_dir"]) + ":/data/prom1:z"],
                command=["sidecar", "--debug.name=1", "--grpc-address=0.0.0.0:10911", "--grpc-grace-period=1s",
                         "--http-address=0.0.0.0:10912", "--http-grace-period=1s",
                         "--prometheus.url=http://" + db_address, "--tsdb.path=/data/prom1"])
    endpoints = []
    if o["thanos"] and o["thanos_sc"]:
        endpoints = [address("sidecar1", 10911)]
    elif not o["thanos"] and o["local_thanos"]:
        endpoints = [address("sidecar1", 10911)]
    if o["thanos"] or o["local_thanos"]:
        service("thanos", "thanos", "docker.io/thanosio/thanos:" + v["THANOS_VERSION"],
                ports=ports((10903, 10903), (10904, 10904)),
                command=["query", "--debug.name=query0", "--grpc-address=0.0.0.0:10903", "--grpc-grace-period=1s",
                         "--http-address=0.0.0.0:10904", "--http-grace-period=1s", "--query.promql-engine=thanos",
                         "--query.replica-label=cluster"])
        services["thanos"]["command"] += ["--endpoint=" + e for e in endpoints]
        if not o["no_thanos_datasource"]:
            stack.files["grafana/provisioning/datasources/thanos.yaml"] = (
                "# config file version\napiVersion: 1\ndatasources:\n- name: thanos\n  type: prometheus\n"
                "  url: http://%s\n  access: proxy\n  basicAuth: false\n\n" % address("thanos", 10904), 0o644)

    # Datadog
    if o["datadog_key"] or o["datadog_hostname"]:
        if not o["datadog_key"]:
            stack.warnings.append("Datadog API keys are not present, the Datadog agent does not run")
        else:
            conf = v.get("CONF_DIR") or "datadog_conf"
            if not os.path.isfile(os.path.join(paths.abs(conf), "datadog.yaml")):
                stack.files[os.path.join(conf, "datadog.yaml")] = (
                    "# datadog.yaml\nprocess_config:\n  enabled: true\n  scrub_args: true\nlogs_enabled: true\n"
                    "confd_path: /conf.d\nlog_level: INFO\nhostname: %s\n"
                    % (o["datadog_hostname"] or v.get("HOSTNAME", "")), 0o644)
            text = open(os.path.join(cwd, "docs/source/procedures/datadog/conf.yaml")).read()
            stack.files[os.path.join(conf, "conf.d/prometheus.d/conf.yaml")] = (text.replace("IP:9090", db_address),
                                                                                 0o644)
            stack.env["DD_API_KEY"] = o["datadog_key"]
            svc = service(v.get("DATADOG_NAME") or "datadog-agent", "datadog", "gcr.io/datadoghq/agent:latest",
                          pid="host", volumes=[paths(conf) + "/datadog.yaml:/etc/datadog-agent/datadog.yaml",
                                               paths(conf) + "/conf.d/:/conf.d"],
                          environment=["DD_CONTAINER_INCLUDE="])
            svc["secrets_env"] = ["DD_API_KEY=${DD_API_KEY}"]

    # Grafana and its renderer
    support = o["support_dashboard"]
    auth = "true" if support or o["ldap"] else o["auth"]
    anonymous = "false" if o["ldap"] else o["anonymous"]
    first = o["versions"].split(",")[0]
    home = v.get("HOME_DASHBOARD") or "/var/lib/grafana/dashboards/ver_%s/%s.%s.json" % (
        first, "alternator" if o["alternator"] else "scylla-overview", first)
    embedding = o["embedding"]
    allow = v.get("GRAFANA_ALLOW_EMBEDDING") or v.get("GF_SECURITY_ALLOW_EMBEDDING") or "false"
    secure = v.get("GRAFANA_COOKIE_SECURE") or v.get("GF_SECURITY_COOKIE_SECURE")
    samesite = v.get("GRAFANA_COOKIE_SAMESITE") or v.get("GF_SECURITY_COOKIE_SAMESITE")
    if embedding is not None:
        allow, secure, samesite = ("true", "true", "none") if embedding else ("false", "false", "lax")
    if allow == "true":
        secure, samesite = secure or "true", samesite or "none"
    else:
        secure, samesite = secure or "false", samesite or "lax"
    env = ["GF_AUTH_BASIC_ENABLED=" + auth, "GF_AUTH_ANONYMOUS_ENABLED=" + anonymous,
           "GF_AUTH_ANONYMOUS_ORG_ROLE=" + o["anonymous_role"], "GF_PANELS_DISABLE_SANITIZE_HTML=true",
           "GF_RENDERING_DEFAULT_WIDTH=1920", "GF_RENDERING_DEFAULT_HEIGHT=1080",
           "GF_PATHS_PROVISIONING=/var/lib/grafana/provisioning",
           "GF_ANALYTICS_GOOGLE_ANALYTICS_UA_ID=UA-43975320-9",
           "GF_ANALYTICS_REPORTING_ENABLED=" + (v.get("ANALYTICS_REPORTING_ENABLED") or "false"),
           "GF_ANALYTICS_CHECK_FOR_UPDATES=" + (v.get("ANALYTICS_CHECK_FOR_UPDATES") or "false"),
           "GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES=" + (v.get("ANALYTICS_CHECK_FOR_PLUGIN_UPDATES") or "false"),
           "GF_SECURITY_ANGULAR_SUPPORT_ENABLED=" + (v.get("SECURITY_ANGULAR_SUPPORT_ENABLED") or "false"),
           "GF_DATABASE_WAL=true", "GF_AUTH_ANONYMOUS_ORG_NAME=Main Org.",
           "GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=scylladb-scylla-datasource",
           "GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=" + home,
           "GF_PROVISIONING_PERMITTED_PROVISIONED_PATHS=/var/lib/grafana/dashboards/",
           "GF_SERVER_ENABLE_GZIP=" + (v.get("SERVER_ENABLE_GZIP") or "true"),
           "GF_SECURITY_ALLOW_EMBEDDING=" + allow, "GF_SECURITY_COOKIE_SECURE=" + secure,
           "GF_SECURITY_COOKIE_SAMESITE=" + samesite]
    extra = list(o["grafana_env"])
    if o["ldap"]:
        extra += ["GF_AUTH_LDAP_ENABLED=true", "GF_AUTH_LDAP_CONFIG_FILE=/etc/grafana/ldap.toml",
                  "GF_AUTH_LDAP_ALLOW_SIGN_UP=true"]
    theme = v.get("DEFAULT_THEME", "light")
    if theme and not any(e.startswith("GF_USERS_DEFAULT_THEME=") for e in extra):
        extra.append("GF_USERS_DEFAULT_THEME=" + theme)
    token = o["render_token"] or read_env_file(os.path.join(cwd, ".env")).get("GRAFANA_RENDERER_TOKEN") or ""
    if (renderer or o["render_token_file"]) and not token:
        token = secrets.token_hex(16)
    if o["render_token_file"]:
        stack.files[paths.abs(o["render_token_file"])] = (token + "\n", 0o600)
    if renderer:
        stack.env["GRAFANA_RENDERER_TOKEN"] = token
        root = next((e.partition("=")[2] for e in extra if e.startswith("GF_SERVER_ROOT_URL=")), "")
        root = "" if re.match(r"https?://", root) else root.rstrip("/")
        svc = service("agrafrender", "grafanarender",
                      "docker.io/grafana/grafana-image-renderer:" + v["GRAFANA_RENDERER_VERSION"],
                      ports=[] if host else ["8081:8081"], command=["server"])
        svc["secrets_env"] = ["AUTH_TOKEN=${GRAFANA_RENDERER_TOKEN}"]
        extra += ["GF_RENDERING_SERVER_URL=http://%s/render" % address("agrafrender", 8081),
                  "GF_RENDERING_CALLBACK_URL=http://%s%s/" % (address(grafana_name, 3000 if not host else grafana_port),
                                                              root)]
    if v.get("HTTP_PROXY"):
        extra.append("http_proxy=" + v["HTTP_PROXY"])
    env += extra + ["GF_FEATURE_TOGGLES_ENABLE=dashboardSectionVariables"]
    volumes = ["./grafana/build:/var/lib/grafana/dashboards:z", "./grafana/plugins:/var/lib/grafana/plugins:z",
               "./grafana%s/provisioning:/var/lib/grafana/provisioning:z" % stack_dir]
    stack.config.append(paths.abs("grafana%s/provisioning" % stack_dir))
    if o["grafana_dir"]:
        volumes.append(paths(o["grafana_dir"]) + ":/var/lib/grafana")
        stack.dirs.append(paths.abs(o["grafana_dir"]))
    if o["ldap"]:
        volumes.append(paths(o["ldap"]) + ":/etc/grafana/ldap.toml")
    svc = service(grafana_name, "grafana", "docker.io/grafana/grafana:" + v["GRAFANA_VERSION"],
                  user=None if uid == 0 else user, userns_mode=userns, ports=ports((grafana_port, 3000)),
                  volumes=volumes,
                  environment=env)
    svc["secrets_env"] = ["GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}"]
    if renderer:
        svc["secrets_env"].append("GF_RENDERING_RENDERER_TOKEN=${GRAFANA_RENDERER_TOKEN}")
    stack.env["GRAFANA_ADMIN_PASSWORD"] = o["admin_password"] or "admin"
    if support:
        stack.warnings.append("--support-dashboard: set the support folder permissions in Grafana by hand")

    # Dashboards and datasources, as start-all.sh and start-grafana.sh make them
    if current == "master":
        cmd = ["./generate-dashboards.sh", "-v", o["versions"]]
        cmd += ["-F", "-R", "0"] if o["archive"] else []
        cmd += ["-M", o["manager_version"]] + (["-s", stack_id] if stack_id else [])
        cmd += ["--support-dashboard"] if support and not o["archive"] else []
        cmd += ["--vector-search"] if o["vector_search"] else []
        stack.commands.append(cmd)
    cmd = ["./generate-dashboards.sh"] + (["--vector-search"] if o["vector_search"] else []) + ["-t"]
    cmd += ["-S", o["solution"]] if o["solution"] else []
    cmd += ["-v", o["versions"], "-M", o["manager_version"]] + (["-s", stack_id] if stack_id else [])
    cmd += ["--clear"] if o["clear"] else []
    cmd += ["--support-dashboard"] if support else []
    for dashboard in o["dashboards"]:
        cmd += ["-j", dashboard]
    stack.commands.append(cmd)
    cmd = ["./grafana-datasource.sh", "-p", db_address, "-m", am_address]
    cmd += ["-L", loki_flag] if loki_flag else []
    cmd += ["-s", stack_id] if stack_id else []
    cmd += ["-S", o["scrap"]] if o["scrap"] else []
    stack.commands.append(cmd)

    # traefik, always on the host network, as start-traefik.sh runs it
    if o["traefik"]:
        for name in ("PRIVATE_IP", "CERT_DIR"):
            if not environ.get(name):
                raise ConfigError("--traefik: %s is required in the environment" % name)
        # as start-traefik.sh checks: a port published outside loopback
        # bypasses mTLS, or takes the address traefik needs
        if host:
            raise ConfigError("--traefik cannot be used with -l: the stack's ports would bypass traefik")
        if not re.match(r"^(127\.|::1$|\[::1\]$)", o["bind"].rstrip(":")):
            raise ConfigError("--traefik needs -A 127.0.0.1, so traefik is the only way in")
        cert_dir = environ["CERT_DIR"]
        if not cert_dir.startswith("/") or ":" in cert_dir:
            raise ConfigError("--traefik: CERT_DIR must be an absolute path without ':'")
        stack.commands.append(["./start-traefik.sh", "--config-only"])
        stack.config.append(paths.abs("traefik/build/static"))
        # ponytail: json-file rotation, as start-traefik.sh sets for docker's
        # default driver; follow the daemon's driver if another one is needed.
        services["traefik"] = {
            "container_name": "traefik", "image": "traefik:" + (environ.get("TAG") or v["TRAEFIK_VERSION"]),
            "network_mode": "host", "restart": "unless-stopped", "cap_drop": ["ALL"],
            "cap_add": ["DAC_READ_SEARCH"], "security_opt": ["no-new-privileges"],
            "logging": {"driver": "json-file", "options": {"mode": "non-blocking", "max-size": "50m",
                                                           "max-file": "3"}},
            "volumes": ["./traefik/build/static:/etc/traefik:ro,z", "./traefik/build/confs:/etc/traefik/confs:ro,z",
                        cert_dir + ":/etc/traefik/certs:ro"],
        }

    for svc in services.values():
        secret = svc.pop("secrets_env", [])
        for key in list(svc):
            svc[key] = escape(svc[key])
        if secret:
            svc["environment"] = svc.get("environment", []) + secret
    stack.compose = {"name": "scylla-monitoring" + ("-stack" + stack_id if stack_id else ""), "services": services}
    if network and not host:
        stack.compose["networks"] = {"default": {"name": network, "external": True}}
    stack.up = o["up"]
    for value in stack.env.values():
        env_value(value)  # rejects what .env cannot hold, before anything is written
    return stack


def write_text(path, text, mode):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(tmp, mode)
    os.rename(tmp, path)


CONFIG_LABEL = "com.scylladb.monitoring.config-hash"


def config_hash(stack, svc, cwd):
    """A hash of the config a service reads only on start: the generated
    files and the stack.config paths its volumes mount. docker compose up
    then recreates the service when they change, not only its definition."""
    def under(path, root):
        return path == root or path.startswith(root.rstrip("/") + "/")
    files = {os.path.normpath(os.path.join(cwd, p)): text for p, (text, _) in stack.files.items()}
    h = hashlib.sha256()
    for volume in svc.get("volumes", []):
        src = os.path.normpath(os.path.join(cwd, volume.replace("$$", "$").split(":")[0]))
        for path in sorted(p for p in files if under(p, src)):
            h.update(("%s\0%s\0" % (path, files[path])).encode())
        for root in sorted({os.path.normpath(c) for c in stack.config}):
            if not (under(src, root) or under(root, src)):
                continue
            top = src if under(src, root) else root
            paths = [top] if os.path.isfile(top) else sorted(
                os.path.join(d, name) for d, _, names in os.walk(top) for name in names)
            for path in paths:
                try:
                    with open(path, "rb") as f:
                        h.update(path.encode() + b"\0" + f.read() + b"\0")
                except OSError:
                    pass  # unreadable to this user, such as a root-only key
    return h.hexdigest()[:16]


def write(stack, cwd=None, environ=None, run=subprocess.run):
    """Writes the files, runs the helper scripts, writes docker-compose.yml
    and .env, and runs docker compose up when asked."""
    cwd = os.path.abspath(cwd or os.getcwd())
    environ = dict(os.environ if environ is None else environ)
    for warning in stack.warnings:
        print("Warning: " + warning, file=sys.stderr)
    for d in stack.dirs:
        os.makedirs(d, exist_ok=True)
    for path, (text, mode) in stack.files.items():
        write_text(os.path.join(cwd, path), text, mode)
    if stack.scylla_txt:
        path, lines = stack.scylla_txt
        date = datetime.datetime.now().strftime("%Y-%m-%d_%H_%M_%S")
        if os.path.isfile(path):
            os.rename(path, path.replace("scylla.txt", "scylla.%s.txt" % date))
        write_text(path, "\n".join(lines + ['LAST_RUN="%s"' % date]) + "\n", 0o644)
    for cmd in stack.commands:
        run(cmd, cwd=cwd, env=environ, check=True)
    for svc in stack.compose.get("services", {}).values():
        label = "%s=%s" % (CONFIG_LABEL, config_hash(stack, svc, cwd))
        labels = svc.setdefault("labels", [])
        if isinstance(labels, dict):
            labels[CONFIG_LABEL] = label.split("=", 1)[1]
        else:
            svc["labels"] = [l for l in labels if not l.startswith(CONFIG_LABEL + "=")] + [label]
    write_text(os.path.join(cwd, ".env"), "".join("%s=%s\n" % (k, env_value(val)) for k, val in sorted(stack.env.items())),
               0o600)
    write_text(os.path.join(cwd, "docker-compose.yml"), yaml.safe_dump(stack.compose, sort_keys=False), 0o644)
    if stack.up:
        run(["docker", "compose", "up", "-d", "--remove-orphans"], cwd=cwd, env=environ, check=True)


def main(argv):
    try:
        write(build(argv))
    except ConfigError as e:
        print("error: %s" % e, file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as e:
        print("error: %s failed" % " ".join(e.cmd), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
