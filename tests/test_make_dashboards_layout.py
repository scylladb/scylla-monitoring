#!/usr/bin/env python3
# Checks make_dashboards.py Grafana 13 layouts: rows/tabs nesting and section variables.
# Run: python3 tests/test_make_dashboards_layout.py
import copy
import json
import os
import sys
import tempfile
from types import SimpleNamespace

# Runs from the repository root, where make_dashboards.py and grafana/ are.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.path.insert(0, ROOT)

import make_dashboards as md

TYPES = md.get_json_file("grafana/types.json")
EXAMPLE = md.get_json_file("grafana/examples/tabs-example.template.json")
ARGS = SimpleNamespace(panel_as_spec=True)


def build(template, version="master"):
    md.id = 1
    md.strip_class = True
    result = copy.deepcopy(template)
    md.update_object(result, TYPES, [md.parse_version(v) for v in version.split(".")], [], {})
    md.make_grafana_13(result, ARGS)
    return result["dashboard"]["spec"]


def sections(layout):
    return layout["spec"].get("rows") or layout["spec"].get("tabs")


def raises(template, text):
    try:
        build(template)
    except ValueError as e:
        assert text in str(e), e
        return
    raise AssertionError(f"expected ValueError containing {text!r}")


spec = build(EXAMPLE)
root = spec["layout"]
assert root["kind"] == "TabsLayout"
overview, latency, per_dc = sections(root)
assert [t["kind"] for t in (overview, latency, per_dc)] == ["TabsLayoutTab"] * 3
assert overview["spec"]["layout"]["kind"] == "GridLayout"
assert "collapse" not in overview["spec"]

# section variable: kind+spec only, on the tab that declares it
assert latency["spec"]["variables"] == [v for v in latency["spec"]["variables"] if set(v) == {"kind", "spec"}]
assert [v["spec"]["name"] for v in latency["spec"]["variables"]] == ["quantile"]
assert [v["spec"]["name"] for v in spec["variables"]] == ["cluster", "dc"]

# rows inside a tab, tabs inside a row
assert latency["spec"]["layout"]["kind"] == "RowsLayout"
reads, lwt = sections(latency["spec"]["layout"])
assert lwt["kind"] == "RowsLayoutRow" and lwt["spec"]["collapse"] is True
assert lwt["spec"]["layout"]["kind"] == "TabsLayout"
assert [t["spec"]["title"] for t in sections(lwt["spec"]["layout"])] == ["Paxos", "Errors"]

# tab repeat normalised, conditional rendering kept
assert per_dc["spec"]["repeat"] == {"mode": "variable", "value": "dc"}
assert per_dc["spec"]["conditionalRendering"]["kind"] == "ConditionalRenderingGroup"
assert len(spec["elements"]) == 9

# dashversion filtering drops the LWT row with its tabs and panels
old = build(EXAMPLE, "2024.2")
assert [r["spec"]["title"] for r in sections(sections(old["layout"])[1]["spec"]["layout"])] == ["Reads and writes (p$quantile)"]
assert len(old["elements"]) == 5

# a root with rows still gives a RowsLayout
as_rows = copy.deepcopy(EXAMPLE)
as_rows["dashboard"]["rows"] = as_rows["dashboard"].pop("tabs")
assert build(as_rows)["layout"]["kind"] == "RowsLayout"

bad = copy.deepcopy(EXAMPLE)
bad["dashboard"]["tabs"][0]["rows"] = [{"class": "row", "panels": [{"class": "rps_panel"}]}]
raises(bad, "expected one of")

bad = copy.deepcopy(EXAMPLE)
bad["dashboard"]["panels"] = [{"class": "rps_panel"}]
raises(bad, "expected one of ['rows', 'tabs']")

# a section needs one of panels/rows/tabs; a typo must not silently drop it
bad = copy.deepcopy(EXAMPLE)
bad["dashboard"]["tabs"][0]["panel"] = bad["dashboard"]["tabs"][0].pop("panels")
raises(bad, "has [], expected one of")

bad = copy.deepcopy(EXAMPLE)
bad["dashboard"]["rows"] = bad["dashboard"].pop("tabs")
bad["dashboard"]["row"] = bad["dashboard"].pop("rows")
raises(bad, "has [], expected one of ['rows', 'tabs']")

# an unknown class fails instead of silently adding nothing
bad = copy.deepcopy(EXAMPLE)
bad["dashboard"]["tabs"][0]["panels"][0]["class"] = "rps_panle"
raises(bad, "class 'rps_panle' not found")

# an empty list still counts as the key being set
bad = copy.deepcopy(EXAMPLE)
bad["dashboard"]["panels"] = []
raises(bad, "expected one of ['rows', 'tabs']")

bad = copy.deepcopy(EXAMPLE)
bad["dashboard"]["tabs"][0]["rows"] = []
raises(bad, "expected one of")

# a list emptied by version filtering drops its section instead of failing
filtered = copy.deepcopy(EXAMPLE)
filtered["dashboard"]["tabs"].append({"class": "row", "title": "New", "rows": [
    {"class": "row", "dashversion": ["<2020.1"], "panels": [{"class": "rps_panel"}]}]})
assert [t["spec"]["title"] for t in sections(build(filtered)["layout"])] == ["Overview", "Latency", "DC $dc"]

# -G5 rejects tabs and nesting at any depth with a clear error
for template in (EXAMPLE, as_rows):
    g5 = copy.deepcopy(template)
    md.update_object(g5, TYPES, [md.MASTER_VERSION], [], {})
    try:
        md.make_grafana_5(g5, ARGS)
        raise AssertionError("expected ValueError from make_grafana_5")
    except ValueError as e:
        assert "only supported in the Grafana 13 format" in str(e), e

bad = copy.deepcopy(EXAMPLE)
bad["dashboard"]["tabs"][1]["variables"].append(copy.deepcopy(bad["dashboard"]["tabs"][1]["variables"][0]))
raises(bad, "duplicate variable names ['quantile']")

# SCYLLADB-2587: version tags pick a panel's queries and are left out of the output
tagged = copy.deepcopy(EXAMPLE)
tagged["dashboard"]["tabs"][0]["panels"][0]["spec/data/spec/queries"] = [
    {"class": "graph_query", "spec/query/spec/expr": "old", "dashversion": ["<2027.1"]},
    {"class": "graph_query", "spec/query/spec/expr": "new", "dashversion": [">2027.1"]}]
for version, kept, dropped in (("2026.4", "old", "new"), ("master", "new", "old")):
    spec = build(tagged, version)
    exprs = [q["spec"]["query"]["spec"]["expr"] for e in spec["elements"].values()
             for q in e["spec"].get("data", {}).get("spec", {}).get("queries", [])]
    assert kept in exprs and dropped not in exprs
    assert "dashversion" not in json.dumps(spec)
plain = copy.deepcopy(tagged)
md.update_object(plain, TYPES, [md.MASTER_VERSION], [], {})
assert "dashversion" not in json.dumps(plain)

# a version tag on the dashboard skips it for the versions it rejects, and removes an earlier build of it
with tempfile.TemporaryDirectory() as tmp:
    gated = copy.deepcopy(EXAMPLE)
    gated["dashboard"]["dashversion"] = [">2027.1"]
    path = os.path.join(tmp, "gated.template.json")
    with open(path, "w") as f:
        json.dump(gated, f)
    open(os.path.join(tmp, "gated.2026.4.json"), "w").close()
    for version in ("2026.4", "master"):
        args = SimpleNamespace(dash_version=version, add_row=[], product=[], grafana4=False, grafana5=False,
                               grafana13=True, panel_as_spec=True, strip_class=True, as_file=tmp)
        md.get_dashboard(path, TYPES, args, [], {})
    assert not os.path.exists(os.path.join(tmp, "gated.2026.4.json"))
    with open(os.path.join(tmp, "gated.master.json")) as f:
        assert "dashversion" not in json.load(f)

print("ok")
