# ia-node-mongodb

**Repository:** `[helm-charts]`  
**Helm-Chart-Name:** `[ia-node-mongodb]`  
**Description:** `[National Digital Twin Programme Helm chart for MongoDB, a helper package to support deployment of the IA Node]`  
**SPDX-License-Identifier:** `Apache-2.0 AND OGL-UK-3.0 `  

## Overview  

The Helm chart `ia-node-mongdb` is intended to ease deployment and configuration of MongoDB which is a prerequisite required to deploy an IA Node (Integration Architecture Node). 

MongoDB is a general-purpose document database, the helper package `ia-node-mongdb` intends to ease first time deployments for testing. 

[Overview of MongoDB](https://www.mongodb.com/)

This chart has been developed to provide a simple example for deploying a MongoDB using the [MongoDB Kubernetes Operator](https://www.mongodb.com/try/download/community-kubernetes-operator) for use specifically with the IA Node. 

> [!IMPORTANT]  
> Secret management is outside of the scope of the deployment, however we have provided a few possible examples on how you might override the default values or provide your own where supported.

## TL;DR

> [!IMPORTANT]  
> The installation assumes that Istio has already been installed Istio, following the [Istio Helm Install](https://istio.io/latest/docs/setup/install/helm/) guide, and assumes a default principal of `cluster.local/ns/istio-system/sa/ingressgateway`, and default gateway of `istio-system/istio-gateway`. 

```sh
helm install my-release oci://ghcr.io/national-node-net/helm/ia-node-mongodb -n ia-node
```

Optionally, use an overrides.yaml:

```sh
helm install my-release oci://ghcr.io/national-node-net/helm/ia-node-mongodb -n ia-node -f ./overrides.yaml 
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
  - [`MongoDB Community Operator Helm chart 0.12.0+`](https://www.mongodb.com/try/download/community-kubernetes-operator): offers full control over MongoDB deployments from a single Kubernetes control plane

## Installing the Chart

Add the [MongoDB Helm charts for Kubernetes](https://mongodb.github.io/helm-charts/) repository to Helmfirst.

```sh
helm repo add mongodb https://mongodb.github.io/helm-charts
```

Run the following to install the operator. Ensure the operator 'watchNamespace' is set to either all or specific target namespace where you intend to deploy the MongoDB instance. 

```sh
helm install community-operator mongodb/community-operator --namespace mongodb-operator --create-namespace --set operator.watchNamespace="*"
```

Create the target namespace if it does not already exist, typically this will be the same namespace as the core IA Node application. 

```sh
kubectl create namespace ia-node
```

If running Istio in side car mode, remember to add the injection label: 

```sh
kubectl label namespace ia-node istio-injection=enabled
```

Install the latest chart:  

```sh
helm install ia-node-mongodb oci://ghcr.io/national-node-net/helm/ia-node-mongodb -n ia-node
```

Optionally, use an overrides.yaml:

```sh
helm install ia-node-mongodb oci://ghcr.io/national-node-net/helm/ia-node-mongodb -n ia-node -f ./overrides.yaml 
```

To quickly view the database running, setup a port forward.

```sh
kubectl port-forward -n ia-node svc/mongodb-svc 27017:27017
```

If you already have the mongodb shell installed you can then run a quick check i.e. `mongosh "mongodb://localhost:27017/access"` to verify the database exits. 

## Uninstall the Chart

To uninstall the Helm chart:

```sh
helm uninstall ia-node-mongodb -n ia-node
```

To uninstall the MongoDB operator:

```sh
helm install community-operator -n mongodb-operator
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
helm upgrade ia-node-mongodb oci://ghcr.io/national-node-net/helm/ia-node-mongodb -n ia-node \
  --set mongodb.secret.password=ADD_YOUR_PASSWORD_HERE 
```

Verify the secret has updated by running: 

```sh
kubectl get secret ia-node-user-password -n ia-node -o json | jq -r '.data | with_entries(.value |= @base64d)'
```

#### Bring Your Own Secret

It is possible to opt for a "bring your own secret" by updating the secret name and disabling the default secret creation, but you do need to make sure that you replace "user" with the name of your intended user. 

Firstly, create a Kubernetes Secret, the name will be used in a later stage: 

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: user-password
type: Opaque
stringData:
  password: somesuperawesomepassword
```

Apply into the same namespace where the Helm chart is being deployed: 

```sh 
kubectl apply -f ./mongdbsecret.yaml -n ia-node
```

Lastly, override the values on the install/upgrade: 

```sh 
helm upgrade ia-node-mongodb oci://ghcr.io/national-node-net/helm/ia-node-mongodb -n ia-node \
--set mongodb.secret.create=false \
--set mongodb.secret.name=user-password
```

## Parameters

###  Istio

| Name                          | Description                                                             | Value                                      |
|-------------------------------|-------------------------------------------------------------------------|--------------------------------------------|
| istio.annotations             | used to override default annotations on just Istio Components           | {}                                         |
| istio.enabled                 | enabled by default, but used to disable Istio components                | true                                       |
| istio.extraDefaults           | deploys peer authentication and auth deny rules when different namespace| false                                      |
| istio.principals              | used for auth policy and defaults to the access api service account     | [ cluster.local/ns/ia-node/sa/access-api ] |
| istio.peerAuthenticationMode  | can be set to PERMISSIVE for debugging but not recommended long term    | STRICT                                     |
| istio.virtualService.enabled  | typically not required unless access is required outside of the IA Node | false                                      |
| istio.virtualService.hosts    | hosts default                                                           | [ * ]                                      |
| istio.virtualService.gateways | gateway reference                                                       | [ istio-system/istio-gateway  ]            |

###  MongoDB Spec

| Name                 | Description                              | Value   |
|----------------------|------------------------------------------|---------|
| mongodb.name         | default name for the resource            | mongodb |
| mongodb.spec.members | default members should be no less than 3 | 3       |
| mongodb.spec.version | default version                          | "6.0.5" |

###  MongoDB TLS 
(default off for Istio)

| Name                                              | Description                                                        | Value           |
|---------------------------------------------------|--------------------------------------------------------------------|-----------------|
| mongodb.spec.security.tls.enabled                 | used to toggle tls                                                 | false           |
| mongodb.spec.security.tls.useX509                 | used to toggle if to use X509 certificate                          | false           |
| mongodb.spec.security.tls.certificateKeySecretRef | can be used to provider a certificate secret reference for the Key | tls-certificate |
| mongodb.spec.security.tls.caCertificateSecretRef  | can be used to provider a certificate secret reference for the CA  | tls-ca-key-pair |

###  MongoDB Default Secret

| Name                                | Description                                                                                      | Value                   |
|-------------------------------------|--------------------------------------------------------------------------------------------------|-------------------------|
| mongodb.secret.create               | option to create secret or not                                                                   | true                    |
| mongodb.secret.name                 | secret name, and also the name of the reference when specifying alternative secret               | "ia-node-user-password" |
| mongodb.secret.providerClassEnabled | enables secret provider class to be deployed                                                     | false                   |
| mongodb.secret.provider             | required for the provider class, when not set to default the regular secret creation is disabled | default                 |
| mongodb.secret.objectName           | required for the provider class                                                                  | default                 |
| mongodb.secret.objectType           | required for the provider class                                                                  | default                 |
| mongodb.secret.password             | the default value used in absence of overriding the password                                     | supersecretpassword     |

###  MongoDB Default User

| Name                        | Description                    | Value                                                                                                                                                      |
|-----------------------------|--------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| mongodb.users.default.name  | name of default user           | a-node-user                                                                                                                                                |
| mongodb.users.default.db    | database name for default user | access                                                                                                                                                     |
| mongodb.users.default.roles | default user roles             | [ clusterAdmin, userAdminAnyDatabase, backup, dbAdminAnyDatabase, restore, MongodbAutomationAgentUserRole, readWriteAnyDatabase, enableSharding, dbOwner ] |

## References

- [Kubernetes Cluster](https://kubernetes.io/)
- [Helm](https://helm.sh/)
- [Formatting and Query Tooling (jq)](https://jqlang.org/)
- [Istio Helm chart, Gateway, Base and Istiod 1.25.0+](https://istio.io/latest/docs/setup/install/helm/)
- [MongoDB](https://www.mongodb.com/)
- [MongoDB Kubernetes Operator](https://www.mongodb.com/try/download/community-kubernetes-operator)
- [MongoDB Helm charts for Kubernetes](https://mongodb.github.io/helm-charts/)

## Development and Testing

You can run the charts from the repository code directly if you plan to develop and test new updates to the charts. 

1. Clone the repository
2. If required add an `overrides.yaml` into the root directory of the chart (overrides.yaml is purposefully ignored on commit by `.gitignore`)
3. Set a terminal to run from the root directory of the repository
4. Then run either commands below depending on if you are working with overrides

```sh 
helm install ia-node-mongodb ./charts/ia-node-mongodb -n ia-node -f ./charts/ia-node-mongodb/values.yaml
```

```sh 
helm install ia-node-mongodb ./charts/ia-node-mongodb -n ia-node -f ./charts/ia-node-mongodb/values.yaml -f ./charts/ia-node-mongodb/overrides.yaml 
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

© Crown Copyright 2026. This work has been developed by the National Digital Twin Programme and is legally attributed to the UK's Department for Business, Innovation, Science and Trade (BIST) as the governing entity.
