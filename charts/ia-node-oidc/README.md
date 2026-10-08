# ia-node-oidc

**Repository:** `[helm-charts]`  
**Helm-Chart-Name:** `[ia-node-oidc]`  
**Description:** `[National Digital Twin Programme Helm chart for OIDC, a helper package to support deployment of the IA Node]`  
**SPDX-License-Identifier:** `Apache-2.0 AND OGL-UK-3.0 `  

## Overview  

The Helm chart `ia-node-oidc` is intended to ease deployment and configuration of an OIDC conformant Identity Provider (IdP) [Keycloak](https://www.keycloak.org/), with with [PostgreSQL](https://www.postgresql.org/), integrated with Istio, [oAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/) and [Redis](https://redis.io/), which are prerequisites required to deploy an IA Node (Integration Architecture Node). 

If you have not already deployed an OIDC provider, this document also offers some guidance regarding a basic example install and setup of oAuth2 Proxy, a reverse proxy and static file server that provides authentication for use with OIDC providers for validating email a group claims. The example in this setup uses Keycloak as the provider.

[Overview of oAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/)

[Overview of Keycloak](https://www.keycloak.org/)

[Overview of Redis](https://redis.io/)

[Overview of PostgreSQL](https://www.postgresql.org)

This chart has been developed to provide an example for deploying oAuth2 Proxy, Keycloak and Redis, for use specifically with the IA Node. 

> [!IMPORTANT]  
> Secret management is outside of the scope of the deployment, however we have provided a few possible examples on how you might override the default values or provide your own where supported.

## TL;DR

> [!IMPORTANT]  
> The installation assumes that Istio has already been installed Istio, following the [Istio Helm Install](https://istio.io/latest/docs/setup/install/helm/) guide, and assumes a default principal of `cluster.local/ns/istio-system/sa/ingressgateway`, and default gateway of `istio-system/istio-gateway`. It is also assumed you have Istio installed and you have configured an Istio gateway using the default setup and then in addition configured a mesh config or envoy filter to handle the redirection of oAuth2 Proxy. In addition you should also have a keycloak installation which is assumed for the default install, to be on your cluster ie. `http://keycloak.keycloak.svc.cluster.local` with a realm, test users, client and groups. 

> [!NOTE]  
> You can either generate a secret called `oauth2-proxy-default` yourself, or secret creation to true as below with your [cookie secret](https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview/) and keycloak client id and secret which will generate a secret for you. The config map and optional secret output from the package, can then be used to override the oauth2 Proxy installation. 

```sh
helm install ia-node-oidc oci://ghcr.io/national-node-net/helm/ia-node-oidc -n ia-node --set oidcProvider.configMap.redirect_url=https://localhost/oauth2/callback --set istio.virtualService.hosts[0]="localhost"
```

Optionally, use an overrides.yaml:

```sh
helm install my-release oci://ghcr.io/national-node-net/helm/ia-node-oidc -n ia-node -f ./overrides.yaml 
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
  - `OpenID Connect (OIDC) Identity Provider:` the application requires that authentication is performed by the service mesh using an OIDC authentication flow and that all paths exposed on the domain should be authenticated, this install was tested with [Keycloak](https://www.keycloak.org/) using [`Bitnami Keycloak Helm chart 24.4.13`](https://github.com/bitnami/charts/blob/main/bitnami/keycloak/README.md) which, also installs [PostgreSQL](https://www.postgresql.org/).
  - [`oAuth2Proxy`](https://oauth2-proxy.github.io/oauth2-proxy/): a reverse proxy that should be deployed and integrated with Istio service mesh to provide authentication using a target OpenID Connect (OIDC) Identity Provider, this install used [`Bitnami oAuth2 Proxy Helm chart 6.2.10`](https://github.com/bitnami/charts/blob/main/bitnami/oauth2-proxy/README.md), which also installs [`Redis`](https://redis.io/) a session storage option that can be used with oAuth2Proxy

> [!NOTE]
> The application itself has also been tested with Cognito in place of Keycloak [see here](https://github.com/National-Node-Net/integration-architecture-documentation/blob/main/DeveloperDocumentation/Deployment/deployment-local.md). 
  
## Installing the Chart

Before you can install the chart, you will need to make sure you have configured an OIDC provider with users, clients and groups some further guidance on how this can be done is captured under the configuration sections. 

Create the target namespace if it does not already exist, typically this will be the same namespace as the core IA Node application. 

```sh
kubectl create namespace ia-node
```

If running Istio in side car mode, remember to add the injection label. 

```sh
kubectl label namespace ia-node istio-injection=enabled
```

Install the latest chart using the following.  

```sh
helm install ia-node-oidc oci://ghcr.io/national-node-net/helm/ia-node-oidc -n ia-node --set oidcProvider.configMap.redirect_url=https://localhost/oauth2/callback
```

Optionally, use an overrides.yaml:

```sh
helm install ia-node-oidc oci://ghcr.io/national-node-net/helm/ia-node-oidc -n ia-node-oidc -f ./overrides.yaml 
```

Next install oAuth2Proxy, the example below uses the [Bitnami oAuth2 Proxy Helm chart](https://github.com/bitnami/charts/blob/main/bitnami/oauth2-proxy/README.md), however [oAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/installation) do provide a Helm chart option directly from the core documentation. 

You can quickly install a oAuth2Proxy to the same namespace as the main package using the following. 

```sh
helm install oauth2-proxy oci://registry-1.docker.io/bitnamicharts/oauth2-proxy -n ia-node --set istio.virtualService.hosts[0]="localhost"
```

The helper package `ia-node-oidc` itself can be used to generate a config map and secret which can be passed into the oAuth2Proxy install, these provide some basic defaults for a keycloak setup. 

```sh
helm install oauth2-proxy oci://registry-1.docker.io/bitnamicharts/oauth2-proxy -n ia-node --set configuration.existingSecret="oauth2-proxy-default" --set configuration.existingConfigmap="oauth2-proxy-default" --set istio.virtualService.hosts[0]="localhost"
```

## Uninstall the Chart

To uninstall the Helm chart:

```sh
helm uninstall ia-node-oidc -n ia-node
```

If you require to uninstall key cloak that can be also done as follows. 

```sh
helm uninstall keycloak -n keycloak 
```

If you require to uninstall oAuth2 Proxy that can be also done as follows. 

```sh
helm uninstall oauth2-proxy -n ia-node
```

## Configuration and Installation details

###  Istio

Any Istio examples throughout this documentation are provided largely as information to help support integrators to plan their own deployment.

The installation assumes that Istio has already been installed Istio, following the [Istio Helm Install](https://istio.io/latest/docs/setup/install/helm/) guide, and assumes a default principal of `cluster.local/ns/istio-system/sa/ingressgateway`, and default gateway of `istio-system/istio-gateway`.   

This chart provides just a basic Istio configuration to support the setup of oAuth2 Proxy using Key Cloak as an example OIDC provider, as we want traffic to redirect to the OIDC provider via oAuth2 Proxy if a token is invalid or does not exist. However Istio will still require to be configured to handle this redirection. An external authorizer can be applied, either globally using the `mesh config` as part of the Istio installation or by applying an `envoy filter`. 

The following is an example of a possible, mesh config that could be applied. See more information [here](https://istio.io/latest/docs/tasks/security/authorization/authz-custom/). 

```yaml
    meshConfig:
      extensionProviders:
      - envoyExtAuthzHttp:
          headersToDownstreamOnDeny:
          - set-cookie
          - content-type
          headersToUpstreamOnAllow:
          - authorization
          - path
          - x-auth-request-access-token
          - x-forwarded-client-cert
          - x-auth-request-user
          - x-auth-request-email
          includeHeadersInCheck:
          - authorization
          - cookie
          port: 80
          service: oauth2-proxy.ia-node.svc.cluster.local
        name: oauth2-authz
```


> [!NOTE]
> Istio `authorization policies` are implemented to restrict communications between components. These principals are based on the namespace a service is deployed to and the service account it runs as. In particular, the principal that the Istio ingress is assigned is environment specific and may differ from the one specified in the default deployment. These can all be overridden using the Helm values. 

### OIDC Provider 

The application requires that authentication is performed by the service mesh as outlined above, using an OIDC authentication flow and that all paths exposed on the domain should be authenticated.

The OIDC token that describes the result of a successful authentication is passed in a HTTP header upstream from the Istio ingress upstream to the service and any subsequent service to service calls. The OIDC Token is a [JSON web token](https://jwt.io/) that represents the result of OIDC authentication flow.

It passes between services as a HTTP header. The format being: 

```sh
Authorization: Bearer <BASE 64 ENCODED JWT>
```

> [!NOTE]  
> Note: Use of this header is a de-facto standard and the key (`Authorization`) and prefix (`Bearer `) are both configurable in [Istio](https://istio.io/latest/docs/reference/config/security/request_authentication/#JWTHeader-prefix) and the services.

You can inspect the payload of a generated token using something similar to the command below. 

```sh
echo $token | cut -d '.' -f 2 | base64 -d | jq .
```

The payload content should contain email and groups, as shown in the example below:

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

There are some examples of Cognito covered in the [documents repository](https://github.com/National-Node-Net/integration-architecture-documentation/blob/main/DeveloperDocumentation/Deployment/deployment-local.md).

The rest of this section is to provide a bit of a quick guide example for a basic Key Cloak configuration. 

#### Key Cloak

Its possibly you are using a realm within an existing Key Cloak and can just skip to the section around configuring the components in the realm, however if that is not the case, you this will provide a really basic install. 

Create a new namespace. 

```sh
kubectl create namespace keycloak
kubectl label namespace keycloak istio-injection=enabled
```

Using the [Bitnami Keycloak Helm chart](https://github.com/bitnami/charts/blob/main/bitnami/keycloak/README.md), you can quickly install a key cloak example to your namespace. 

```sh
helm install keycloak oci://registry-1.docker.io/bitnamicharts/keycloak -n keycloak 
```

The default setup with create an account with `user` and generate a password, which can be obtained by running the following:

```sh
kubectl -n keycloak get secret keycloak -o jsonpath='{.data.admin-password}' | base64 -d && echo
```
To quickly view the application running, setup a port forward.

```sh
kubectl port-forward --namespace keycloak svc/keycloak 8080:80
```

Create a virtual service (similar to that below). 

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: keycloak
  namespace: keycloak
spec:
  hosts:
  - '*'
  gateways:
  - istio-system/ingress-gateway # assuming use of a common gateway, however its possible this maybe not the case
  http:
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: keycloak.keycloak.svc.cluster.local  # should be the fully qualified service name
        port:
          number: 80
```

#### Realm, Users, Groups and Client Configuration(s)

The following are some high level steps you will require for setting integration. 

- create a new admin and remove the default install one
- create a new realm that represents the application i.e. ia-node
- create at least one regular test user with a valid email
- setup groups required by the `ianode` i.e. ianode_admin, ianode_read, ianode_write either by
	- creating realm roles that represent the groups 
	- directly creating groups that represent each group 
- add the relevant roles and groups to the required users
- create a client scope called "groups", with a mapper for either "realm roles" or "group membership" depending on which you configured node that group membership uses paths so you will have "/groupname" for a parent group, which will be relevant when matching the claims
- create client(s) one with basic setup and one with a client id/secret setup and add groups to be included in the claims

> [!NOTE]  
> Note: The example realm [keycloak-realm.json](./config/keycloak-realm.json), can be imported as a reference/starting point. This example includes example clients and a group client scope thgat maps both group membership and realm roles mappers, however only one of these options are required. 

You should replace the client ids with your own generated client id after import and regenerate any client secrets.

#### Verify JWT with UI Client

Set the following variables. 

```sh
client_id="yourUIClient" ## `5461f43e-57e1-4e1b-a3e4-4947596e5d04` is the example from keycloak-realm.json
client_secret="yourUISecret" ## `4qaUP8ETjxdON2pQLSzHzLCgfISZ1a93` is the example from keycloak-realm.json
domain="https://locahost-oidc" 
realm="ianode" ## `ianode` is the example from keycloak-realm.json
```

Then run the following to generate the token. 

```sh
token=$(curl --silent --request POST --url "https://$domain/realms/$realm/protocol/openid-connect/token" --header "Content-Type: application/x-www-form-urlencoded" --data-urlencode "client_id=$client_id" --data-urlencode "client_secret=$client_secret" --data-urlencode "grant_type=client_credentials" | jq .access_token)
```

Inspect the results to verify the groups appear in the claims as you would expect

```sh
echo $token | cut -d '.' -f 2 | base64 -d 
```

For querying and formatting you can use [`jq 1.6+`](https://jqlang.org/): 

```sh
echo $token | cut -d '.' -f 2 | base64 -d | jq .
```

#### Verify JWT with API Client

Set the following variables. 

```sh
password=yourKeyCloakPassword
username=yourKeyCloakEmail
client_id=yourAPIClient ## `079ff956-38c6-46f4-a03c-acc09addd173` is the example from keycloak-realm.json
domain="https://locahost-oidc"
realm="yourRealm" ## `ianode` is the example from keycloak-realm.json
```

Then run the following to generate the token. 

```sh
token=$(curl --silent --request POST --url "https://$domain/realms/$realm/protocol/openid-connect/token" --header "Content-Type: application/x-www-form-urlencoded" --data-urlencode "client_id=$client_id" --data-urlencode  "username=$username" --data-urlencode  "password=$password" --data-urlencode  "grant_type=password" | jq .access_token)
```

Inspect the results to verify the groups appear in the claims as you would expect

```sh
echo $token | cut -d '.' -f 2 | base64 -d 
```

For querying and formatting you can use [`jq 1.6+`](https://jqlang.org/): 

```sh
echo $token | cut -d '.' -f 2 | base64 -d | jq .
```

Attempt to use the access api as follows. 

```sh
curl -v --request GET --url https://locahost/api/access/whoami  -H "Authorization: Bearer $token" 
```

### oAuth2 Proxy and Redis

You should review all the [oAuth2 Proxy Configuration](https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview/) in addition to the parameters outlined by this package. 

oAuth2 Proxy, also supports alternative providers other than Key Cloak which you can view in the [provider configuration information](https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/). 

Although oAuth2 Proxy has been the tool, that has been tested against the latest installation setup its possible an alternative tool could potentially be used in its place if it was to offer similar capability. 

## Parameters

###  Istio

| Name                            | Description                                                                         | Value                                           |
| ------------------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------- |
| istio.annotations               | used to override default annotations on just Istio Components                       | {}                                              |
| istio.enabled                   | enabled by default, but used to disable Istio components                            | true                                            |
| istio.extraDefaults             | deploys peer authentication and auth deny rules when different namespace            | false                                           |
| istio.principal                 | used for auth policy and defaults to gateway ingress                                | cluster.local/ns/istio-system/sa/ingressgateway |
| istio.peerAuthenticationMode    | can be set to PERMISSIVE for debugging but not recommended long term                | STRICT                                          |
| istio.componentSelectorLabels   | used to update the selector label for Istio which can differ for different installs | istio: ingressgateway                           |
| istio.namespace                 | namespace where Istio ingress has been installed                                    | istio-system                                    |
| istio.authorizationPolicy.hosts | hosts default                                                                       | [ * ]                                           |
| istio.virtualService.hosts      | hosts default                                                                       | [ * ]                                           |
| istio.virtualService.gateways   | gateway reference                                                                   | [ istio-system/istio-gateway  ]                 |

###  Application 

| Name                        | Description                                                           | Value                           |
| --------------------------- | --------------------------------------------------------------------- | ------------------------------- |
| app.componentSelectorLabels | used to set what the application selector label should be for the app | app.kubernetes.io/name: ia-node |


###  OIDC

| Name                                       | Description                                                           | Value                                                                                          |
| ------------------------------------------ | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| oidcProvider.type                          | used to highlight intended provider and toggle the config to generate | "keycloak"                                                                                     |
| oidcProvider.jwtRules.forwardOriginalToken | forward token settings for Istio jwtRules                             | true                                                                                           |
| oidcProvider.jwtRules.issuer               | issuer for Istio jwtRules                                             | "http://keycloak.keycloak.svc.cluster.local/realms/examplerealm"                               |
| oidcProvider.jwtRules.jwksUri              | jwks uri for Istio jwtRules                                           | "http://keycloak.keycloak.svc.cluster.local/realms/examplerealm/protocol/openid-connect/certs" |
| oidcProvider.requestPrincipals             | allowed request principal for Istio authorization policy              | [ "http://keycloak.keycloak.svc.cluster.local/examplerealm/*" ]                                |

###  OAuth2Proxy

| Name                                    | Description                                       | Value                                                                               |
| --------------------------------------- | ------------------------------------------------- | ----------------------------------------------------------------------------------- |
| oAuth2Proxy.componentSelectorLabels     | application selector labels for OAuth2Proxy       | [ app.kubernetes.io/name: oauth2-proxy, app.kubernetes.io/component: oauth2-proxy ] |
| oAuth2Proxy.customAuthorizationPaths    | paths for OAuth2Proxy custom authorization policy | [ / , /* ]                                                                          |
| oAuth2Proxy.customAuthorizationNotPaths | paths for OAuth2Proxy custom authorization policy | [  ]                                                                                |

###  OIDC OAuth2Proxy Secret

Used to generate a secret to provide to OAuth2Proxy for Key Cloak

| Name                             | Description                                                            | Value                                          |
| -------------------------------- | ---------------------------------------------------------------------- | ---------------------------------------------- |
| oidcProvider.secret.create       | option to create secret or not                                         | true                                           |
| oidcProvider.secret.name         | name of the secret for the creation                                    | oauth2-proxy-default                           |
| oidcProvider.secret.cookieSecret | default cookie value this **should be updated**                        | "SCVDREM0bCYkSmRreVtuZ0deSiRmNz80a1p3RUZPeEM=" |
| oidcProvider.secret.clientSecret | default client secret based on the example realm **should be updated** | "4qaUP8ETjxdON2pQLSzHzLCgfISZ1a93"             |
| oidcProvider.secret.clientId     | default client id based on the example realm **should be updated**     | "5461f43e-57e1-4e1b-a3e4-4947596e5d04"         |

###  OIDC OAuth2Proxy ConfigMap

Used to generate a config map to provide to OAuth2Proxy for Key Cloak

 | Name                                     | Description                               | Value                                                      |
 | ---------------------------------------- | ----------------------------------------- | ---------------------------------------------------------- |
 | oidcProvider.configMap.create            | option to create config map               | true                                                       |
 | oidcProvider.configMap.name              | name of the config map for the creation   | oauth2-proxy-default                                       |
 | oidcProvider.configMap.issuer_url        | issuer url for the identity provider      | "http://keycloak.keycloak.svc.cluster.local/realms/ianode" |
 | oidcProvider.configMap.redirect_url      | redirect url required for the application | "https://localhost/oauth2/callback"                        |
 | oidcProvider.configMap.cookie_domains    | allowed cookie domains                    | "localhost"                                                |
 | oidcProvider.configMap.whitelist_domains | whitelist domains                         | "*"                                                        |
 | oidcProvider.configMap.email_domains     | email domains                             | "*"                                                        |
 | oidcProvider.configMap.logging_enabled   | enables extra logging in oauth2proxy      | "false"                                                    |
 

## References

- [Kubernetes Cluster](https://kubernetes.io/)
- [Helm](https://helm.sh/)
- [Formatting and Query Tooling (jq)](https://jqlang.org/)
- [Istio Helm chart, Gateway, Base and Istiod 1.25.0+](https://istio.io/latest/docs/setup/install/helm/)
- [oAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Keycloak](https://www.keycloak.org/)
- [Bitnami Key Cloak Helm chart](https://github.com/bitnami/charts/blob/main/bitnami/keycloak/README.md)
- [Bitnami oAuth2 Proxy Helm chart](https://github.com/bitnami/charts/blob/main/bitnami/oauth2-proxy/README.md)
- [oAuth2 Proxy Configuration and Cookie Secret Generation](https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview/)
- [PostgreSQL](https://www.postgresql.org/)

## Development and Testing

You can run the charts from the repository code directly if you plan to develop and test new updates to the charts. 

1. Clone the repository
2. If required add an `overrides.yaml` into the root directory of the chart (overrides.yaml is purposefully ignored on commit by `.gitignore`)
3. Set a terminal to run from the root directory of the repository
4. Then run either commands below depending on if you are working with overrides

```sh 
helm install ia-node-oidc ./charts/ia-node-oidc -n ia-node -f ./charts/ia-node-oidc/values.yaml --set oidcProvider.configMap.redirect_url="https://localhost/oauth2/callback" 
```

```sh 
helm install ia-node-oidc ./charts/ia-node-oidc -n ia-node -f ./charts/ia-node-oidc/values.yaml -f ./charts/ia-node-oidc/overrides.yaml 
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
