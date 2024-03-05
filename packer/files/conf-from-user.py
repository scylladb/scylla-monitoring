#!/usr/bin/python3

import urllib.request
import json
import subprocess
import shutil
import shlex
import yaml
import argparse
import email
from pathlib import Path

HOME_DIR='/home/centos/'
USER='centos'
dry_run=None
verbose=None

"""
{
"version": "master,5.1",
"ips":["127.0.0.1", "127.0.0.2"]
}
"""

def run(template_cmd, shell=False):
    cmd = template_cmd.format(_HOME=HOME_DIR, _USER=USER)
    if dry_run:
        print(cmd)
        return
    if verbose:
        print(cmd)
    if not shell:
        cmd = shlex.split(cmd)
    try:
        res = subprocess.check_output(cmd, shell=shell)
        if verbose:
            print(res)
        return res
    except Exception as e:
        print("Error while running:")
        print(cmd,end =" ")
        print(e.output)
        raise

def parse_message(response):
        r = response.read()
        msg = email.message_from_bytes(r)
        res = {}
        if msg.is_multipart():
            for part in msg.walk():
                obj = None
                filename = part.get_filename()
                base_filename =  filename.split('.')[0] if filename else None
                # if base_filename and base_filename in ['scylla_server', 'scylla-monitoring', 'env']:
                if part.get_content_type().startswith('application/') or part.get_content_type().startswith('text/plain'):
                    type = part.get_content_type().split('/')[1].strip(' \t\n\r')
                    pyload = None
                    if type.endswith('yml') or type.endswith('yaml'):
                        pyload = part.get_payload(decode='utf-8')
                        obj = yaml.safe_load(pyload)
                    elif type.endswith('json'):
                        pyload = part.get_payload(decode='utf-8')
                        obj = json.load(pyload)
                    else:
                        obj = part.get_payload(decode=True).decode('utf-8')
                if obj:
                    res[base_filename] = {'obj' : obj, 'filename': filename, 'payload' : pyload}
        else:
            print("message is not a multipart, ignoring")
        return res

def get_parsed_message(url, headers={}):
    try:
        req = urllib.request.Request(url, headers=headers)
        response = urllib.request.urlopen(req)
        return parse_message(response)
    except Exception as err:
        print(f"Unexpected {err=}, {type(err)=}")
        return None

def getAWSData(args):
    url = 'http://169.254.169.254/latest/user-data' if args.address == "" else args.address 
    return get_parsed_message(url) 

def getGCEData(args):
    url = 'http://metadata.google.internal/computeMetadata/v1/instance/attributes/user-data' if args.address == "" else args.address
    return get_parsed_message(url, headers={'Metadata-Flavor': "Google"})

def getData(args):
    if args.cloud == 'aws':
        return getAWSData(args)
    elif args.cloud == 'gce':
        return getGCEData(args)
    return {}

def getVersions(version):
    if isinstance(version, str):
        return version
    return ",".join(version)

def mk_servers(obj):
    with open(HOME_DIR + 'scylla-grafana-monitoring-scylla-monitoring/prometheus/scylla_servers.yml', 'w') as f:
        documents = yaml.dump(obj, f)

def getDataDir(data):
    if 'prometheus_data' in data:
        return data['prometheus_data']
    run('sudo -u {_USER} mkdir -p {_HOME}/scylla-grafana-monitoring-scylla-monitoring/data')
    return HOME_DIR + 'scylla-grafana-monitoring-scylla-monitoring/data'

def mk_env(data):
    with open(HOME_DIR + 'scylla-grafana-monitoring-scylla-monitoring/env.sh', 'w') as f:
        f.write(data)
    run('chown {_USER}:{_USER} {_HOME}/scylla-grafana-monitoring-scylla-monitoring/env.sh')

def setupStartAll(data):
    try:
        run('sudo -u {_USER} cp {_HOME}/scylla-grafana-monitoring-scylla-monitoring/prometheus/rule_config.original.yml {_HOME}/scylla-grafana-monitoring-scylla-monitoring/prometheus/rule_config.yml')
    except Exception as e:
        print("Error while running:")
    if 'env' in data: 
        mk_env(data['env']['obj'])
    if 'scylla_server' in data:
        mk_servers(data['scylla_server']['obj'])

def generate_dashboard(data):
    manager = " -M " + data['manager'] if 'manager' in data else ""
    run('sudo -u {_USER} ./generate-dashboards.sh -F -v {VERSION} {MANAGER}'.format(_USER=USER, VERSION=getVersions(data['version']), MANAGER=manager))

def add_dashboard(scylla_monitoring, data):
    if 'dashboards' not in scylla_monitoring:
        return
    for dashboard in scylla_monitoring['dashboards']:
        if 'name' in dashboard:
            with open(HOME_DIR + 'scylla-grafana-monitoring-scylla-monitoring/{NAME}'.format(NAME=dashboard["full_name"]), 'w') as f:
                if 'name' in dashboard and dashboard['name'] in data:
                    f.write(data[dashboard['name']]['payload'])

parser = argparse.ArgumentParser(description='Setup Scylla Monitoring from userdata', conflict_handler="resolve")
parser.add_argument('-u', '--user', default="centos", help='The username that is being used')
parser.add_argument('-c', '--cloud', default="aws", help='The cloud to connect to (aws/gcp)')
parser.add_argument('-a', '--address', default="", help='If set uses the provided address to fetch the data from')
args = parser.parse_args()
data = getData(args)
USER = args.user
HOME_DIR='/home/' + USER + '/'
if "scylla-monitoring" not in data or "version" not in data["scylla-monitoring"]['obj']:
    exit(0)
scylla_monitoring = data["scylla-monitoring"]['obj']
setupStartAll(data)
generate_dashboard(scylla_monitoring)
add_dashboard(scylla_monitoring, data)
run('sudo -u {_USER} ./start-all.sh')
