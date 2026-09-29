# Changelog 

**Repository:** `[helm-charts]`  
**Description:** `Tracks all notable changes, version history, and roadmap toward 1.0.0 following Semantic Versioning.`  
**SPDX-License-Identifier:** `OGL-UK-3.0`  

All notable changes to this repository will be documented in this file. 

Routine updates limited to patching GitHub Actions dependencies are excluded from new changelog entries, as they do not themselves change the functional behaviour of application software. Changes that alter workflow functionality, security controls or application behaviour remain reportable. Historical entries documenting GitHub Actions dependency updates are retained for reference.

This project follows **Semantic Versioning (SemVer)** ([semver.org](https://semver.org/)), using the format: 


`[MAJOR].[MINOR].[PATCH]` 
- **MAJOR** (`X.0.0`) – Incompatible API/feature changes that break backward compatibility. 
- **MINOR** (`0.X.0`) – Backward-compatible new features, enhancements, or functionality changes. 
- **PATCH** (`0.0.X`) – Backward-compatible bug fixes, security updates, or minor corrections. 
- **Pre-release versions** – Use suffixes such as `-alpha`, `-beta`, `-rc.1` (e.g., `2.1.0-beta.1`). 
- **Build metadata** – If needed, use `+build` (e.g., `2.1.0+20250314`). 

---

## [0.90.3] – 2026-08-11

### Changed
- Updated GitHub Actions to latest versions.

---

## [0.90.2] – 2026-07-16

### Changed 
- Alignment of GitHub actions to new organisation.

---

## [0.90.1] – 2025-04-30

no updates to ia-node-mongodb. 

### Fix

- ia-node-oidc:
  - name of the `oidcProvider.componentSelectorLabels` changed to  `oAuth2Proxy.componentSelectorLabels` to reflect the content more accurate
  - name of realm to in the defaults to use `ianode` rather than just `examplerealm` so that this is more specific for the examples provided 

### Features

- ia-node:
  - defaults set to local keycloak service for the api and secure graph
  - revise the default `Fuseki configs` to provide the ability some of the default install options and to install with/without catalog topic
  - default hosts to "*" to ease local deployment 
- ia-node-kafka:
  - add flexibility to override values for the listener and virtual service ports, so these can be overridden
- ia-node-oidc:
  - add flexibility to override the both `paths` and `not paths` for the `authenticate-apps` CUSTOM authorization policy
  - default hosts to "*" to ease local deployment

In addition we have added a scripts folder with a few local development script examples. 

### Additional Notes and Limitations 

- ia-node:
  - the secure graph component is set to disabled by default at this time, when working with local Kafka Cluster, the Connect component if enabled will have no issues with connecting, however the graph component whilst able to connects, presents a TLS handshake error. Its not believed this to be an issue for cloud equivalent components
  - there currently are no supported images at this time for the Access UI or Query UI components but these can be enabled and overridden with test images as these become available
- ia-node-kafka:
  - the Zookeeper components are going to be deprecated in the future, suggest moving to an alterative i.e. Kraft in the near future

## [0.90.0] – 2025-04-25

### Initial Public Release (Pre-Stable) 

This is the first public release of this repository under NDTP's open-source governance model. 
Since this release is **pre-1.0.0**, changes may still occur that are **not fully backward-compatible**. 

#### Initial Features 
  - [`ia-node`](./charts/ia-node/README.md): Helm chart to deploy the IA Node application components see [ia-node CHANGELOG.md](./charts/ia-node/CHANGELOG.md)
  - [`ia-node-oidc`](./charts/ia-node-oidc/README.md): Helm chart intended to ease deployment and configuration of an OIDC conformant Identity Provider (IdP) Keycloak integrated with Istio, oAuth2 Proxy and Redis, which are prerequisites required to deploy an IA Node see [ia-node-oidc CHANGELOG.md](./charts/ia-node-oidc/CHANGELOG.md)
  -  [`ia-node-mongodb`](./charts/ia-node-mongodb/README.md): Helm chart intended to ease deployment and configuration of MongoDB which is a prerequisite required to deploy an IA Node see [ia-node-mongodb CHANGELOG.md](./charts/ia-node-mongodb/CHANGELOG.md)
  -  [`ia-node-kafka`](./charts/ia-node-kafka/README.md): Helm chart intended to ease deployment and configuration of Apache Kafka which is a prerequisite required to deploy an IA Node see [ia-node-kafka CHANGELOG.md](./charts/ia-node-kafka/CHANGELOG.md)

#### Known Limitations 
- Some components are subject to change before `1.0.0`. 

## Future Roadmap to `1.0.0` 

The `0.90.x` series is part of NDTP’s **pre-stable development cycle**, meaning: 
- **Minor versions (`0.91.0`, `0.92.0`...) introduce features and improvements** leading to a stable `1.0.0`. 
- **Patch versions (`0.90.1`, `0.90.2`...) contain only bug fixes and security updates**. 
- **Backward compatibility is NOT guaranteed until `1.0.0`**, though NDTP aims to minimise breaking changes. 

Once `1.0.0` is reached, future versions will follow **strict SemVer rules**. 

---

## Versioning Policy 

1. **MAJOR updates (`X.0.0`)** – Typically introduce breaking changes that require users to modify their code or configurations. 
- **Breaking changes (default rule)**: Any backward-incompatible modifications require a major version bump. 
- **Non-breaking major updates (exceptional cases)**: A major version may also be incremented if the update represents a significant milestone, such as a shift in governance, a long-term stability commitment, or substantial new functionality that redefines the project’s scope. 
2. **MINOR updates (`0.X.0`)** – New functionality that is backward-compatible. 
3. **PATCH updates (`0.0.X`)** – Bug fixes, performance improvements, or security patches. 
4. **Dependency updates** – A **major dependency upgrade** that introduces breaking changes should trigger a **MAJOR** version bump (once at `1.0.0`). 

---

## How to Update This Changelog 

1. When making changes, update this file under the **Unreleased** section. 
2. Before a new release, move changes from **Unreleased** to a new dated section with a version number. 
3. Follow **Semantic Versioning** rules to categorise changes correctly. 
4. If pre-release versions are used, clearly mark them as `-alpha`, `-beta`, or `-rc.X`. 

---

**Maintained by the National Digital Twin Programme (NDTP).** 

© Crown Copyright 2026. This work has been developed by the National Digital Twin Programme and is legally attributed to the UK's Department for Business, Innovation, Science and Trade (BIST) as the governing entity. 
Licensed under the Open Government Licence v3.0. 
For full licensing terms, see [OGL_LICENSE.md](OGL_LICENSE.md).