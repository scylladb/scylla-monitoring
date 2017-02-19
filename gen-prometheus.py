template = """
global:
  scrape_interval: 1s # By default, scrape targets every 1 second.

  # Attach these labels to any time series or alerts when communicating with
  # external systems (federation, remote storage, Alertmanager).
  external_labels:
    monitor: 'scylla-monitor'

scrape_configs:
- job_name: scylla
  honor_labels: true
  static_configs:
  - targets: %s

- job_name: node_exporter
  honor_labels: true
  static_configs:
  - targets: %s
"""

from sys import argv
from string import split
ips=split(argv[1],",")
def add_port(vec, port):
    return str(map(lambda x: x + ":" + port, vec))
print template%(add_port(ips, "9180"), add_port(ips, "9100"))
