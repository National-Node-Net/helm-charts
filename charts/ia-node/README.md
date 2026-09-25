# ia-node

**Repository:** `[helm-charts]`  
**Helm-Chart-Name:** `[ia-node]`  
**Description:** `[National Digital Twin Programme Helm chart for the IA Node]`  
**SPDX-License-Identifier:** `Apache-2.0 AND OGL-UK-3.0 `  

## Overview  

The Helm chart `ia-node` is intended to deploy the basic IA Node application components.

IA Node (Integration Architecture Node), is an open-source digital component developed as part of the National Digital Twin Programme (NDTP) to support managing and sharing information across organisations, the package `ia-node` intends to ease first time deployments for testing. 

[Overview of IA Node](https://github.com/National-Node-Net/integration-architecture-documentation)

> [!IMPORTANT]  
> Secrets management is outside of the scope of the deployment, however, we have provided a few possible examples on how you might override the default values or provide your own where supported.

## TL;DR

> [!IMPORTANT]  
> The installation assumes that Istio has already been installed Istio, following the [Istio Helm Install](https://istio.io/latest/docs/setup/install/helm/) guide, and assumes a default principal of `cluster.local/ns/istio-system/sa/ingressgateway`, and default gateway of `istio-system/istio-gateway`. It is also assumed that you have Istio installed and you have configured an Istio gateway using the default setup and then in addition configured a mesh config or envoy filter to handle the redirection of OAuth2 Proxy, configured with an OIDC provider. In addition you should also have a MongoDB and Kafka installation which is assumed for the default install i.e. `mongodb-svc:27017` and `kafka-cluster-kafka-bootstrap.ia-node-kafka.svc:9093` respectively using secret names of `ia-node-user-password` and `kafka-auth-config` respectively. These can all be overridden in the values as required, along with any other requirements if you are hosting these services externally. 

```sh
helm install my-release oci://ghcr.io/national-node-net/helm/ia-node -n ia-node \
--set apps.api.configMap.data.DEPLOYED_DOMAIN="http://localhost" \
--set apps.api.configMap.data.OPENID_PROVIDER_URL="http://keycloak.keycloak.svc.cluster.local/realms/ianode/" \
--set apps.graph.configMap.data.JWKS_URL="http://keycloak.keycloak.svc.cluster.local/realms/ianode/.well-known/openid-configuration" \
--set istio.virtualService.hosts[0]="localhost"
```

Optionally, use an overrides.yaml:

```sh
helm install my-release oci://ghcr.io/national-node-net/helm/ia-node -n ia-node -f ./overrides.yaml 
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
  - 
- **Application Installation Requirements:** 
  - [Istio Helm chart, Gateway, Base and Istiod 1.25.0+](https://istio.io/latest/docs/setup/install/helm/): service mesh that layers onto existing application, providing uniform and more efficient ways to secure, connect, and monitor services
  - `OpenID Connect (OIDC) Identity Provider:` the application requires that authentication is performed by the service mesh using an OIDC authentication flow and that all paths exposed on the domain should be authenticated, this install was tested with [`Keycloak`](https://www.keycloak.org/) using [`Bitnami Keycloak Helm chart 24.4.13`](https://github.com/bitnami/charts/blob/main/bitnami/keycloak/README.md) which, also installs [`PostgreSQL`](https://www.postgresql.org/).
  - [`oAuth2Proxy`](https://oauth2-proxy.github.io/oauth2-proxy/): a reverse proxy that should be deployed and integrated with Istio service mesh to provide authentication using a target OpenID Connect (OIDC) Identity Provider, this install used [`Bitnami oAuth2 Proxy Helm chart 6.2.10`](https://github.com/bitnami/charts/blob/main/bitnami/oauth2-proxy/README.md), which also installs [`Redis`](https://redis.io/) a session storage option that can be used with oAuth2Proxy
  - [`MongoDB`](https://www.mongodb.com/): for application data storage, this install was tested with the [`MongoDB Community Operator Helm chart 0.12.0+`](https://www.mongodb.com/try/download/community-kubernetes-operator)
  - [`Apache Kafka`](https://kafka.apache.org/): for application data streaming, this install was tested with the [`Kafka Strimzi Operator 0.45.0+`](https://artifacthub.io/packages/helm/strimzi-kafka-operator/strimzi-kafka-operator)

## Installing the Chart

Create the target namespace if it does not already exist. 

```sh
kubectl create namespace ia-node
```

If running Istio in side car mode, remember to add the injection label. 

```sh
kubectl label namespace ia-node istio-injection=enabled
```


Install the latest chart using the following:  

```sh
helm install ia-node oci://ghcr.io/national-node-net/helm/ia-node -n ia-node \
--set apps.api.configMap.data.DEPLOYED_DOMAIN="http://localhost" \
--set apps.api.configMap.data.OPENID_PROVIDER_URL="http://keycloak.keycloak.svc.cluster.local/realms/ianode/" \
--set apps.graph.configMap.data.JWKS_URL="http://keycloak.keycloak.svc.cluster.local/realms/ianode/.well-known/openid-configuration" \
--set istio.virtualService.hosts[0]="localhost"
```

Optionally, use an overrides.yaml:

```sh
helm install ia-node oci://ghcr.io/national-node-net/helm/ia-node -n ia-node -f ./overrides.yaml 
```

## Uninstall the Chart

To uninstall the chart:

```sh
helm uninstall ia-node -n ia-node
```

## Configuration and Installation details

### Istio 

Any Istio examples throughout this documentation are provided largely as information to help support integrators to plan their own deployment.  

> [!IMPORTANT]  
> The installation assumes that Istio has already been installed Istio, following the [Istio Helm Install](https://istio.io/latest/docs/setup/install/helm/) guide, and assumes a default principal of `cluster.local/ns/istio-system/sa/ingressgateway`, and default gateway of `istio-system/istio-gateway`. You will require a [gateway](https://istio.io/latest/docs/reference/config/networking/gateway/) and a domain, listening on HTTPS port (443), presenting a valid TLS certificate and either the [Global Mesh](https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/) options or an [Envoy Filter](https://istio.io/latest/docs/reference/config/networking/envoy-filter/) to initiate the OIDC flow. 

> [!NOTE]
> Authorization policies are implemented to restrict communications between components, the principals are based on the namespace a service is deployed to and the service account it runs as, some of these may differ for your environment if you are not using the defaults but can be overridden using the Helm values.

### OIDC Provider

Istio should be integrated with an OIDC conformant Identity Provider (IdP) e.g. Keycloak, Cognito etc. and it requires to be configured with users, clients and groups. The application requires that authentication is performed by the service mesh using an OIDC authentication flow and that all paths exposed on the domain should be authenticated. The OIDC token that describes the result of a successful authentication is passed in a HTTP header upstream from the Istio ingress upstream to the service and any subsequent service to service calls. The OIDC Token is a [JSON web token](https://jwt.io/) that represents the result of OIDC authentication flow, the payload content should, contain similar to the example below.

```
{
  "iss": "https://localhost-oidc",
  "email": "yourEmail",
  "email_verified": true,
  "groups": [
    "ianode_read",
    "ianode_admin",
    "ianode_write"
  ]
}
```

### Environmental Configuration

You will need to replace details for environment for each of the application dependencies. One approach is to create your an `overrides.yaml` with the values to suit your environment setup requirements, rather than doing this using the `--set` on commandline. 

We have provided some minimal examples of the configurations that you will most likely require to change, although a full set can be found in the parameters section. 

#### Example Config Override Access API

```yaml
apps:
  api:
    configMap:
      data:
        DEPLOYED_DOMAIN: https://localhost
        OPENID_PROVIDER_URL: http://keycloak.keycloak.svc.cluster.local/realms/ianode
```

#### Example Config Override Access UI
  
```yaml
apps:
  ui:
    configMap:
      data:
        env-config.js: "window.ACCESS_API_URL = \"https://localhost/api/access\"\r\n"
```

#### Example Config Override Secure Agent Graph
 
```yaml
apps:
  graph:
    configMap:
      data:
        JWKS_URL: http://keycloak.keycloak.svc.cluster.local/realms/ianode/.well-known/openid-configuration

 ```
 
#### Example Config Override Query UI 
	
```yaml
apps:
  query:
    graph:
      configMap:
        data:
      env-config.js: "window.GRAPHQL_URL = \"https://localhost/api/sparql/knowledge/graphql\";\r\nwindow.BETA= \"true\";\r\nwindow.SPARQL_URL = \"https://localhost/api/sparql/knowledge/sparql\";\r\nwindow.ACCESS_URL= \"https://localhost/api/access\";\r\n"
 ```
### Fuseki Config

There is a default Fuseki `config.ttl` that is deployed as a config map with this package as an example. However the creation can be turned off if you wish to create your own in advance of installing the Helm chart. 

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: graph-server-fuseki
data:
  config.ttl: |-
    [ add your own config details ]
 ```

### Secret Management

This chart provides a few options for managing the default secrets. 

#### Override the Value 

Override the secret value you pass to the chart with a Helm install/upgrade. 

```sh
helm upgrade ia-node oci://ghcr.io/national-node-net/helm/ia-node -n ia-node --set mongodb.secret.password=ADD_YOUR_PASSWORD_HERE 
```

Verify the default is now configured by running: 

```sh
kubectl get secret  ia-node-user-password   -n ia-node -o json | jq -r '.data | with_entries(.value |= @base64d)'
```

Similar can be done for any of the other secrets generated by this package. 

#### Bring Your Own Secret

It is possible to opt for a "bring your own secret" by updating the secret name and disabling the default creation. 

Firstly, a secret is required:  

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: bring-your-own-mongdb-secret-reference
type: Opaque
stringData:
  password: somesuperawesomepassword
```

Apply into the same namespace where the Helm chart is being deployed:

```sh
kubectl apply -f ./mongdbsecret.yaml -n ia-node
```

Lastly override the values on the install/upgrade as below. 

```sh
helm upgrade ia-node oci://ghcr.io/national-node-net/helm/ia-node -n ia-node \
--set mongodb.secret.create=false \
--set mongodb.secret.name=bring-your-own-mongdb-secret-reference
```

Similar can be done for any of the other secrets generated by this package. 

#### Additional Certificates

In some environments you may need add certificate information into the services. For example if you are not using something like cert manager to manage certificates or you are hosting the main application on `mysubdomain.domain.dev` and your OIDC provider or database is being hosted on a different subdomain `myoidc-subdomain.domain.dev`. 

This can be done by creating an additional config map and applying all the required certs similar to that below.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: root-certs
data:
  root-ca.pem: |
    -----BEGIN CERTIFICATE-----
    ADD CERT INFORMATION HERE
    -----END CERTIFICATE-----
```

Then apply this into the same namespace.

```sh
kubectl apply -f ./rootcerts.yaml -n ia-node
```

And add the following overrides values: 

```yaml
extraCerts: 
  required: true
  name: root-ca.pem
```

#### Referencing Alternative or Private Registries for Images

All images are all published to a the National Digital Twin Programme GitHub Registry see [here](https://github.com/orgs/National-Node-Net/packages?ecosystem=container). 

Some teams, may wish to sync images to another registry they host or sync to a registry that is already integrated with their desired target environment cluster, however others may wish to use the private github registry directly.

This can be done using a similar approach as described [here](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/), which is what we have used as an example below. Alternatively you can also get Helmto do the heavy lifting on the generation as described [here](https://helm.sh/docs/howto/charts_tips_and_tricks/#creating-image-pull-secrets).

You will require an access token with at least "read only" access either

  -  a personal access token more suited for local use
  -  an org token / app for environment use or jobs that are shared by a team / group

Then log in to the target registry as follows. 

```sh
 docker login -u user ghcr.io/national-node-net -p $token
```

This should generate a config i.e. .docker/config.json you can view the contents using 

```
cat .docker/config.json
```

Now generate a secret using that config as follows: 

```sh
kubectl create secret generic private-registry \
--from-file=.dockerconfigjson=.docker/config.json \
--type=kubernetes.io/dockerconfigjson \
-n ia-node
```

If you can't find a config you can also do this directly 

```sh
kubectl create secret docker-registry private-registry \
--docker-server=ghcr.io/national-node-net \
--docker-username=user \
--docker-password=$token \
--docker-email=user@yourdomain \
-n ia-node
```

And then override the values as follows.

```yaml
imagePullSecrets:
- name: private-registry
```

## Parameters

###  Istio

| Name                          | Description                                                              | Value                                                 |
| ----------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------- |
| istio.annotations             | used to override default annotations on just Istio Components            | {}                                                    |
| istio.enabled                 | enabled by default, but used to disable Istio components                 | true                                                  |
| istio.extraDefaults           | deploys peer authentication and auth deny rules when different namespace | true                                                  |
| istio.principal               | used for auth policy and defaults to gateway ingress                     | cluster.local/ns/istio-system/sa/istio-ingressgateway |
| istio.peerAuthenticationMode  | can be set to PERMISSIVE for debugging but not recommended long term     | PERMISSIVE                                            |
| istio.virtualService.hosts    | hosts default, should be replaced with your domain                       | [ * ]                                                 |
| istio.virtualService.gateways | gateway reference                                                        | [ istio-system/istio-gateway  ]                       |
| istio.groupClaimNames.admin   | default admin group claim name                                           | "ianode_admin"                                        |
| istio.groupClaimNames.read    | default read group claim name                                            | "ianode_read"                                         |
| istio.groupClaimNames.write   | default write group claim name                                           | "ianode_write"                                        |

###   Extra Certs 

| Name                    | Description                                                              | Value       |
| ----------------------- | ------------------------------------------------------------------------ | ----------- |
| extraCerts.required     | can be enabled if extra certs are required mapped to NODE_EXTRA_CA_CERTS | false       |
| extraCerts.name         | name of the cert                                                         | root-ca.pem |
| extraCerts.configMapRef | name of the config map to reference to use                               | root-certs  |
 
###  Image Pull Secrets

| Name             | Description                                                                | Value |
| ---------------- | -------------------------------------------------------------------------- | ----- |
| imagePullSecrets | can be used to globally add additional pull secrets for private registries | []    |

### Fuseki Config

| Name                                   | Description                                           | Value                                                                     |
| -------------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------- |
| fusekiConfig.create                    | create config map with default config.tll             | true                                                                      |
| fusekiConfig.name                      | config map name, changes require volume mount updates | "graph-server-fuseki"                                                     |
| fusekiConfig.prefix                    | override prefix for default config.tll                | "ndtp.co.uk"                                                              |
| fusekiConfig.catalogEnabled            | enabled config.tll including catalog topic            | false                                                                     |
| fusekiConfig.cqrsEnabled               | enables CQRS (Command Query Responsibility Segregation) | true                                                                      |
| fusekiConfig.jaContext.graphqlExecutor | override graphqlExecutor for default config.tll       | "uk.gov.dbt.ndtp.jena.graphql.execution.ianode.graph.IANodeGraphExecutor" |
| fusekiConfig.jaContext.queryTimeout    | override queryTimeout  for default config.tll         | "120000,120000"                                                           |
| fusekiConfig.kafkaTopics.knowledge     | Kafka topic for knowledge data                        | "knowledge"                                                               |
| fusekiConfig.kafkaTopics.ontology      | Kafka topic for ontology data                         | "ontology"                                                                |
| fusekiConfig.cqrsTopics.knowledge      | CQRS topic for knowledge data                         | "knowledge"                                                               |
| fusekiConfig.cqrsTopics.ontology       | CQRS topic for ontology data                          | "ontology"                                                                |

###  MongoDB 

| Name                                | Description                                                                                      | Value                   |
| ----------------------------------- | ------------------------------------------------------------------------------------------------ | ----------------------- |
| mongodb.extraCerts.required         | can be enabled if extra certs are required mapped to MONGO_SSL_CERT                              | false                   |
| mongodb.extraCerts.name             | name of the cert                                                                                 | mongo-ca.pem            |
| mongodb.extraCerts.configMapRef     | name of the config map to reference to use                                                       | mongo-certs             |
| mongodb.secret.create               | option to create secret or not                                                                   | true                    |
| mongodb.secret.name                 | secret name, and the name of the reference when specifying alternative secret                    | "ia-node-user-password" |
| mongodb.secret.providerClassEnabled | enables secret provider class to be deployed                                                     | false                   |
| mongodb.secret.provider             | required for the provider class, when not set to default the regular secret creation is disabled | default                 |
| mongodb.secret.objectName           | required for the provider class                                                                  | default                 |
| mongodb.secret.objectType           | required for the provider class                                                                  | default                 |
| mongodb.secret.password             | the default value used in absence of overriding the password                                     | supersecretpassword     |

###  Kafka 

| Name                          | Description                                                                  | Value                              |
| ----------------------------- | ---------------------------------------------------------------------------- | ---------------------------------- |
| kafkaCluster.bootstrapServers | overrides the bootstrap server connection                                    | kafka-cluster-kafka-bootstrap:9093 |
| kafkaCluster.secret.create    | option to create secret or not                                               | false                              |
| kafkaCluster.secret.name      | secret name and the name of the reference when specifying alternative secret | kafka-auth-config                  |
| kafkaCluster.secret.username  | the default username                                                         | kafka-ia-node-user                 |
| kafkaCluster.secret.password  | the default value used in absence of overriding the password                 | supersecretpassword                |

###  Access Api 

| Name                                 | Description                                              | Value                                       |
| ------------------------------------ | -------------------------------------------------------- | ------------------------------------------- |
| apps.api.enabled                     | toggled the component to be deployed or not              | true                                        |
| apps.api.deployment.image.repository | default image repository                                 | ghcr.io/national-node-net/ianode-access |
| apps.api.deployment.image.tag        | default image tag                                        | 0.90.0                                      |
| apps.api.configMap.data              | config map overrides, only the ones listed are mandatory | DEPLOYED_DOMAIN, OPENID_PROVIDER_URL        |

###  Access UI

Note: currently access-ui image is not supported yet. 

| Name                                | Description                                              | Value                                   |
| ----------------------------------- | -------------------------------------------------------- | --------------------------------------- |
| apps.ui.enabled                     | toggled the component to be deployed or not              | false                                   |
| apps.ui.deployment.image.repository | default image repository                                 | ghcr.io/national-node-net/access-ui |
| apps.ui.deployment.image.tag        | default image tag                                        | latest                                  |
| apps.ui.configMap.data              | config map overrides, only the ones listed are mandatory | env-config.js                           |

###  Secure Agent Graph

| Name                                  | Description                                              | Value                                                                  |
| ------------------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------------- |
| apps.api.graph                        | toggled the component to be deployed or not              | true                                                                   |
| apps.api.statefulSet.image.repository | default image repository                                 | ghcr.io/national-node-net/secure-agent-graph                       |
| apps.api.statefulSet.image.tag        | default image tag                                        | 0.90.0                                                                 |
| apps.api.configMap.data               | config map overrides, only the ones listed are mandatory | ATTRIBUTE_HIERARCHY_URL, JWKS_URL, SEARCH_API_URL, USER_ATTRIBUTES_URL |

###  Query UI

Note: currently query-ui image is not supported yet. 

| Name                                   | Description                                              | Value                                  |
| -------------------------------------- | -------------------------------------------------------- | -------------------------------------- |
| apps.graph.enabled                     | toggled the component to be deployed or not              | false                                  |
| apps.graph.deployment.image.repository | default image repository                                 | ghcr.io/national-node-net/query-ui |
| apps.graph.deployment.image.tag        | default image tag                                        | latest                                 |
| apps.graph.configMap.data              | config map overrides, only the ones listed are mandatory | env-config.js                          |

## References

- [Kubernetes Cluster](https://kubernetes.io/)
- [Helm](https://helm.sh/)
- [Formatting and Query Tooling (jq)](https://jqlang.org/)
- [Istio Helm chart, Gateway, Base and Istiod 1.25.0+](https://istio.io/latest/docs/setup/install/helm/)
- [MongoDB](https://www.mongodb.com/)
- [Apache Kafka](https://kafka.apache.org/)

## Development and Testing

You can run the charts from the repository code directly if you plan to develop and test new updates to the charts. 

1. Clone the repository
2. If required add an `overrides.yaml` into the root directory of the chart (overrides.yaml is purposefully ignored on commit by `.gitignore`)
3. Set a terminal to run from the root directory of the repository
4. Then run either commands below depending on if you are working with overrides

```sh
helm install ia-node ./charts/ia-node -n ia-node -f ./charts/ia-node/values.yaml \
--set apps.api.configMap.data.DEPLOYED_DOMAIN="http://localhost" \
--set apps.api.configMap.data.OPENID_PROVIDER_URL="http://keycloak.keycloak.svc.cluster.local/realms/ianode/" \
--set apps.graph.configMap.data.JWKS_URL="http://keycloak.keycloak.svc.cluster.local/realms/ianode/.well-known/openid-configuration" \
--set istio.virtualService.hosts[0]="localhost"
```

```sh
helm install ia-node ./charts/ia-node -n ia-node -f ./charts/ia-node/values.yaml -f ./charts/ia-node/overrides.yaml 
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
