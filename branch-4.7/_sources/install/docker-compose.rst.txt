Using Docker Compose
====================

Scylla-Monitoring Stack is container-based.
You can start and stop the Scylla Monitoring Stack with the `start-all.sh` and `kill-all.sh` scripts.
 
Docker Compose is an alternative method to start and stop the stack. It requires more manual steps, but once
configured, it simplifies starting and stopping the stack.

.. warning:: 

    *docker-compose* **and** *start_all.sh* are two **alternative** ways to launch Scylla Monitoring Stack.
    You should use **one** method, **not both**. In particular,  creating and updating *docker-compose.yml* is ignored
    when using *start_all.sh*

Prerequisite 
------------

Make sure you have `docker` and `docker-compose` installed.

Setting Prometheus
------------------

The Prometheus configuration file contains among others the IP address of the *alertmanager* and either the location
of the *scylla_server.yml* file or a Consul IP address of Scylla Manager, if Scylla Manager is used for server provisioning.

You can use `./prometheus-config.sh` to generate the file, for example: 

.. code-block:: shell

   ./prometheus-config.sh --compose
   
For production systems, It is advised to use an external directory for the Prometheus database. Make sure to create one and
update the docker-compose file accordingly (see the docker-compose example below).  

Setting Grafana Provisioning
----------------------------

Grafana reads its provisioning configuration from files, one for the data-source and one for the dashboards.
Note that the latter tells Grafana where the dashboards are located, it is not the dashboards themselves, which are
at a different location.

Grafana Data-Source file
^^^^^^^^^^^^^^^^^^^^^^^^
Run the following command to update the datasource:

.. code-block:: shell

   ./grafana-datasource.sh --compose

You can see the generated file under: `grafana/provisioning/datasources/datasource.yaml` 

Grafana Dashboard Load file
^^^^^^^^^^^^^^^^^^^^^^^^^^^
To set the dashboard load file, you can run the `./generate-sashboards.sh` with the `-t` command line flag and the `-v` flag to specify the version.
For example, Scylla-enterprise version 2020.1:

.. code-block:: shell

   ./generate-dashboards.sh -t -v 2020.1

This command generates the files under: `grafana/provisioning/dashboards/`

Docker Compose file
-------------------
You can use the following example as a base for your docker compose.

Pass the following to a file called `docker-compose.yml`


.. literalinclude:: docker-compose.example.yml
   :language: ruby


Start and Stop
^^^^^^^^^^^^^^

To start the Scylla Monitoring Stack run ``docker-compose up`` and to stop run ``docker-compose down``.
