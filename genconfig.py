#!/usr/bin/python

import argparse
import os
import yaml

scylla_port=9180
node_exporter_port=9100

def append_port(ips, port):
    return [ "%s:%s"%(x, port) for x in ips ]

def gen_targets(servers, port):
    return {"targets" : append_port(servers, port) }

def dump_yaml(directory, filename, servers, port):
    try:
        os.mkdir(directory)
    except OSError, err:
        if err.errno != 17:
            raise
        pass 
    stream = file(os.path.join(directory, filename), 'w')
    yaml.dump([gen_targets(servers, port)], stream)
    
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate configuration for prometheus")
    parser.add_argument('-d', '--directory', help="directory where to generate the configuration files", type=str, default="./")
    parser.add_argument('-s', '--scylla', help="Generate scylla_servers.yml file", action='store_true')
    parser.add_argument('-n', '--node', help="Generate node_exporter_servers.yml file", action='store_true')
    parser.add_argument('servers', help="list of nodes to configure, separated by space", nargs='+', type=str, metavar='node_ip')
    arguments = parser.parse_args()

    if arguments.scylla:
        dump_yaml(arguments.directory, 'scylla_servers.yaml', arguments.servers, scylla_port)
    
    if arguments.node:
        dump_yaml(arguments.directory, 'node_exporter_servers.yaml', arguments.servers, node_exporter_port)
    
