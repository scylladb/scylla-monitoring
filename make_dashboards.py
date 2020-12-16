#!/usr/bin/env python3
#
# Copyright (C) 2017 ScyllaDB
#

#
# This file is part of Scylla.
#
# Scylla is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Scylla is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Scylla.  If not, see <http://www.gnu.org/licenses/>.

from __future__ import print_function

import argparse
import json
import re
import os

parser = argparse.ArgumentParser(description='Dashboards creating tool', conflict_handler="resolve")
parser.add_argument('-t', '--type', action='append', help='Types file')
parser.add_argument('-R', '--Replace', action='append', help='Search and replace a value, it should be in a format of old_value=new_value')
parser.add_argument('-d', '--dashboards', action='append', help='dashbaords file')
parser.add_argument('-ar', '--add-row', action='append', help='merge a templated row, format number:file', default=[])
parser.add_argument('-r', '--reverse', action='store_true', default=False, help='Reverse mode, take a dashboard and try to minimize it')
parser.add_argument('-G', '--grafana4', action='store_true', default=False, help='Do not Migrate the dashboard to the grafa 5 format, if not set the script will remove and emulate the rows with a single panels')
parser.add_argument('-h', '--help', action='store_true', default=False, help='Print help information')
parser.add_argument('-kt', '--key-tips', action='store_true', default=False, help='Add key tips when there are conflict values between the template and the value')
parser.add_argument('-af', '--as-file', type=str, default="", help='Make the dashboard ready to be loaded as files and not with http, when not empty, state the directory the file will be written to')

def help(args):
    parser.print_help()
    print("""
The utility can be used to create dashboards from templates or templates from dashboards.

types files holds type definitions.
Type is a json object, that will be added (but not replace) to the values in the template.
Types support inheritance, when a type holds a class field, it would inherit the fields from
the base class.

Type examples:

{
    "base_row": {
        "collapse": false,
        "editable": true
    },
    "small_row": {
        "class": "base_row",
        "height": "25px"
    },
    "row": {
        "class": "base_row",
        "height": "150px"
    }
}


Template example:

{
    "dashboard": {
        "class": "dashboard", 
        "rows": [
            {
                "class": "small_row", 
                "panels": [
                    {
                        "class": "text_panel", 
                        "content": "<img src=\"http://www.scylladb.com/wp-content/uploads/logo-scylla-white-simple.png\" height=\"70\">\n<hr style=\"border-top: 3px solid #5780c1;\">", 
                        "id": "auto", 
                    }
                ], 
                "title": "New row"
            }, 
            {
                "class": "row" 
            }
        ]
    }
}

When creating templates, the -kt is useful to find conflicts.
    """
    )
    

def get_type(name, types):
    if name not in types:
        return {}
    if "class" not in types[name]:
        return types[name]
    result = types[name].copy()
    cls = get_type(types[name]["class"], types)
    for k in cls:
        if k not in result:
            result[k] = cls[k]
    return result
    

def get_json_file(name):
    try:
        return json.load(open(name))
    except Exception as inst:
        print("Failed opening file:", name, inst)
        exit(0)

def write_json(name, obj, replace_strings=[]):
    y = json.dumps(obj, sort_keys = True, separators=(',', ': '), indent = 4)
    for r in replace_strings:
        y = y.replace(r[0], r[1])
    with open(name, 'w') as outfile:
        outfile.write(y)
    
def merge_json_files(files):
    results = {}
    for name in files:
        results.update(get_json_file(name))
    return results

def make_replace_strings(replace):
    results = []
    if (replace):
        for v in replace:
            results.append(v.split('=', 1))
    return results

def update_object(obj, types):
    global id
    if not isinstance(obj, dict):
        return obj
    if "class" in obj:
        extra = get_type(obj["class"], types)
        for key in extra:
            if key not in obj:
                obj[key] = extra[key]
    for v in obj:
        if v == "id" and obj[v] == "auto":
            obj[v] = id
            id = id + 1
        elif isinstance(obj[v], list):
            obj[v] = [update_object(o, types) for o in obj[v]]
        elif isinstance(obj[v], dict):
            obj[v] = update_object(obj[v], types)
    return obj

def compact_obj(obj, types, args):
    if not isinstance(obj, dict):
        return obj
    for v in obj:
        if isinstance(obj[v], list):
            if obj[v] and isinstance(obj[v][0], dict) and obj[v][0]:
                obj[v] = [compact_obj(o, types, args) for o in obj[v]]
        elif isinstance(obj[v], dict):
            obj[v] = compact_obj(obj[v], types, args)

    if "class" in obj:
        extra = get_type(obj["class"], types)
        for key in extra:
            if key != "class" and key in obj:
                if key != "id" and obj[key] != extra[key]:
                    if args.key_tips:
                        obj["**" + key + "**"] = extra[key]
                else:
                    obj.pop(key)
    return obj

def get_space_panel(size):
    global id
    id = id + 1
    return {
  "class": "text_panel",
  "content": "##  ",
  "editable": True,
  "error": False,
  "id": id,
  "links": [],
  "mode": "markdown",
  "span": size,
  "style": {},
  "title": "",
  "transparent": True,
  "type": "text"
}

def panel_width(gridpos, panel):
    if "w" in gridpos:
        return gridpos["w"]
    if "span" in panel:
        return panel["span"] * 2
    return 6

def get_height(value, default):
    m = re.match(r"(\d+)", value)
    if m:
        return int(int(m.group(1))/30)
    return default

def set_grid_pos(x, y, panel, h, gridpos):
    if "x" not in gridpos:
        gridpos["x"] = x
    if "y" not in gridpos:
        gridpos["y"] = y
    if "h" not in gridpos:
        if "height" in panel:
            gridpos["h"] = get_height(panel["height"], h)
        else:
            gridpos["h"] = h
    if "w" not in gridpos:
        gridpos["w"] = panel_width(gridpos, panel)
    panel["gridPos"] = gridpos
    return gridpos["h"]

def add_row(y, panels, row, args):
    total_span = 0
    h = 6
    x = 0
    max_h = 0
    if "height" in row:
        if row["height"] != "auto":
            h = get_height(row["height"], h)
    if "gridPos" in row:
        if "h" in row["gridPos"]:
            h = row["gridPos"]["h"]
    for p in row["panels"]:
        gridpos = {}
        if "gridPos" in p:
            gridpos = dict(p["gridPos"])
        else:
            gridpos = {}
        w = panel_width(gridpos, p)
        if  w + x > 24:
            x = 0
            y = y + max_h
            max_h = 0
        height = set_grid_pos(x, y, p, h, gridpos)
        x = x + w
        if height > max_h:
            max_h = height
        panels.append(p)
    return y + max_h

def is_collapsed_row(row):
    return len(row["panels"]) == 1 and row["panels"][0]["type"] == "row" and "collapsed" in row["panels"][0] and row["panels"][0]["collapsed"]

def is_collapsable_row(row):
    return len(row["panels"]) == 1 and row["panels"][0]["type"] == "row"

def make_grafna_5(results, args):
    rows = results["dashboard"]["rows"]
    panels = [];
    y = 0
    in_collapsable_panel = False
    collapsible_row = []
    collapsible_panels = []
    for row in rows:
        if is_collapsable_row(row) and in_collapsable_panel:
            collapsible_row[0]["panels"] = collapsible_panels
            panels.append(collapsible_row[0])
            collapsible_row = []
            collapsible_panels = []
            in_collapsable_panel = False
        if is_collapsed_row(row):
            in_collapsable_panel = True
            y = add_row(y, collapsible_row, row, args)
        else:
            if in_collapsable_panel:
                y = add_row(y, collapsible_panels, row, args)
            else:
                y = add_row(y, panels, row, args)
    del results["dashboard"]["rows"]
    if in_collapsable_panel:
        collapsible_row[0]["panels"] = collapsible_panels
        panels.append(collapsible_row[0])
    results["dashboard"]["panels"] = panels

def write_as_file(name_path, result, dir, replace_strings):
    name = os.path.basename(name_path)
    write_json(os.path.join(dir, name), result["dashboard"], replace_strings)

def get_dashboard(name, types, args, replace_strings):
    global id
    id = 1
    new_name = name.replace("grafana/", "grafana/build/").replace(".template.json", ".json")
    result = get_json_file(name)
    for r in args.add_row:
        [row_number, row_name] = r.split(",")
        row = get_json_file(row_name)
        result["dashboard"]["rows"].insert(int(row_number), row)
    update_object(result, types)
    if not args.grafana4:
        make_grafna_5(result, args)
    if args.as_file:
        write_as_file(new_name, result, args.as_file, replace_strings)
    else:
        write_json(new_name, result, replace_strings)
    
def compact_dashboard(name, type, args):
    new_name = name.replace(".json", ".template.json")
    result = get_json_file(name)
    result = compact_obj(result, types, args)
    write_json(new_name, result)
    
args = parser.parse_args()
if args.help:
    help(args)
    exit(0)

types = merge_json_files(args.type)
replace_strings = make_replace_strings(args.Replace)
for d in args.dashboards:
    if args.reverse:
        compact_dashboard(d, types, args)
    else:
        get_dashboard(d, types, args, replace_strings)
