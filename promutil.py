#!/usr/bin/env python3

import argparse
import requests
import re
import yaml
import os

from datetime import datetime, timedelta

time_format = re.compile('(\d+)([smhdw])')
has_port = re.compile('[^:]+:(\d+)$')
def add_port_if_needed(host):
    if has_port.match(host):
        return host
    return host + ":9090"

def help(args):
    parser.print_help()

def print_url(url, params):
    return url + "?" + "&".join([k + "=" +v for k,v in params.items()])

def get_rules(name):
    res = []
    with open(name) as file:
        o = yaml.load(file, Loader=yaml.FullLoader)
        for g in o["groups"]:
            res = res + g["rules"]
    return res

def metrics_to_openmatrics(m, name=None, labels={}, fl=None):
    if not m["values"]:
        return
    static_labels = [k + "=" + '"' + str(v) + '"' for k,v in labels.items()]
    if not name:
        name = m["metric"]["__name__"]
    name = name + "{" + ",".join(static_labels + [k + "=" +'"' + v+'"' for k,v in m["metric"].items() if k != "__name__"]) + "}"
    for v in m["values"]:
        if fl:
            fl.write(name + " "+ str(v[1])+ " "+  str(v[0])+"\n")
        else:
            print(name, v[1], v[0])
    
    #print("# TYPE", name, "gague")
def range_to_openmatrics(res, name=None, labels={}, fl=None):
    if not res or not res[0]["values"]:
        return False
    if not name:
        name = res[0]["metric"]["__name__"]
    if fl:
        fl.write("# TYPE" + " "+  name+ " "+  "gauge\n")
    else:
        print("# TYPE", name, "gauge")
    for q in res:
        metrics_to_openmatrics(q, name, labels, fl=fl)
    return True

def print_range(res, name=None, labels={}, out_format="OM", fl_name=None, new_file=False):
    if out_format != "OM":
        return
    file_op = "w" if new_file else "a+" 
    if fl_name:
        with open(fl_name, file_op) as f:
            if range_to_openmatrics(res, name=name, labels=labels, fl=f) and new_file:
                f.write("# EOF\n")
    else:
        range_to_openmatrics(res, name=name, labels=labels)

def get_json_data(url, params):
    resp = requests.get(url=url, params=params)
    res = resp.json()
    return res['data']['result']

def range_query(host, params, max_points):
    url = "http://" +host + "/api/v1/query_range"
    print(url, params)
    step = get_delta(params['step'])
    start = str2time(params['start'])
    end = str2time(params['end'])
    num_points = (end-start)/step
    if num_points <= max_points:
        return get_json_data(url, params)
    res = []
    current = start
    while current < end:
        params['start'] = time2str(current)
        current = current + step*max_points
        if current > end:
            current = end
        params['end'] = time2str(current)
        res = res + get_json_data(url, params)
        current = current + step
    return res
def get_timedelta(v, typ):
    if typ == 's':
        return timedelta(seconds = v)
    if typ == 'm':
        return timedelta(minutes = v)
    if typ == 'h':
        return timedelta(hours = v)
    if typ == 'd':
        return timedelta(days = v)
    if typ == 'w':
        return timedelta(weeks = v)

def str2time(s):
    return datetime.strptime(s, '%Y-%m-%dT%H:%M:%S.%fZ')

def time2str(s):
    return s.strftime('%Y-%m-%dT%H:%M:%S.%fZ')

def get_delta(s):
    t = time_format.match(s)
    if t:
        i = int(t.group(1))
        return get_timedelta(i, t.group(2))
    return None

def get_time(s):
    t = get_delta(s)
    if t != None:
        return datetime.now() - t
    return str2time(s)

def get_start_end_time(args):
    start = None
    end = None
    if args.start:
        start = get_time(args.start)
    if args.end:
        end = get_time(args.end)
    if not start:
        if not end:
            end = get_time('0s')
        start = end - get_delta(args.duration)
    if not end:
        end = start + get_delta(args.duration)
    return time2str(start), time2str(end)

def terminate_output(name, out_format, new_file, skip_oef):
    if out_format != "OM" or skip_oef:
        return
    if name:
        if not new_file:
            with open(name, "a+") as f:
                f.write("# EOF\n")
    else:
        print("# EOF")

def safe_param_name(name):
    return name.replace('.', '_')
def do_range_query_by_host(host, args):
    start, end = get_start_end_time(args)
    if args.query:
        params = dict(
            query=args.query,
            start=start,
            end=end,
            step=args.step
        )
        print_range(range_query(host, params, args.max_point), out_format=args.format, fl_name=args.out_file, new_file=args.new_file, name=args.query_name)
        # range_to_openmatrics(range_query(host, params), name=args.query_name)
    if args.rules:
        rules = get_rules(args.rules)
        i = 0
        for r in rules:
            if 'record' in r and args.skip_rules or 'record' not in r and args.skip_alerts:
                continue 
            name = safe_param_name(r['record'] if 'record' in r else 'alert:' + r['alert'])
            params = dict(
                query=r['expr'],
                start=start,
                end=end,
                step=args.step
            )
            labels = r['labels'] if 'labels' in r else {}
            print_range(range_query(host, params, args.max_point), name=name, labels=labels, out_format=args.format, fl_name=args.out_file, new_file=args.new_file)
            if args.post_script != "":
                os.system(args.post_script)

def do_range_query(args):
    if args.host_file:
        print("using host file", args.host_file)
        with open(args.host_file) as file:
            for l in file:
                print(l.strip())
                if l.strip() != "":
                    do_range_query_by_host(add_port_if_needed(l.strip()), args)
    else:
        do_range_query_by_host(add_port_if_needed(args.host), args)
    terminate_output(args.out_file, args.format, args.new_file, args.skip_eof)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Prometheus swiss army knife helper', conflict_handler="resolve")
    parser.add_argument('-h', '--host', default="127.0.0.1:9090", help='Prometheus host to connect to')
    parser.add_argument('-F', '--format', default="OM", help='The output format, default open metrics (OM)')
    parser.add_argument('-R', '--rules', default="", help='Read the queries from rule format')
    parser.add_argument('-hf', '--host-file', default="", help='If set, the host or hosts will be read from a file')
    subparsers = parser.add_subparsers(help='Available commands')
    parser_help = subparsers.add_parser('help', help='Display help information')
    parser_help.set_defaults(func=help)
    parser_rquery = subparsers.add_parser('rquery', help='do a range query')
    parser_rquery.add_argument('-q', '--query', help='Prometheus query')
    parser_rquery.add_argument('-s', '--step', default="15s", help='Query step')
    parser_rquery.add_argument('--skip-alerts', default=False, action='store_true', help='when set only recording rules will be created and alerts will be skipped')
    parser_rquery.add_argument('--skip-rules', default=False, action='store_true', help='when set only alerts will be created and recording rules will be skipped')
    parser_rquery.add_argument('-d', '--duration', default="1h", help='Duration, can replace the start or end')
    parser_rquery.add_argument('--start', default="", help='start time, can either be in relative h/m/d/s or absolute time')
    parser_rquery.add_argument('--end', default="", help='end time, can either be in relative h/m/d/s or absolute time')
    parser_rquery.add_argument('--post-script', default="", help='if set the script will be run after each metrics creation')
    parser_rquery.add_argument('-o', '--out-file', default="", help='if set, output will be written to an out-file')
    parser_rquery.add_argument('-qn','--query-name', default=None, help='if set, name will be used for the query')
    parser_rquery.add_argument('--new-file', default=False, action='store_true', help='if set the script will create a new file, typically if using post script')
    parser_rquery.add_argument('--skip-eof', default=False, action='store_true', help='if set the script will not write EOF')
    parser_rquery.add_argument('-m', '--max-point', default=10000, type=int, help='limit the number of data points per query')
    parser_rquery.set_defaults(func=do_range_query)
    args = parser.parse_args()
    args.func(args)

