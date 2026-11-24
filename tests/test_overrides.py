#!/usr/bin/env python3
"""Find dashboard template content that does not follow the class conventions.

usage: test_overrides.py [-t grafana/types.json] [-b BASE_TYPES] [template.json...]

Without templates it runs as a test: the self-test, then every dashboard
template that git tracks.

Reports:
  DUP     an override that sets the value its class already has
  PARTIAL an override that replaces a whole object and repeats some of its keys
  RAW     a panel written as raw Grafana JSON, with no "class"
  STYLE   a key no other template uses (Grafana export leftovers)

With -b (types.json of the base branch, e.g. from
`git show origin/master:grafana/types.json`), only the classes that are new or
changed are compared with their parent class. Without it all classes are.

Exit status is 1 when anything is reported.
"""
import argparse
import copy
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MISSING = object()
STYLE_KEYS = {
    "spec/definition": "query variables take only spec/query/spec/__legacyStringValue",
    "spec/query/spec/query": "use spec/query/spec/__legacyStringValue",
    "spec/query/spec/refId": "not needed on a variable",
    "spec/vizConfig/version": "leave the version of the class",
    "vizConfig/version": "leave the version of the class",
    "spec/vizConfig/spec/options/footer": "table footer is a Grafana export leftover",
}


def get_type(name, types):
    t = types[name]
    if "class" not in t:
        return t
    result = dict(t)
    for k, v in get_type(t["class"], types).items():
        result.setdefault(k, v)
    return result


def resolve(obj, types):
    """Expand classes and path overrides the way make_dashboards.py does."""
    if isinstance(obj, list):
        return [resolve(o, types) for o in obj]
    if not isinstance(obj, dict):
        return obj
    obj = copy.deepcopy(obj)
    if "class" in obj:
        for k, v in get_type(obj.pop("class"), types).items():
            if k != "class":
                obj.setdefault(k, copy.deepcopy(v))
    for k in [k for k in obj if "/" not in k]:
        obj[k] = resolve(obj[k], types)
    for k in [k for k in obj if "/" in k]:
        val = resolve(obj.pop(k), types)
        parts = k.split("/")
        target = obj
        for i, part in enumerate(parts[:-1]):
            if isinstance(target, list):
                target = target[int(part)]
            else:
                target = target.setdefault(part, [] if parts[i + 1].lstrip("-").isdigit() else {})
        if isinstance(target, list):
            target[int(parts[-1])] = val
        else:
            target[parts[-1]] = val
    return obj


def lookup(obj, path):
    for part in path.split("/"):
        try:
            obj = obj[int(part)] if isinstance(obj, list) else obj[part]
        except (KeyError, IndexError, ValueError, TypeError):
            return MISSING
    return obj


def check_object(where, obj, types, out):
    for k, why in STYLE_KEYS.items():
        if k in obj:
            out.append(f"STYLE   {where} | {k}: {why}")
    if "class" not in obj or obj["class"] not in types:
        return
    base = resolve({"class": obj["class"]}, types)
    for k, v in obj.items():
        if k in ("class", "panels", "rows", "tabs"):
            continue
        b = lookup(base, k)
        if b is MISSING:
            continue
        v = resolve(v, types)
        # An override replaces the whole value, so only an equal value is a
        # duplicate; a smaller object drops keys of the class and is kept.
        # It is also kept when another override of the object replaces a
        # parent of this key, so removing it would change the result.
        if v == b and resolve(obj, types) == resolve({x: y for x, y in obj.items() if x != k}, types):
            out.append(f"DUP     {where} | {k} = {json.dumps(v)[:80]}")
        elif isinstance(v, dict) and isinstance(b, dict):
            same = [x for x in v if x in b and v[x] == b[x]]
            if same:
                out.append(f"PARTIAL {where} | {k} repeats {same}")


def walk(obj, where, types, out, raw=True):
    if isinstance(obj, dict):
        label = obj.get("spec/title", obj.get("title", obj.get("spec/name", "")))
        if "class" in obj:
            check_object(f"{where} [{obj['class']}] {str(label)[:40]}", obj, types, out)
        elif raw and ("vizConfig" in obj or obj.get("kind") == "Panel"):
            title = obj.get("spec", obj).get("title", "") if isinstance(obj.get("spec", obj), dict) else ""
            out.append(f"RAW     {where} | panel without a class: {title}")
        for v in obj.values():
            walk(v, where, types, out, raw)
    elif isinstance(obj, list):
        for o in obj:
            walk(o, where, types, out, raw)


def run(types, base_types, templates):
    out = []
    for name, cls in types.items():
        if base_types is None or base_types.get(name) != cls:
            check_object(f"types.json class {name}", cls, types, out)
            # The body of a class is raw by definition; check the objects
            # inside it that use a class.
            for v in cls.values():
                walk(v, f"types.json class {name}", types, out, raw=False)
    for name, template in templates:
        walk(template, name, types, out)
    return out


def selftest():
    types = {
        "base": {"kind": "Panel", "span": 1, "spec": {"unit": "s", "legend": {"show": False, "calcs": []}, "steps": [{"color": "green"}]}},
        "child": {"class": "base", "spec/unit": "s", "span": 2},
        "outer": {"kind": "Panel", "items": [{"class": "base", "span": 1}]},
        "holder": {"panels": [{"span": 1}]},
    }
    template = {"rows": [
        {"class": "base", "spec/unit": "ms", "spec/steps/0/color": "green", "spec/legend": {"show": True, "calcs": []}},
        {"kind": "Panel", "spec": {"title": "raw"}},
        {"class": "base", "spec/vizConfig/version": ""},
        {"class": "base", "spec/legend": {"show": True}, "spec/legend/show": False},
        {"class": "holder", "panels": [{"span": 2}], "panels/0/span": 1},
    ]}
    out = run(types, {"base": types["base"]}, [("t", template)])
    kinds = sorted(o.split()[0] for o in out)
    assert kinds == ["DUP", "DUP", "DUP", "PARTIAL", "RAW", "STYLE"], out
    assert any("class outer" in o and "span" in o for o in out), out
    assert not any("spec/legend/show" in o for o in out), out
    assert not any("panels/0/span" in o for o in out), out
    assert any("class child" in o and "spec/unit" in o for o in out), out


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-t", "--types", default="grafana/types.json")
    parser.add_argument("-b", "--base-types")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("templates", nargs="*")
    args = parser.parse_args()
    if args.selftest or not args.templates:
        selftest()
        if args.selftest:
            return print("selftest passed")
        os.chdir(ROOT)
        args.templates = subprocess.check_output(
            ["git", "ls-files", "grafana/*.template.json"], text=True).split()
    types = json.load(open(args.types))
    base_types = json.load(open(args.base_types)) if args.base_types else None
    out = run(types, base_types, [(os.path.basename(t), json.load(open(t))) for t in args.templates])
    print("\n".join(out) if out else "ok")
    sys.exit(1 if out else 0)


if __name__ == "__main__":
    main()
