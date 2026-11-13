#!/usr/bin/env python3
# Checks the alerting rules in prometheus/prom_rules/ with the promtool unit
# tests in tests/data/prometheus_rules/, using the Prometheus image of
# versions.sh when it is pulled.
# Run: python3 tests/test_prometheus_rules.py
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.path.insert(0, ROOT)

import scylla_monitoring_config as smc

DATA = os.path.join("tests", "data", "prometheus_rules")
RULES = os.path.join("prometheus", "prom_rules")


def test_rules():
    image = "prom/prometheus:" + smc.stack_versions(ROOT)[0]
    if not shutil.which("docker") or subprocess.run(["docker", "image", "inspect", image],
                                                    capture_output=True).returncode:
        print("skipped promtool: docker or %s is not available" % image)
        return
    user = "%d:%d" % (os.getuid(), os.getgid())
    with tempfile.TemporaryDirectory() as tmp:
        for d in (DATA, RULES):
            shutil.copytree(d, os.path.join(tmp, d))
        for name in sorted(os.listdir(DATA)):
            result = subprocess.run(["docker", "run", "--rm", "-u", user, "-v", tmp + ":/c:ro,z", "-w", "/c",
                                     "--entrypoint", "promtool", image, "test", "rules", os.path.join(DATA, name)],
                                    capture_output=True, text=True)
            if result.returncode:
                print(result.stdout, result.stderr)
            assert result.returncode == 0


if __name__ == "__main__":
    test_rules()
    print("ok")
