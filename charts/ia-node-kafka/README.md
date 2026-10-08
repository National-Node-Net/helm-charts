# ia-node-kafka

**Repository:** `[helm-charts]`  
**Helm-Chart-Name:** `[ia-node-kafka]`  
**Description:** `[National Digital Twin Programme Helm chart for Kafka, a helper package to support deployment of the IA Node]`  
**SPDX-License-Identifier:** `Apache-2.0 AND OGL-UK-3.0 `  

## Overview  

The Helm chart `ia-node-kafka` is intended to ease deployment and configuration of Apache Kafka which is a prerequisite required to deploy an IA Node (Integration Architecture Node).

Apache Kafka is a distributed event streaming platform for high-performance data pipelines, streaming analytics and data integration, the helper package `ia-node-kafka` intends to ease first time deployments for testing. 

[Overview of Apache Kafka](https://kafka.apache.org/)

This chart has been developed to provide an example deployment of a Kafka Cluster using the [Kafka Strimzi Operator](https://artifacthub.io/packages/helm/strimzi-kafka-operator/strimzi-kafka-operator) for use specifically with the IA Node secure graph component. 

> [!IMPORTANT]  
> Secret management is outside of the scope of the deployment, however we have provided a few possible examples on how you might override the default values or provide your own where supported.

## TL;DR

> [!IMPORTANT]  
> The installation assumes that Istio has already been installed Istio, following the [Istio Helm Install](https://istio.io/latest/docs/setup/install/helm/) guide, and assumes a default principal of `cluster.local/ns/istio-system/sa/ingressgateway`, and default gateway of `istio-system/istio-gateway`.

```sh
helm install my-release oci://ghcr.io/national-node-net/helm/ia-node-kafka -n ia-node
```

Optionally, use an overrides.yaml:

```sh
helm install my-release oci://ghcr.io/national-node-net/helm/ia-node-kafka -n ia-node -f ./overrides.yaml 
```

## Prerequisites

You will require the following technologies installed and configured to get started. 

Versions highlighted are based on what configurations have been used throughout the testing of the Helm chart. 

- **Supported Kubernetes Versions:** 
  - [`Kubernetes 1.23+`](https://kubernetes.io/): a Kubernetes cluster i.e. AKS or local development cluster 
  
- **Required Tooling:**
  - [`kubectl 1.28.9+`](https://kubernetes.io/docs/reference/kubectl/): prior knowledge, usage and experience with `kubectl` 
  - [`Helm 3.8.0+`](https://helm.sh/): prior knowledge, usage and experience in Helm
  - [`jq 1.6+`](https://jqlang.org/): for querying and formating json
  
- **Optional Tooling:**
  - [`K9s 0.32.5+`](https://K9scli.io/): for Kubernetes cluster overview and visualisation of deployments
  
- **Installation Requirements:** 
  - [`Istio Helm chart, Gateway, Base and Istiod 1.25.0+`](https://istio.io/latest/docs/setup/install/helm/): service mesh that layers onto existing application, providing uniform and more efficient ways to secure, connect, and monitor services
  - [`Kafka Strimzi Operator 0.48.0+`](https://artifacthub.io/packages/helm/strimzi-kafka-operator/strimzi-kafka-operator): bootstraps the Strimzi Cluster Operator Deployment, Cluster Roles, Cluster Role Bindings, Service Accounts, and Custom Resource Definitions for running Apache Kafka. Note: Version 0.48.0+ is required for Kafka 4.x with KRaft mode support.

## Installing the Chart

Install the Kafka Strimzi Operator and then run the following to install. Ensure that 'watchAnyNamespace' is set to true if you want the operator to work against any namespace. 

Note: The below --set commands for resources are optional and configured for small environments
```sh
helm install my-strimzi-cluster-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator --namespace kafka-operator --create-namespace \
  --set watchAnyNamespace="true" \
  --set resources.requests.cpu=50m \
  --set resources.requests.memory=128Mi \
  --set resources.limits.cpu=500m \
  --set resources.limits.memory=256Mi
```

Create the target namespace if it does not already exist, typically this will be the same namespace as the core IA Node application. 

```sh
kubectl create namespace ia-node
```

If running Istio in side car mode, remember to add the injection label: 

```sh
kubectl label namespace ia-node istio-injection=enabled
```

Install the latest chart (defaults to Kafka 4.1.0 with KRaft mode for small environments): 

```sh
helm install ia-node-kafka oci://ghcr.io/national-node-net/helm/ia-node-kafka -n ia-node
```

Optionally, use an overrides.yaml:

```sh
helm install ia-node-kafka oci://ghcr.io/national-node-net/helm/ia-node-kafka -n ia-node -f ./overrides.yaml 
```

> [!NOTE]
> The chart now defaults to Kafka 4.1.0 with KRaft mode (no ZooKeeper) for better performance and reduced resource usage. For production environments with multiple brokers, adjust `kafkaCluster.spec.kraft.brokerReplicas` and `kafkaCluster.spec.kraft.controllerReplicas` accordingly.

## Uninstall the Chart

To uninstall the Helm chart:

```sh
helm uninstall ia-node-kafka -n ia-node
```

To uninstall the Kafka cluster operator: 

```sh
helm install my-strimzi-cluster-operator -n kafka-operator 
```

## Configuration and Installation details

### Istio

Any Istio examples throughout this documentation are provided largely as information to help support integrators to plan their own deployment.

The installation assumes that Istio has already been installed Istio following the [Istio Helm install](https://istio.io/latest/docs/setup/install/helm/) and assumes a default principal of `cluster.local/ns/istio-system/sa/ingressgateway` and default gateway of `istio-system/istio-gateway`. 

> [!NOTE]
> Istio `authorization policies` are implemented to restrict communications between components. These principals are based on the namespace a service is deployed to and the service account it runs as. In particular, the principal that the Istio ingress is assigned is environment specific and may differ from the one specified in the default deployment. These can all be overridden using the Helm values. 

### Secret Management

This chart provides a few options for managing the default secrets. 

#### Override the Value 

Override the secret value you pass to the chart on a Helm install/upgrade.

```sh
helm upgrade ia-node-kafka oci://ghcr.io/national-node-net/helm/ia-node-kafka -n ia-node \
  --set kafkaCluster.secret.password=ADD_YOUR_PASSWORD_HERE 
```

Verify the secret has updated by running: 

```sh
kubectl get secret kafka-ia-node-user -n ia-node -o json | jq -r '.data | with_entries(.value |= @base64d)'
```

> [!NOTE]
> The helm chart installation does take some time, so you may need to give it a few mins before verifying the secret.

#### Bring Your Own Secret

It is possible to opt for a "bring your own secret" by updating the secret name and disabling the default secret creation, but you do need to make sure that you replace "user" with the name of your intended user. 

Firstly, create two Kubernetes Secrets, the first is for setting up the Kafka user, the second uses the same information to configure the properties for the application. The names of both will be used in a later stage: 

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: user
  labels:
    strimzi.io/cluster: kafka-cluster
    strimzi.io/kind: KafkaUser
type: Opaque
stringData:
  password: somesuperawesomepassword
  sasl.jaas.config: org.apache.kafka.common.security.scram.ScramLoginModule required username="user" password="somesuperawesomepassword";
---
apiVersion: v1
kind: Secret
metadata:
  name: kafka-auth-config
  labels:
    strimzi.io/cluster: kafka-cluster
    strimzi.io/kind: KafkaUser
type: Opaque
stringData:
  kafka-config.properties: |
    security.protocol=SASL_SSL
    sasl.mechanism=SCRAM-SHA-512
    sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required \
        username="user" \
        password="somesuperawesomepassword";
```

Apply into the same namespace where the Helm chart is being deployed: 

```sh 
kubectl apply -f ./kafkaclustersecret.yaml -n ia-node
```

Lastly, override the values on the install/upgrade replacing the secret name and username to match those you created: 

```sh 
helm upgrade ia-node-kafkaCluster oci://ghcr.io/national-node-net/helm/ia-node-kafkaCluster -n ia-node \
--set kafkaCluster.secret.create=false \
--set kafkaCluster.secret.name=kafka-auth-config \
--set kafkaCluster.secret.username=user
```

## Parameters

###  Istio

| Name                          | Description                                                             | Value                           |
| ----------------------------- | ----------------------------------------------------------------------- | ------------------------------- |
| istio.annotations             | used to override default annotations on just Istio Components           | {}                              |
| istio.enabled                 | enabled by default, but used to disable Istio components                | true                            |
| istio.extraDefaults           | deploys peer authentication and deny all rules if required              | false                           |
| istio.peerAuthenticationMode  | can be set to PERMISSIVE for debugging but not recommended long term    | STRICT                          |
| istio.virtualService.enabled  | typically not required unless access is required outside of the IA Node | true                            |
| istio.virtualService.hosts    | hosts default                                                           | [ * ]                           |
| istio.virtualService.gateways | gateway reference                                                       | [ istio-system/istio-gateway  ] |

###  Kafka Spec

| Name                                | Description                   | Value         |
| ----------------------------------- | ----------------------------- | ------------- |
| kafkaCluster.name                   | default name for the resource | kafka-cluster |
| kafkaCluster.spec.version           | default version               | 3.9.0         |
| kafkaCluster.spec.kafkaReplicas     | default kafka replicas        | 3             |
| kafkaCluster.spec.zookeeperReplicas | default zookeeper replicas    | 3             |
| kafkaCluster.connectEnabled         | enables connect resources     | false         |

###  Kafka Default Secret 

| Name                                | Description                                                                  | Value                         |
| ----------------------------------- | ---------------------------------------------------------------------------- | ----------------------------- |
| kafkaCluster.secret.create          | if set the user will use a generated secret instead of the value provided    | true                          |
| kafkaCluster.secret.name            | the default secret name for setting up the configuration for the application | kafka-auth-config             |
| kafkaCluster.secret.username        | the default secret password for the user, that has to match the username     | kafka-ia-node-user            |
| kafkaCluster.secret.password        | the default value used in absence of overriding the password                 | supersecretpassword           |
| kafkaCluster.secret.usernameConnect | the default secret password for the user, that has to match the username     | kafka-connect-ia-node-user    |
| kafkaCluster.secret.passwordConnect | the default value used in absence of overriding the password                 | supersecretpasswordforconnect |

## References

- [Kubernetes Cluster](https://kubernetes.io/)
- [Helm](https://helm.sh/)
- [Formatting and Query Tooling (jq)](https://jqlang.org/)
- [Istio Helm chart, Gateway, Base and Istiod 1.25.0+](https://istio.io/latest/docs/setup/install/helm/)
- [Apache Kafka](https://kafka.apache.org/)
- [Kafka Strimzi Operator](https://artifacthub.io/packages/helm/strimzi-kafka-operator/strimzi-kafka-operator)
- [Kafka Strimzi Operator Helm charts](https://github.com/strimzi/strimzi-kafka-operator/blob/main/helm-charts/helm3/strimzi-kafka-operator/README.md). 

## Development and Testing

You can run the charts from the repository code directly if you plan to develop and test new updates to the charts. 

1. Clone the repository
2. If required add an `overrides.yaml` into the root directory of the chart (overrides.yaml is purposefully ignored on commit by `.gitignore`)
3. Set a terminal to run from the root directory of the repository
4. Then run either commands below depending on if you are working with overrides

```sh
helm install ia-node-kafka ./charts/ia-node-kafka -n ia-node -f ./charts/ia-node-kafka/values.yaml
```

```sh
helm install ia-node-kafka ./charts/ia-node-kafka -n ia-node -f ./charts/ia-node-kafka/values.yaml -f ./charts/ia-node-kafka/overrides.yaml 
```

## Public Funding Acknowledgment  
This repository has been developed with public funding as part of the National Digital Twin Programme (NDTP), a UK Government initiative. NDTP, alongside its partners, has invested in this work to advance open, secure, and reusable digital twin technologies for any organisation, whether from the public or private sector, irrespective of size.  

## License  
This repository contains both source code and documentation, which are covered by different licenses:  
- **Code:** Originally developed by **Telicent Ltd.**, now maintained by **National Digital Twin
Programme**. Licensed under the [Apache License 2.0](./LICENSE.md).  
- **Documentation:** Licensed under the [Open Government Licence v3.0](./OGL_LICENSE.md).  
See [`LICENSE.md`](./LICENSE.md), [`OGL_LICENSE.md`](./OGL_LICENSE.md), and [`NOTICE.md`](./NOTICE.md) for details.    

## Security and Responsible Disclosure  
We take security seriously. If you believe you have found a security vulnerability in this repository, please follow our responsible disclosure process outlined in [`SECURITY.md`](./SECURITY.md).  

## Contributing  
We welcome contributions that align with the Programme’s objectives. Please read our [`CONTRIBUTING.md`](./CONTRIBUTING.md) guidelines before submitting pull requests.  

## Acknowledgements  
This repository has benefited from collaboration with various organisations. For a list of acknowledgments, see [`ACKNOWLEDGEMENTS.md`](./ACKNOWLEDGEMENTS.md).  

## Support and Contact  
For questions or support, check our Issues or contact the NDTP team on ndtp@businessandtrade.gov.uk.

**Maintained by the National Digital Twin Programme (NDTP).**  

© Crown Copyright 2026. This work has been developed by the National Digital Twin Programme and is legally attributed to the UK's Department for Business, Innovation, Science and Trade (BIST) as the governing entity
