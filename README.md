# HashiCorp Consul Docker-Compose Test Environment

This repo contains a full featured environment for setting up and testing HashiCorp Consul Enterprise.

It is a constant Work-in-progress.

Details:

* Heavy focus on implementing and testing the latest Consul features.
* Rapidly changing.
* Currently only configures Service Discovery
  * Mesh additions coming soon.

Architecture:
![](readme-images/architecture.png)

# Initialization Pre-Requirements

* Environment requires Docker-Compose
* HashiCorp Consul Enterprise license required.
  * Place in `./license`
* Generate Consul PKI Root certs and Consul Server RPC certs
  * Self-signed certificates have already been provided in this repo.
  * If they need to be regenerated:
    * From within `./certs`
      ```
      consul tls ca create -days=3650
      consul tls cert create -server -dc=dc1 -additional-dnsname=consul-server1-dc1 -days=1825
      consul tls cert create -server -dc=dc2 -additional-dnsname=consul-server1-dc2 -days=1825
      chmod 644 *
      ```
* Create Auth0 account with appropriate configuration
  * Required only for the OIDC authentication in this Consul environment.
  * Details on how to do that will come later. For now reference this [Learn Guide](https://https://developer.hashicorp.com/consul/tutorials/datacenter-operations/single-sign-on-auth0?in=consul%2Fdatacenter-operations).
    * NOTE: The guide is outdated and Auth0 has since changed the locations for a few of the components. Everything is still possible to complete using this guide, but the locations of the config params are in different places on the leftside bar. Specifically:
      * `Applications` > `Applications` > Default
      * `Auth Pipeline` > `Rules`

# Instructions to Execute Environment

* Launch docker-compose environment:
  * `docker-compose up`
* Configure the environment using the `post-config.sh` script:
  * `./post-config.sh`

# Tear down and Re-build Environment

* Delete all docker resources except the images:
  * `docker ps -a | grep -v CONTAINER | awk '{print \$1}' | xargs docker stop; docker ps -a | grep -v CONTAINER | awk '{print \$1}' | xargs docker rm; docker volume ls | grep -v DRIVER | awk '{print \$2}' | xargs docker volume rm; docker network prune -f`
  * `docker-compose up`

# Architecture Overview

## Consul Servers

* 2x single-node Consul Clusters

### DC1

* Servers (1)
  * `consul-server1-dc1`
  * UI exposed on local port 8500: `http://127.0.0.1:8500/ui/_default/dc1/services`
* Gossip Encryption: `aPuGh+5UDskRAbkLaXRzFoSOcSM+5vAK+NEYOWHJH7w=`

### DC2

* Consul Servers (1)
  * `consul-server1-dc2`
* UI exposed on local port 8501: `http://127.0.0.1:8501/ui/_default/dc2/services`
* Gossip Encryption: `dznVKWl1ri975FUJiddzAPM+3eNP9iXDad2c8hghsKA=`

## Admin Partitions & Namespaces

### DC1

* `default`
* `donkey`
* `unicorn`
  * `frontend` (NS)
  * `backend` (NS)
* `proj1`
* `proj2`

### DC2

* `default`
* `heimdall`

## Cluster Peering Relationships & Exported Services

* `DC1` <> `DC2` peered on `default` partitions

### Exported Services

#### DC1

* DC1 `donkey(AP)/donkey` > DC1 `default` (AP)
* DC1 `default(AP)/joshs-obnoxiously-long-service-name-gonna-take-awhile` > `DC2` (Peer)

#### DC2

* DC2 `default(AP)/josh` > `DC1` (Peer)

## HashiCorp Vault

Vault will eventually be implemented in the future as the Certificate Authority for the Consul Connect Service Mesh.

* The Vault server is currently commented out in the docker-compose file.

## Consul Clients

### consul-client-dc1-alpha (DC1)

* **DC**: `DC1`
* **Partition**: `default`
* **Services**:
  * `josh` (4 instances)
    * This `josh` service is exported to the `DC2` peer (`default`).
    * The `service.id` is `josh-local-x` to differentiate between this local service and the imported service (see Notes below)
  * `joshs-obnoxiously-long-service-name-gonna-take-awhile` (8 instances)
    * This `joshs-obnoxiously-long-service-name-gonna-take-awhile` service is exported to the `DC2` peer (`default`).
* **ACL Token**: `00000000-0000-0000-0000-000000001111`
  * `node-identity=client-dc1-alpha:dc1`
  * `service-identity=joshs-obnoxiously-long-service-name-gonna-take-awhile:dc1`
  * `service-identity=josh:dc1`
* **Notes**:
  * Within `DC1` and `DC2`, each cluster contains a service named `josh`.
  * This is intentional, as to test out the behavior of when a exported service from a peer matches the same name of a local service.
  * `DC1/default_AP/default_NS/josh` and `DC2/default_AP/default_NS/josh => DC1/default_AP/default_NS`
  * (Bug) As of 1.13.2, the UI cannot list the instances of both `josh` services by clicking on them.
    * Both links point to the imported `josh` only (bugged)
    * The UI URL can be manually manipulated to view the local `josh`: `http://127.0.0.1:8500/ui/_default/dc1/services/josh/instances`

### consul-client-dc1-charlie-ap1 (DC1)

* **DC**: `DC1`
* **Partition**: `donkey`
* **Services**:
  * `donkey` (5 instances)
* **ACL Token**: `root`
* **Notes**:

### consul-client-dc1-delta-ap2 (DC1)

* **DC**: `DC1`
* **Partition**: `unicorn`
* **Services**:
  * `unicorn-frontend` (3 instances)
    * Namespace: `frontend`
  * `unicorn-backend` (3 instances)
    * Namespace: `backend`
* **ACL Token**: `root`
* **Notes**:

### consul-client-dc1-echo-proj1 (DC1)

* **DC**: `DC1`
* **Partition**: `proj1`
* **Services**
  * `baphomet` (3 instances)
* **ACL Token**: `root`
* **Notes**:

### virtual (DC1)

* **DC**: `DC1`
* **Partition**: `proj1`
* **Services**
  * `virtual-baphomet` (3 external instances)
* **Notes**:
  * This is a virtual node registered with the `post-config.sh` script.
  * It represents an externally registered service
  * Each `virtual-baphomet` service can be de-registered using the following commands:
    ```
    curl --request PUT --data @./configs/services-dc1-proj1-baphomet0.json --header "X-Consul-Token: root" localhost:8500/v1/catalog/register
    curl --request PUT --data @./configs/services-dc1-proj1-baphomet1.json --header "X-Consul-Token: root" localhost:8500/v1/catalog/register
    curl --request PUT --data @./configs/services-dc1-proj1-baphomet2.json --header "X-Consul-Token: root" localhost:8500/v1/catalog/register
    ```

### consul-client-dc2-bravo (DC2)

* **DC**: `DC2`
* **Partition**: `default`
* **Services**:
  * `josh` (7 instances)
* **ACL Token**: `root`
* **Notes**:
  * This `josh` service is exported to the `DC1` peer (`default`).

# ACL Auth / Policies / Roles / Tokens

## ACL Tokens

#### Token: `root`

* Policy: `global-management`

#### Token: `00000000-0000-0000-0000-000000001111`

* Policies:
  * node-identity: `client-dc1-alpha:dc1`
  * service-identity: `joshs-obnoxiously-long-service-name-gonna-take-awhile:dc1`
  * service-identity: `josh:dc1`
* Purpose:
  * Agent token for Consul Client `consul-client-dc1-alpha` (DC1)

#### Token: `00000000-0000-0000-0000-000000002222`

* Role: `team-proj1-rw`
* Purpose:
  * Grant write permissions within `DC1` / `proj1` partition.

#### Token: `00000000-0000-0000-0000-000000003333`

* Role: `DC1-Read`
* Purpose:
  * Read-only privileges within the entire `DC1` cluster.

## Roles

#### Role: `consul-admins`

* Policy: `global-management`
* Purpose:
  * Assign root level permissions.
  * Used within the Auth0 OIDC method (group: `admins`) to define who should have "god mode" in the Consul Cluster

#### Role: `team-proj1-rw`

* Purpose: Grant write permissions within `DC1` / `proj1` partition.
* Used within the Auth0 OIDC method (group: `proj1`) to define who should have management permission of the `proj` partition

#### Role: `dc1-read`

* Purpose: Read-only privileges within the entire `DC1` cluster.

## OIDC Authentiction

### Auth0

#### Binding Rules

* auth0 groups = `proj1`
* auth0 groups = `admins`

# Enabled Features

### Core Cluster Config

* Consul Enterprise
* Admin Partitions Enabled
* Best-Practice Security Features Enabled
  * TLS encryption on all nodes.
  * TLS Verify on everything.
  * Gossip Encryption enabled.

### PKI / Certificates

* Auto encrypt enabled (automatic distribution of Consul Client RPC certificates)

### ACL / RBAC / Tokens

* `global-management` token defined as `root`
  * When in doubt use the `root` token.
* Most tokens and roles are scoped to the `default` partitions.
  * This is intentional, so all tokens are at the root hierarchy and can be scoped to managed any resource in any partition. (best-practices)

### Authentication

* OIDC Authentication enabled with Auth0

# Future Goals

### Key Architecture

* Add a local Kubernetes Consul cluster
  * Likely using minikube or k3s. Haven't decided.
* Add ECS cluster
  * Need to figure out how to expose local networking to ECS. This may not be practical for a DC lab. We'll see.

### Cluster Peering & Exported Services

* Add `non-default` partition peering relationships and see how cumbersome the management is.

### PKI / Certificates

* Add Vault as the ConnectCA
* Use a unique CA keyset for each DC (`DC1` / `DC2`)
  * This is how separately managed clusters would work in the real world.

### Service Mesh

* Add FakeService applications working in the Consul Mesh.
* Split DC1 and DC2 into completely separate IP networks.
  * Requires adding Mesh Gateways into the DC1 and DC2 perimeters.
  * See Network examples from [Nic Jackson](https://github.com/nicholasjackson/demo-consul-service-mesh/blob/master/gateways/docker-compose.yml)

### Authentication Methods

* Add JWT authentication

### Metrics / Telemetry

* Add local UI metrics
  * I think this will require setting up a local prometheus pod.

# Staging Notes
