# federator

**Repository:** `[helm-charts]`  
**Helm-Chart-Name:** `[federator]`  
**Description:** `[National Digital Twin Programme Helm chart for the Federator]`  
**SPDX-License-Identifier:** `Apache-2.0 AND OGL-UK-3.0 `  

## Overview  

The Helm chart `federator` deploys the NDTP Federator application, which can run in two modes:
- **Server mode (producer)**: Exposes a gRPC service for clients to consume federated data
- **Client mode (consumer)**: Connects to remote Federator servers and consumes federated data

The Federator is an open-source component developed as part of the National Digital Twin Programme (NDTP) to support secure data federation and sharing across organisations.

[Overview of Federator](https://github.com/National-Node-Net/integration-architecture-documentation)

> [!IMPORTANT]  
> Secrets management is outside of the scope of the deployment. However, we have provided several options for managing secrets, including the `configRender` feature that allows you to keep sensitive values in existing Kubernetes Secrets while maintaining configuration files in ConfigMaps.

## TL;DR

### Server Mode

```sh
helm install federator-server oci://ghcr.io/national-node-net/helm/federator -n federator \
--set mode=server \
--create-namespace
```

### Client Mode

```sh
helm install federator-client oci://ghcr.io/national-node-net/helm/federator -n federator \
--set mode=client \
--set service.enabled=false \
--create-namespace
```

Optionally, use an overrides file:

```sh
helm install federator oci://ghcr.io/national-node-net/helm/federator -n federator -f ./overrides.yaml 
```

## Prerequisites  

You will require the following technologies installed and configured to get started. 

Versions highlighted are based on what configurations have been used throughout the testing of the Helm chart. 

- **Supported Kubernetes Versions:** 
  - [`Kubernetes 1.23+`](https://kubernetes.io/): a Kubernetes cluster i.e. AKS or local development cluster 
  
- **Required Tooling:**
  - [`kubectl 1.28.9+`](https://kubernetes.io/docs/reference/kubectl/): prior knowledge, usage and experience with `kubectl` 
  - [`Helm 3.8.0+`](https://helm.sh/): prior knowledge, usage and experience in Helm
  
- **Optional Tooling:**
  - [`K9s 0.32.5+`](https://K9scli.io/): for Kubernetes cluster overview and visualisation of deployments
  
- **Application Dependencies:** 
  - [`Apache Kafka`](https://kafka.apache.org/): for data streaming (tested with [`Strimzi Kafka Operator 0.45.0+`](https://artifacthub.io/packages/helm/strimzi-kafka-operator/strimzi-kafka-operator))
  - **Authentication**: The Federator supports various authentication mechanisms including OIDC tokens and API keys
  - **AWS MSK (Optional)**: If using AWS MSK with IAM authentication, see [MSK-IAM-AUTH.md](MSK-IAM-AUTH.md)

## Installing the Chart

Create the target namespace if it does not already exist. 

```sh
kubectl create namespace federator
```

### Server Mode Installation

Install the chart in server mode to expose a gRPC service:

```sh
helm install federator-server oci://ghcr.io/national-node-net/helm/federator -n federator \
--set mode=server
```

### Client Mode Installation

Install the chart in client mode to consume from remote servers:

```sh
helm install federator-client oci://ghcr.io/national-node-net/helm/federator -n federator \
--set mode=client \
--set service.enabled=false
```

## Uninstall the Chart

To uninstall the chart:

```sh
helm uninstall federator -n federator
```

## Configuration and Installation Details

### Mode Selection

The Federator can run in two modes, controlled by the `mode` value:

#### Server Mode (Producer)
- Reads from local Kafka topics
- Exposes a gRPC service on port 9001
- Serves federated data to clients
- Requires `server.properties` configuration file

```yaml
mode: server
service:
  enabled: true
  type: ClusterIP
  port: 9001
```

#### Client Mode (Consumer)
- Connects to remote Federator servers via gRPC
- Writes received data to local Kafka topics
- Does not expose a service
- Requires `client.properties` configuration file

```yaml
mode: client
service:
  enabled: false
```

### Configuration Files

The Federator requires configuration files to be mounted at `/config` (configurable via `config.mountPath`). There are two approaches:

#### Option 1: Static ConfigMap (Simple)

Provide configuration files directly in values:

```yaml
config:
  files:
    server.properties: |-
      kafka.bootstrapServers=kafka:9092
      kafka.topic.prefix=PREFIX-
      # ... additional properties
    
    logback.xml: |-
      <configuration>
        <!-- logging configuration -->
      </configuration>
```

#### Option 2: ConfigMap + Secret Rendering (Recommended for Production)

Keep non-sensitive config in ConfigMaps and inject secrets at runtime:

```yaml
configRender:
  enabled: true
  secretRefs:
    - name: kafka-credentials
      items:
        - key: sasl-jaas-config
          path: kafka.sasl.config
    - name: redis-password
      items:
        - key: password
          path: redis.password
  properties:
    - property: redis.password
      secretKey: redis.password
      file: server.properties
  replacements:
    - placeholder: "{{KAFKA_SASL_CONFIG}}"
      secretKey: kafka.sasl.config
      file: server.properties

config:
  files:
    server.properties: |-
      kafka.bootstrapServers=kafka:9092
      kafka.sasl.jaas.config={{KAFKA_SASL_CONFIG}}
      # redis.password will be injected by configRender
```

The `configRender` initContainer will:
1. Copy files from the ConfigMap to the config directory
2. Inject secret values using either property upsert or placeholder replacement
3. Make the final configuration available to the main container

See [examples/values-server-example.yaml](examples/values-server-example.yaml) and [examples/values-client-example.yaml](examples/values-client-example.yaml) for complete working examples.

### AWS MSK IAM Authentication

The chart includes built-in support for AWS MSK with IAM authentication. When enabled, an init container downloads the required authentication library.

```yaml
mskIamAuth:
  enabled: true
  image: curlimages/curl:8.11.1

extraEnv:
  - name: AWS_REGION
    value: eu-west-2

serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/your-msk-access-role
```

For detailed configuration, see [MSK-IAM-AUTH.md](MSK-IAM-AUTH.md).

### Secret Management

#### Option 1: Bring Your Own Secret

Create your own secret and reference it:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: federator-config-secret
  namespace: federator
type: Opaque
stringData:
  server.properties: |
    kafka.bootstrapServers=kafka:9092
    # ... your configuration
```

Then reference it:

```yaml
secretConfig:
  create: false
  name: federator-config-secret
  items:
    - key: server.properties
      path: server.properties
```

#### Option 2: Chart-Managed Secret

Let the chart create a secret:

```yaml
secretConfig:
  create: true
  files:
    server.properties: |
      kafka.bootstrapServers=kafka:9092
      # ... your configuration
```

> [!WARNING]  
> Do not commit sensitive values to version control. Use encrypted secrets management (e.g., Sealed Secrets, External Secrets Operator) or the `configRender` approach.

### Image Configuration

The chart uses separate image repositories for server and client modes:

```yaml
images:
  server:
    repository: ghcr.io/national-node-net/federator/federator-server
    tag: 1.0.0
  client:
    repository: ghcr.io/national-node-net/federator/federator-client
    tag: 1.0.0

image:
  pullPolicy: IfNotPresent
```

### Private Container Registries

To use a private registry, create an image pull secret:

```sh
kubectl create secret docker-registry private-registry \
  --docker-server=ghcr.io \
  --docker-username=your-username \
  --docker-password=$TOKEN \
  --docker-email=your-email@example.com \
  -n federator
```

Then reference it:

```yaml
imagePullSecrets:
  - name: private-registry
```

### Resource Management

Configure resource requests and limits:

```yaml
resources:
  limits:
    cpu: 1000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi
```

### Autoscaling

Enable horizontal pod autoscaling:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80
```

> [!NOTE]  
> When autoscaling is enabled, the `replicaCount` value is ignored.

### Health Probes

Configure health checks for the application:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 9001
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 9001
  initialDelaySeconds: 10
  periodSeconds: 5

startupProbe:
  httpGet:
    path: /health
    port: 9001
  failureThreshold: 30
  periodSeconds: 10
```

### Additional Volumes and Mounts

Add custom volumes and volume mounts:

```yaml
extraVolumes:
  - name: custom-config
    configMap:
      name: my-custom-config

extraVolumeMounts:
  - name: custom-config
    mountPath: /custom
    readOnly: true
```

### Environment Variables

Add additional environment variables:

```yaml
extraEnv:
  - name: LOG_LEVEL
    value: INFO
  - name: CUSTOM_VAR
    value: custom-value

extraEnvFrom:
  - configMapRef:
      name: external-config
  - secretRef:
      name: external-secret
```

### Java Options

Pass JVM options to the application:

```yaml
javaOpts: "-Xmx2048m -Xms1024m -XX:+UseG1GC"
```

### Application Arguments

Pass additional arguments to the application:

```yaml
args: "--debug --verbose"
```

## Parameters

### Global Parameters

| Name                 | Description                          | Value |
| -------------------- | ------------------------------------ | ----- |
| `replicaCount`       | Number of replicas (ignored if HPA enabled) | `1` |
| `mode`               | Deployment mode: `server` or `client` | `server` |
| `nameOverride`       | Override the chart name              | `""` |
| `fullnameOverride`   | Override the full resource name      | `""` |
| `imagePullSecrets`   | Image pull secrets for private registries | `[]` |

### Image Parameters

| Name                        | Description                     | Value                                                      |
| --------------------------- | ------------------------------- | ---------------------------------------------------------- |
| `images.server.repository`  | Server mode image repository    | `ghcr.io/national-node-net/federator/federator-server` |
| `images.server.tag`         | Server mode image tag           | `1.0.0`                                                    |
| `images.client.repository`  | Client mode image repository    | `ghcr.io/national-node-net/federator/federator-client` |
| `images.client.tag`         | Client mode image tag           | `1.0.0`                                                    |
| `image.repository`          | Override image repository       | `""`                                                       |
| `image.tag`                 | Override image tag              | `""`                                                       |
| `image.pullPolicy`          | Image pull policy               | `IfNotPresent`                                             |

### Service Account Parameters

| Name                          | Description                      | Value  |
| ----------------------------- | -------------------------------- | ------ |
| `serviceAccount.create`       | Create a service account         | `true` |
| `serviceAccount.annotations`  | Service account annotations      | `{}`   |
| `serviceAccount.name`         | Service account name (auto-generated if empty) | `""` |

### Service Parameters

| Name                  | Description                       | Value        |
| --------------------- | --------------------------------- | ------------ |
| `service.enabled`     | Enable service (server mode only) | `true`       |
| `service.type`        | Service type                      | `ClusterIP`  |
| `service.port`        | Service port                      | `9001`       |
| `service.annotations` | Service annotations               | `{}`         |
| `service.labels`      | Service labels                    | `{}`         |

### Configuration Parameters

| Name                            | Description                                  | Value                  |
| ------------------------------- | -------------------------------------------- | ---------------------- |
| `config.mountPath`              | Path where config files are mounted          | `/config`              |
| `config.serverPropertiesFile`   | Server properties filename                   | `server.properties`    |
| `config.clientPropertiesFile`   | Client properties filename                   | `client.properties`    |
| `config.files`                  | Configuration files as key-value pairs       | `{}`                   |

### Config Render Parameters

| Name                            | Description                                        | Value         |
| ------------------------------- | -------------------------------------------------- | ------------- |
| `configRender.enabled`          | Enable config rendering with secret injection      | `false`       |
| `configRender.image.repository` | Init container image for config rendering          | `busybox`     |
| `configRender.image.tag`        | Init container image tag                           | `1.36.1`      |
| `configRender.secretRefs`       | List of existing Secrets to mount (recommended)    | `[]`          |
| `configRender.secretName`       | Single Secret to mount (legacy option)             | `""`          |
| `configRender.properties`       | Property upsert operations                         | `[]`          |
| `configRender.replacements`     | Placeholder replacement operations                 | `[]`          |

### Secret Config Parameters

| Name                        | Description                      | Value   |
| --------------------------- | -------------------------------- | ------- |
| `secretConfig.create`       | Create a secret                  | `false` |
| `secretConfig.name`         | Secret name                      | `""`    |
| `secretConfig.items`        | Secret items to mount            | `[]`    |
| `secretConfig.files`        | Secret files content             | `{}`    |
| `secretConfig.annotations`  | Secret annotations               | `{}`    |

### AWS MSK IAM Auth Parameters

| Name                      | Description                               | Value                                                                                          |
| ------------------------- | ----------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `mskIamAuth.enabled`      | Enable AWS MSK IAM authentication         | `false`                                                                                        |
| `mskIamAuth.image`        | curl image for downloading JAR            | `curlimages/curl:8.11.1`                                                                       |
| `mskIamAuth.downloadUrl`  | URL to download MSK IAM auth library      | `https://github.com/aws/aws-msk-iam-auth/releases/download/v2.3.0/aws-msk-iam-auth-2.3.0-all.jar` |
| `mskIamAuth.jarFileName`  | JAR filename                              | `aws-msk-iam-auth-2.3.0-all.jar`                                                               |
| `mskIamAuth.libraryPath`  | Path to mount the library                 | `/library`                                                                                     |
| `mskIamAuth.volumeName`   | Volume name for the library               | `msk-lib`                                                                                      |

### Java and Application Parameters

| Name           | Description                        | Value |
| -------------- | ---------------------------------- | ----- |
| `javaOpts`     | JVM options                        | `""`  |
| `args`         | Application arguments              | `""`  |
| `extraEnv`     | Additional environment variables   | `[]`  |
| `extraEnvFrom` | Additional environment from sources| `[]`  |

### Volume Parameters

| Name                  | Description                  | Value |
| --------------------- | ---------------------------- | ----- |
| `extraVolumes`        | Additional volumes           | `[]`  |
| `extraVolumeMounts`   | Additional volume mounts     | `[]`  |

### Resource Parameters

| Name                   | Description                            | Value |
| ---------------------- | -------------------------------------- | ----- |
| `resources`            | Resource requests and limits           | `{}`  |
| `podAnnotations`       | Pod annotations                        | `{}`  |
| `podSecurityContext`   | Pod security context                   | `{}`  |
| `securityContext`      | Container security context             | `{}`  |

### Probe Parameters

| Name              | Description          | Value |
| ----------------- | -------------------- | ----- |
| `livenessProbe`   | Liveness probe       | `{}`  |
| `readinessProbe`  | Readiness probe      | `{}`  |
| `startupProbe`    | Startup probe        | `{}`  |

### Autoscaling Parameters

| Name                                      | Description                         | Value   |
| ----------------------------------------- | ----------------------------------- | ------- |
| `autoscaling.enabled`                     | Enable autoscaling                  | `false` |
| `autoscaling.minReplicas`                 | Minimum replicas                    | `1`     |
| `autoscaling.maxReplicas`                 | Maximum replicas                    | `3`     |
| `autoscaling.targetCPUUtilizationPercentage`    | Target CPU utilization        | `80`    |
| `autoscaling.targetMemoryUtilizationPercentage` | Target memory utilization     | `80`    |

### Scheduling Parameters

| Name            | Description        | Value |
| --------------- | ------------------ | ----- |
| `nodeSelector`  | Node selector      | `{}`  |
| `tolerations`   | Tolerations        | `[]`  |
| `affinity`      | Affinity rules     | `{}`  |

## Examples

See the [examples](examples/) directory for complete working examples:

- [values-server-example.yaml](examples/values-server-example.yaml) - Server mode with config rendering
- [values-client-example.yaml](examples/values-client-example.yaml) - Client mode with config rendering

## References

- [Kubernetes Cluster](https://kubernetes.io/)
- [Helm](https://helm.sh/)
- [Apache Kafka](https://kafka.apache.org/)
- [AWS MSK IAM Authentication](https://github.com/aws/aws-msk-iam-auth)
- [MSK-IAM-AUTH.md](MSK-IAM-AUTH.md) - Detailed AWS MSK configuration guide

## Development and Testing

You can run the charts from the repository code directly if you plan to develop and test new updates to the charts. 

1. Clone the repository
2. Create an `overrides.yaml` file with your configuration (ignored by git)
3. Set a terminal to run from the root directory of the repository
4. Run the install command:

```sh
helm install federator ./charts/federator -n federator -f ./charts/federator/values.yaml -f ./charts/federator/overrides.yaml
```

Or with inline overrides:

```sh
helm install federator ./charts/federator -n federator \
  --set mode=server \
  --set config.files.server\.properties="kafka.bootstrapServers=kafka:9092"
```

## Public Funding Acknowledgment  
This repository has been developed with public funding as part of the National Digital Twin Programme (NDTP), a UK Government initiative. NDTP, alongside its partners, has invested in this work to advance open, secure, and reusable digital twin technologies for any organisation, whether from the public or private sector, irrespective of size.  

## License  
This repository contains both source code and documentation, which are covered by different licenses:  
- **Code:** Originally developed by **Telicent Ltd.**, now maintained by **National Digital Twin Programme**. Licensed under the [Apache License 2.0](../../LICENSE.md).  
- **Documentation:** Licensed under the [Open Government Licence v3.0](../../OGL_LICENSE.md).  
See [`LICENSE.md`](../../LICENSE.md), [`OGL_LICENSE.md`](../../OGL_LICENSE.md), and [`NOTICE.md`](../../NOTICE.md) for details.    

## Security and Responsible Disclosure  
We take security seriously. If you believe you have found a security vulnerability in this repository, please follow our responsible disclosure process outlined in [`SECURITY.md`](../../SECURITY.md).  

## Contributing  
We welcome contributions that align with the Programme's objectives. Please read our [`CONTRIBUTING.md`](../../CONTRIBUTING.md) guidelines before submitting pull requests.  

## Acknowledgements  
This repository has benefited from collaboration with various organisations. For a list of acknowledgments, see [`ACKNOWLEDGEMENTS.md`](../../ACKNOWLEDGEMENTS.md).  

## Support and Contact  
For questions or support, check our Issues or contact the NDTP team on ndtp@businessandtrade.gov.uk.

**Maintained by the National Digital Twin Programme (NDTP).**  

© Crown Copyright 2026. This work has been developed by the National Digital Twin Programme and is legally attributed to the UK's Department for Business, Innovation, Science and Trade (BIST) as the governing entity
