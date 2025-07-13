#!/usr/bin/env python3

import argparse
import os
import yaml
import re
import sys
from copy import deepcopy

def gen_targets(servers, cluster, alias_separator):
    if ':' not in servers:
        raise Exception('Server list must contain a dc name')
    dcs = servers.split(':', maxsplit=1)
    res = {"labels": {"cluster": cluster, "dc": dcs[0]}}
    ips = dcs[1].split(',')
    res["targets"] = [ip for ip in ips if not alias_separator or alias_separator not in ip]
    if len(res["targets"]) == len(ips):
        return res
    multi_resutls = [res] if len(res["targets"]) > 0 else []
    for ip in ips:
        if alias_separator and alias_separator in ip:
            res = deepcopy(res)
            ip_part = ip.split(alias_separator)
            res["targets"] = [ip_part[0]]
            res["labels"]["instance"] = ip_part[1]
            multi_resutls.append(res)
    return multi_resutls

def get_servers_from_nodetool_status():
    res = []
    dc = None
    ips = []
    for line in sys.stdin:
        if dc:
            ip = re.search(r"..\s+([\d\.]+)\s", line)
            if ip:
                ips.append(ip.group(1))
        m = re.search(r"Datacenter: ([^\s]+)\s*$", line)
        if m:
            if dc:
                res.append(dc + ":" + ",".join(ips))
            ips = []
            dc = m.group(1)
    if dc:
        res.append(dc + ":" + ",".join(ips))
    return res

def dump_yaml_no_dc(directory, filename, servers):
    try:
        os.mkdir(directory)
    except OSError as err:
        if err.errno != 17:
            raise
        pass
    with open(os.path.join(directory, filename), 'w') as stream:
        yaml.dump([{"targets": servers}], stream, default_flow_style=False)

def dump_yaml(directory, filename, servers, cluster, alias_separator):
    try:
        os.mkdir(directory)
    except OSError as err:
        if err.errno != 17:
            raise
        pass
    with open(os.path.join(directory, filename), 'w') as yml_file:
        targets = [gen_targets(s, cluster, alias_separator) for s in servers]
        res = [target for sublist in targets for target in (sublist if isinstance(sublist, list) else [sublist])]
        yaml.dump(res, yml_file, default_flow_style=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate configuration for prometheus")
    parser.add_argument('-d', '--directory', help="directory where to generate the configuration files", type=str, default="./")
    parser.add_argument('-s', '--scylla', help="Deprecated: Generate scylla_servers.yml file", action='store_true')
    parser.add_argument('-n', '--node', help="Deprecated: Generate node_exporter_servers.yml file", action='store_true')
    parser.add_argument('-c', '--cluster', help="The cluster name", type=str, default="my-cluster")
    parser.add_argument('-o', '--output-file', help="The servers output file", type=str, default="scylla_servers.yml")
    parser.add_argument('-NS', '--nodetool-status', help="Use nodetool status output. Output is read from stdin", action='store_true')
    parser.add_argument('servers', help="list of nodes to configure, separated by space", nargs='*', type=str, metavar='node_ip')
    parser.add_argument('-a', '--alias-separator', help='If present, nodes will be parsed as IP{separator}alias. For example: 192.0.2.1:mynode')
    parser.add_argument('-dc', '--datacenters', action='append', help="list of dc and nodes to configure separated by comma. Each dc/nodes entry is a combination of {dc}:ip1,ip2..ipn. You can add an alias to an IP by adding ip{separator}alias")
    arguments = parser.parse_args()

    if arguments.nodetool_status:
        dump_yaml(arguments.directory, arguments.output_file, get_servers_from_nodetool_status(), arguments.cluster, None)
    else:
        if arguments.servers:
            dump_yaml_no_dc(arguments.directory, arguments.output_file, arguments.servers)
        else:
            dump_yaml(arguments.directory, arguments.output_file, arguments.datacenters , arguments.cluster, arguments.alias_separator)
    if arguments.node:
        dump_yaml_no_dc(arguments.directory, 'node_exporter_servers.yml', arguments.servers)
