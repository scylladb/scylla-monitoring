*******************************
Adding and Modifying Dashboards
*******************************

This document explains how to update or create Grafana dashboards for the Scylla Monitoring Stack.

It covers dashboard templates and how to modify them.

.. contents::
   :depth: 2
   :local:


General Limitations
###################
Scylla Monitoring Stack uses Grafana for its dashboards.
The dashboards are provisioned from files and are stored in the Grafana internal storage.
There are two potential consistency issues, covered below.

Consistency Between Restarts
****************************
By default, the Grafana internal storage is within the container. That means that whenever you restart the Scylla Monitoring Stack (explicitly when restarting Grafana) any local changes will not be persisted.
If you are making changes and saving changes from the GUI make sure to configure an external directory for Grafana.

Consistency Between Upgrades
****************************
As mentioned earlier, the dashboards are provisioned from files, this means that when the files are changed, any changes stored locally will be overridden. For this reason, do not make permanent changes to a dashboard, or your changes eventually will be lost.

.. note::  You can save a dashboard change you made from the GUI, but it can be overridden. This should be avoided.

At large, we suggest maintaining your dashboards as files, as Scylla Monitoring does.


Using Templated Dashboards
##########################
Scylla Monitoring uses dashboard templates as we found the Grafana dashboards in JSON format to be too verbose to be maintainable.

Each element in the dashboard file (Each JSON  object) contains all of its attributes and values.

For example a typical graph panel would look like this:

.. code-block:: json

        {
            "aliasColors": {},
            "bars": false,
            "datasource": "prometheus",
            "editable": true,
            "error": false,
            "fill": 0,
            "grid": {
                "threshold1": null,
                "threshold1Color": "rgba(216, 200, 27, 0.27)",
                "threshold2": null,
                "threshold2Color": "rgba(234, 112, 112, 0.22)"
            },
            "gridPos": {
                "h": 6,
                "w": 10,
                "x": 0,
                "y": 4
            },
            "id": 2,
            "isNew": true,
            "legend": {
                "avg": false,
                "current": false,
                "max": false,
                "min": false,
                "show": false,
                "total": false,
                "values": false
            },
            "lines": true,
            "linewidth": 2,
            "links": [],
            "nullPointMode": "connected",
            "percentage": false,
            "pointradius": 5,
            "points": false,
            "renderer": "flot",
            "seriesOverrides": [
                {}
            ],
            "span": 5,
            "stack": false,
            "steppedLine": false,
            "targets": [
                {
                    "expr": "sum(node_filesystem_avail) by (instance)",
                    "intervalFactor": 1,
                    "legendFormat": "",
                    "refId": "A",
                    "step": 1
                }
            ],
            "timeFrom": null,
            "timeShift": null,
            "title": "Available Disk Size",
            "tooltip": {
                "msResolution": false,
                "shared": true,
                "sort": 0,
                "value_type": "cumulative"
            },
            "transparent": false,
            "type": "graph",
            "xaxis": {
                "show": true
            },
            "yaxes": [
                {
                    "format": "percent",
                    "logBase": 1,
                    "max": 101,
                    "min": 0,
                    "show": true
                },
                {
                    "format": "short",
                    "logBase": 1,
                    "max": null,
                    "min": null,
                    "show": true
                }
            ]
        }

As you can imagine, most panels would have similar values.

To reduce the redundancy of the Grafana JSON format, we added dashboard templates.

The Template Class System
***************************

The Scylla Monitoring Stack dashboard templates use a ``class`` attribute that can be added to any JSON object in a template file.
The different classes are defined in a file.

The ``class`` system resembles CSS classes. It is hierarchical, so a ``class`` type definition can have a ``class`` attribute and
it would inherit that class attributes, the inherited class can add or override inherited attributes.

In the template file, you can also add or override attributes.

The Scylla Monitor generation script, uses the `types.json` file and a template file and creates a dashboard.

When generating dashboards, each class will be replaced by its definition.

For example, a row in the `type.json` is defined as:

.. code-block:: json

   {
    "base_row": {
        "collapse": false,
        "editable": true
    },
    "row": {
        "class": "base_row",
        "height": "250px"
    }
    }

Will be used like in a template:

.. code-block:: json

   {
        "class": "row",
        "height": "150px",
        "panels": [
        ]
   }

And the output will be:

.. code-block:: json

   {
        "class": "row",
        "collapse": false,
        "editable": true,
        "height": "150px",
        "panels": [

        ]
   }


We can see that the template added the ``panels`` attribute and that it overrides the ``height`` attribute.


Panel Example
*************

Consider the following example that defines a row inside a dashboard with a graph
panel for the available disk size.

.. code-block:: json

   {
        "class": "row",
        "panels": [
            {
                "class": "bytes_panel",
                "span": 3,
                "targets": [
                    {
                        "expr": "sum(node_filesystem_avail) by (instance)",
                        "intervalFactor": 1,
                        "legendFormat": "",
                        "metric": "",
                        "refId": "A",
                        "step": 1
                    }
                ],
                "title": "Available Disk Size"
            }
        ]
   }

In the example, the `bytes_panel` class generates a graph with bytes as units (that would mean that your
`Y` axis units would adjust themselves to make the graph readable (i.e. GB, MB, bytes, etc').

You can also see that the `span` attribute is overridden to set the panel size.

To get a grasp of the difference, take a look at the Grafana panel example and see how it looks originally.

Grafana Formats and Layouts
***************************

The Grafana layout used to be based on rows, where each row contained multiple panels.
Each row would have a total of 12 panels and if the total span of the panels was larger than 12, it would
break them into multiple lines. This is no longer the case.

Starting from  Grafana version 5.0 and later, rows were no longer supported, they were replaced with a layout that uses
absolute positions (i.e. X,Y, height, width).

The server should be backward compatible, but we've found it had issues with parsing it correctly.
More so, absolute positions are impossible to get right when done by hand.

To overcome these issues, the dashboard generation script will generate the dashboards in the Grafana version 5.0 format.
In the transition, rows will be replaced with a calculated absolute position.

The panel's height will be taken from their row. The `span` attribute is still supported as is row height.

You can use the `gridPos` attribute which is a Grafana 5.0 format, but unlike Grafana, you can use partial attributes.

`gridPos` has the following attributes:

.. code-block:: json

   {
      "x": 0,
      "y": 0,
      "w": 24,
      "h": 4
    }

When using Scylla's template you don't need to supply all of the attributes, so for example to specify that a row is 2 units high you can use:

.. code-block:: json

    {
       "gridPos": {
          "h": 2
        }
    }

Generating the dashboards from templates (generate-dashboards.sh)
*****************************************************************

Prerequisite
============
Python 3
pyyaml


`make_dashboards.py` is a utility that generates dashboards from templates or helps you update the templates when working in reverse mode (the `-r` flag).

Use the -h flag to get help information.

You can use the `make_dashboards.py` to generate a single dashboard, but it's usually easier to use the
`generate-dashboards.sh` wrapper.

When you're done changing an existing dashboard template, run the `generate-dashboards.sh` with the current version,
to replace your existing dashboards.

For example, if you are changing a dashboard in Scylla Enterprise version 2020.1 run:

``.\generate-dashboards.sh -v 2020.1``

.. note::  generate-dashboards.sh will update the dashboards in place, there is no need for a restart for the changes to take effect, just refresh the dashboard.


Validation
**********
After making changes to a template, run the ``generate_generate-dashboards.sh`` and make sure that it ran without any errors.

Refresh your browser for changes to take effect.
Make sure that your panels contain data, if not, maybe there is something wrong with your ``expr`` attribute.
