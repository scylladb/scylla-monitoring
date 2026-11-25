---
name: dashboard-templates
description: Write, change or review the Grafana dashboard templates in grafana/*.template.json and the classes in grafana/types.json - class and override conventions, variables, hiding panels and sections, generation, and the review checklist for dashboard pull requests
---

# Dashboard templates

How to write and review changes to `grafana/*.template.json` and
`grafana/types.json`. Run all commands from the repository root.

The goal of the template format is that a dashboard holds as little as
possible: a panel names a class and states only what differs from it. Small
templates are easier to maintain, and a change to a class reaches every panel
that uses it.

## How templates work

`make_dashboards.py` builds each dashboard from its template and
`grafana/types.json`:

- An object with `"class": "<name>"` starts from that class in `types.json`.
  A class can itself have a `"class"`, so classes derive from one another.
- A key with slashes is a path override: `"spec/vizConfig/spec/options/x": 1`
  sets `obj["spec"]["vizConfig"]["spec"]["options"]["x"]`. A numeric part is a
  list index: `"spec/data/spec/queries/0/spec/query/spec/expr"`.
- A key set on the object wins over the same key in its class. A list or an
  object given as a value replaces the whole value of the class; to change one
  element, use a path override that reaches into it.
- Layout comes from `span` (12 units per row) and the height (`gridPos/h`).
  Positions (`x`, `y`, `w`) and panel ids are generated.

## Rules

### Panels

1. Every panel has a class. Raw Grafana JSON (`"kind": "Panel"` with a full
   `data` / `vizConfig` body) does not go into a template. To bring in a panel
   built in the Grafana UI, find the closest class and write only the
   differences as path overrides.
2. Reuse before adding. Look in `types.json` for a class that already does the
   job (`graph_panel` and its unit variants such as `ops_panel`, `ms_panel`,
   `bytes_panel`, `percent_panel`, `seconds_panel`; `small_stat`,
   `small_stat_area`; `single_value_table`; `plain_text`). A small dashboard
   such as `grafana/scylla-overview.template.json` shows the expected density.
3. A new class derives from the nearest existing class and holds only the
   differences. A class that sets again what another class already has should
   derive from that class.
4. An override never repeats the value of its class.
5. What two or more objects override the same way belongs in a class: a panel
   class for shared options, a query class for a shared legend or format, one
   class for a panel that appears in two sections (for example the same table
   for two task types).
6. Change one element of a list with a path override
   (`.../mappings/0/options/-2`), not by repeating the whole list.
7. Leave out what a Grafana export adds and the class already provides or the
   generator creates: `vizConfig/version`, the table `footer` block, `id`,
   `gridPos` `x`/`y`/`w`, the datasource, `refId` on the first query.
8. Text panels use `plain_text` with HTML content. Section headers follow the
   pattern in "Layout conventions". No emoji.

### Variables

1. Use the variable classes: `query_variable`, `query_variable_all`,
   `hidden_query_variable`, `custom_variable`.
2. A query variable sets its query only with
   `"spec/query/spec/__legacyStringValue"`. Do not add `spec/definition`,
   `spec/query/spec/query` or a `refId`.
3. Use the same names as the other dashboards for the same filter: `cluster`,
   `dc`, `rack`, `node`, `shard`, `by`. A different name needs a reason, such
   as filtering on a different label.
4. One variable per name in a dashboard. A duplicate name breaks it.
5. A variable used by one section is a section variable (`"variables"` on the
   section), not a dashboard variable.

### Queries

1. Missing data must not look healthy. `or vector(0)` on a failure count turns
   "no samples" into a green zero. Return zero only when the checked series
   exist, and show a distinct value for no data.
2. A stat that shows the state "now" uses an instant query. A range query with
   `lastNotNull` keeps showing the last sample after the series is gone.
3. Aggregate by the identity of the thing shown (for example a task id), and
   use names only for display. Two objects can share a name.
4. See "PromQL joins" for joins that silently return nothing.

### Dashboard content

1. A dashboard has no "deprecated" section. A panel that is useful stays; a
   panel that is not is removed.
2. A pull request that removes panels lists them and says why, and what
   replaces them. Check what users of older versions are left with when the
   new panels depend on new metrics.
3. A new view of an existing subject goes into the existing dashboard, using
   sections, tabs and section variables, not into a new dashboard.

### Commits and pull request

1. A change to the Prometheus configuration (scrape config, relabeling,
   rules) is its own commit with an explanation, separate from the dashboard
   change.
2. A change that alters labels on existing series is stated in the commit
   message and in the pull request description.
3. A pull request changes each line once. When several commits in it change
   the same line (a change, then fixes for review comments on it), squash
   them into the commit that introduced the line before asking for review
   again.
4. Run the checks in "Verify" before sending the pull request and again
   after every update to it.
5. The repository is public. Screenshots, queries and descriptions carry no
   customer names, cluster ids or internal addresses.

## Hiding panels and sections

Two mechanisms, both classes in `types.json`. Pick by level.

### Panel: hide when it has no data

For a metric that may not exist (older version, feature not in use):

```json
{
    "span": 3,
    "class": "ops_panel",
    "spec/title": "Resize decisions",
    "conditionalRendering": {
        "class": "conditionalRendering_data"
    }
}
```

The row must use an auto grid; Grafana ignores the data condition in the grid
layout that `base_row` uses:

```json
{
    "class": "row",
    "layout": {
        "class": "auto_grid_layout",
        "spec/maxColumnCount": 4
    },
    "panels": [ ... ]
}
```

A metric that exists but is flat still returns data, so the panel stays; only
an absent metric hides it. Example: `grafana/scylla-vector-search.template.json`.

### Section: hide when a hidden variable is empty

Grafana evaluates data conditions only for panels. To hide a row, section or
tab, add a hidden query variable that is empty when the marker metric is
absent, and a variable condition:

```json
{
    "title": "Host CPU",
    "conditionalRendering": {
        "class": "conditionalRendering_var",
        "spec/items/0/spec/variable": "location_info"
    },
    "rows": [ ... ]
}
```

```json
{
    "class": "hidden_query_variable",
    "spec/name": "location_info",
    "spec/label": "location_info",
    "spec/query/spec/__legacyStringValue": "label_values(scylla_reactor_location_info{cluster=\"$cluster\"}, cluster)"
}
```

`conditionalRendering_var` hides when the variable matches `^$`. Example: the
Host CPU row in `grafana/scylla-advanced.template.json`.

### Do not use dashversion

`"dashversion": [">2025.1"]` on a row, panel or query removes it at generation
time for the other versions. It is being removed from the templates: do not
add it to new or changed content.

For content that depends on the version, use the two mechanisms above. They
decide at view time from live data, so one generated dashboard fits every
version:

- a panel whose metric exists only from some version: hide it when it has no
  data;
- a row, section or tab: hide it with a hidden variable that queries the
  metric which marks the feature.

## PromQL joins

`+`, `*` and the like between vectors are inner joins: if either side returns
nothing, the whole expression returns nothing.

- Join through metrics the panel already depends on, not through an extra
  "info" metric. A detour through a metric that is absent on some clusters
  empties the whole panel there. Every Scylla metric carries the same target
  labels (`cluster`, `dc`, `rack`, `instance`), so read the label from the
  metric already in the join.
- An empty regex matcher (`rack=~""`) matches only the series that have no
  such label, or have it empty. A filter or a repeat over an empty variable
  shows those series and hides every series that has a value in the label.
- To debug "no data", run each side of the join separately in Explore, and
  check the interpolated query in the panel's query inspector for variables
  that resolved to `""`.

## Layout conventions

- A row is 12 `span` units; the panel widths in a row add up to a full row.
- Section header: a `hideHeader` row with `"gridPos/h": 2` holding a
  `plain_text` panel with
  `<h1 style="color:#5780C1; border-bottom: 3px solid #5780C1;">Name</h1>`.
- Repeat a panel over a variable with `"repeat": "<varname>"`.
- Sections, tabs and section variables: see
  `grafana/examples/tabs-example.template.json`.

## Verify

Run all of these before sending a pull request.

1. Check the overrides with `tests/test_overrides.py`:

   ```bash
   git show origin/master:grafana/types.json > /tmp/types.base.json
   python3 tests/test_overrides.py \
     -b /tmp/types.base.json grafana/<dashboard>.template.json
   ```

   - `RAW`: a panel without a class.
   - `DUP`: an override equal to the value of its class.
   - `PARTIAL`: an object override that repeats some keys of its class; use
     path overrides for the keys that differ.
   - `STYLE`: an export leftover or a non-standard variable key.

   The templates have none of these. The script cannot see the same override
   repeated across objects (Panels rule 5) or a class that re-creates a
   sibling (Panels rule 3); read the diff for those.

2. Generate the dashboard and confirm the output is valid JSON:

   ```bash
   mkdir -p /tmp/dash
   ./make_dashboards.py -af /tmp/dash -t grafana/types.json \
     -d grafana/<dashboard>.template.json \
     -R "__MONITOR_VERSION__=master" -R "__SCYLLA_VERSION_DOT__=2026.1" \
     -R "__MONITOR_BRANCH_VERSION=master" -R "__REFRESH_INTERVAL__=30s" \
     --replace-file docs/source/reference/metrics.yaml -V 2026.1
   ```

   `./generate-dashboards.sh -F` regenerates everything.

3. Run `tests/run.sh`. It must pass. It includes `tests/test_overrides.py`
   on all the templates.

4. Load the dashboard in Grafana and look at every panel with data, without
   data, and with each variable set to one value and to All. For content that
   is hidden conditionally, check it both against a cluster that has the
   metric and one that does not.

## Reviewing a dashboard pull request

1. Fetch the head without checking it out, and work on copies:

   ```bash
   mkdir -p /tmp/pr
   git fetch origin pull/<N>/head
   git show FETCH_HEAD:grafana/types.json > /tmp/pr/types.json
   git show FETCH_HEAD:grafana/<dashboard>.template.json > /tmp/pr/<dashboard>.template.json
   ```

2. Run the override check and the generation from "Verify" on the copies:
   pass `-t /tmp/pr/types.json`, and `/tmp/pr/<dashboard>.template.json` as
   the template of the check and as `-d` of the generation. `tests/run.sh` runs the tests of the current
   checkout, not of the copies: take its result from the CI of the pull
   request, or check the pull request out to run it.
3. Read the `types.json` diff: does each new class derive from the nearest
   existing class, and is any existing class changed (that affects other
   dashboards)?
4. Read the template for the rules above, in this order: panels without a
   class, repeated overrides, variables, queries, removed panels.
5. Compare the list of panels and variables with the base branch and ask
   about everything that disappeared.
6. Check files outside `grafana/`: a Prometheus configuration change is a
   separate commit and its effect on existing series is described.
7. Report the blocking items first (raw panels, removed functionality, wrong
   data), then duplication, then style.
