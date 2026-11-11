#!/usr/bin/env python3
# Checks packer/files/scylla-monitoring-preread.sh: the list it makes from
# Grafana's image layers and the stack's directories, and its read of the
# list: the summary line, a missing path, the time limit, a read error and
# the off switch.
# Run: python3 tests/test_preread.py
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.path.insert(0, ROOT)

SCRIPT = os.path.join(ROOT, "packer", "files", "scylla-monitoring-preread.sh")
MB = 1024 * 1024


def write(path, size=1):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"x" * size)


def run(cwd, *args, **env):
    return subprocess.run(["bash", SCRIPT] + list(args), cwd=cwd, env=dict(os.environ, **env),
                          capture_output=True, text=True)


def test_list(tmp):
    docker = os.path.join(tmp, "docker")
    g1 = os.path.join(docker, "overlay2", "a", "diff", "usr", "share", "grafana")
    g2 = os.path.join(docker, "overlay2", "b", "diff", "usr", "share", "grafana")
    write(os.path.join(g1, "data", "plugins-bundled", "prometheus", "plugin.json"))
    write(os.path.join(g1, "data", "plugins-bundled", "mysql", "plugin.json"))
    write(os.path.join(g1, "data", "plugins-bundled", "tempo", "plugin.json"))
    write(os.path.join(g2, "bin", "grafana"))
    write(os.path.join(g2, "conf", "defaults.ini"))
    # a running container's view of the layers is not read a second time
    write(os.path.join(docker, "overlay2", "c", "merged", "usr", "share", "grafana", "bin", "grafana"))
    stack = os.path.join(tmp, "stack")
    write(os.path.join(stack, "env.sh"), 0)
    with open(os.path.join(stack, "env.sh"), "w") as f:
        f.write("GF_PLUGINS_DISABLE_PLUGINS=${GF_PLUGINS_DISABLE_PLUGINS:-mysql, tempo}\n")

    res = run(stack, "--list", docker, os.path.join(tmp, "no-such-directory"))
    assert res.returncode == 0, res.stderr
    assert res.stdout.splitlines() == [
        os.path.join(g2, "bin"),
        os.path.join(g2, "conf"),
        os.path.join(g1, "data", "plugins-bundled", "prometheus"),
        "grafana/plugins", "grafana/provisioning", "grafana/build"], res.stdout

    # no Grafana binary, as with a storage driver that keeps layers elsewhere: the build fails
    res = run(stack, "--list", os.path.join(tmp, "no-such-directory"))
    assert res.returncode != 0 and "No Grafana binary" in res.stderr, res


def test_read(tmp):
    stack = os.path.join(tmp, "read")
    layer = os.path.join(tmp, "layer")
    write(os.path.join(layer, "bin", "grafana"), 2 * MB)
    write(os.path.join(stack, "grafana", "plugins", "scylla", "dist", "module.js"), MB)
    write(os.path.join(stack, "grafana", "provisioning", "dashboards", "load.yaml"), MB)
    listing = os.path.join(tmp, "list")
    with open(listing, "w") as f:
        f.write("%s\n%s\ngrafana/plugins\ngrafana/provisioning\ngrafana/build\n"
                % (os.path.join(layer, "bin"), os.path.join(tmp, "missing")))

    # every file is read; the missing paths are skipped
    res = run(stack, listing)
    assert res.returncode == 0, res.stderr
    assert res.stdout.startswith("Grafana pre-read: finished, 4 MB in "), res.stdout
    assert len(res.stdout.splitlines()) == 1, res.stdout

    # no list file: nothing to read, not an error
    res = run(stack, os.path.join(tmp, "missing"))
    assert res.returncode == 0 and "finished, 0 MB" in res.stdout, res

    # the time limit stops a read that is still running
    slow = os.path.join(tmp, "bin")
    write(os.path.join(slow, "cat"), 0)
    with open(os.path.join(slow, "cat"), "w") as f:
        f.write("#!/bin/sh\nsleep 30\n")
    os.chmod(os.path.join(slow, "cat"), 0o755)
    res = run(stack, listing, PATH=slow + os.pathsep + os.environ["PATH"], GRAFANA_PREREAD_TIMEOUT="1")
    assert res.returncode == 0, res.stderr
    assert res.stdout.startswith("Grafana pre-read: stopped by the 1s limit, 0 MB in "), res.stdout

    # a file that cannot be read is not reported as finished
    with open(os.path.join(slow, "cat"), "w") as f:
        f.write("#!/bin/sh\nexit 1\n")
    res = run(stack, listing, PATH=slow + os.pathsep + os.environ["PATH"])
    assert res.returncode == 0, res.stderr
    assert res.stdout.startswith("Grafana pre-read: ended with read errors (status 123), 0 MB in "), res.stdout

    # the off switch in env.sh
    with open(os.path.join(stack, "env.sh"), "w") as f:
        f.write("GRAFANA_PREREAD=0\n")
    res = run(stack, listing)
    assert res.returncode == 0 and res.stdout == "Grafana pre-read: off, GRAFANA_PREREAD=0\n", res


def test_image():
    env = open("packer/files/env.sh").read()
    assert "GRAFANA_PREREAD=1\n" in env and "GRAFANA_PREREAD_TIMEOUT=120\n" in env
    unit = open("packer/files/scylla-monitoring-preread.service").read()
    # nothing may wait for the read: not a oneshot, and ordered against nothing
    assert "oneshot\n" not in unit and "Before=" not in unit and "After=" not in unit
    installer = open("packer/files/scylla_monitoring_install_ami").read()
    assert "systemctl enable scylla-monitoring-preread.service" in installer


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as tmp:
        test_list(tmp)
        test_read(tmp)
    test_image()
    print("ok")
