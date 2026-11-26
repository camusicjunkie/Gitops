# Flux-Native GitOps Repository

A clean, modern, and fully **Flux-native** GitOps repository structure supporting multi-network, multi-environment, **Blue/Green** Kubernetes clusters.

This architecture combines the failure isolation and per-app granularity of [onedr0p/home-ops](https://github.com/onedr0p/home-ops) with **native Flux and Flux Operator primitives** (`FluxInstance`, `ResourceSet`, `ResourceSetInputProvider`, `ArtifactGenerator`, controller feature gates, strategic merge patches, and strict post-build variable substitution)—without Kustomize overlays or custom CLIs.

---

## Multi-Environment & Blue/Green Architecture

1. **One directory per environment, not per cluster**: Blue and green clusters (and separate air-gapped networks) share identical manifests under `clusters/staging`, `clusters/production`, and `apps/`.
2. **Runtime facts are injected at bootstrap, never committed**: Network domain, cluster name, registry host, and color (`blue`/`green`) are written into `flux-runtime-info` by OpenTofu at bootstrap.
3. **OpenTofu bootstraps once; Flux owns everything after**: OpenTofu installs the Flux Operator, secrets, `flux-runtime-info`, and `FluxInstance`, then hands off.
4. **DNS decides which color is live**: Both blue and green clusters serve the same public hostnames (`<app>.${APPS_SUBDOMAIN}.${NETWORK_DOMAIN}`). External DNS (e.g., Infoblox) switches live traffic between gateway IPs.

| Environment | Path | `APPS_SUBDOMAIN` | Example Hostname |
| :--- | :--- | :--- | :--- |
| **Production** | `clusters/production` | `apps` | `https://harbor.apps.<network-domain>` |
| **Staging** | `clusters/staging` | `staging.apps` | `https://harbor.staging.apps.<network-domain>` |
| **Laptop (Dev)** | `clusters/laptop` | `apps` | `https://harbor.apps.blueandblack.duckdns.org` |

### Cluster Naming Convention

Every VKS workload cluster follows `<network>-<env>-<color>` (for example, `neta-staging-green` or `netb-production-blue`), matching the CAPI `Cluster` object name in the vSphere Namespace. OpenTofu splits the name to select `clusters/<env>/flux-system/instance.yaml` and populate `CLUSTER_ENV` and `CLUSTER_COLOR`.

---

## Core Principles

1. **Per-App Unit of Reconciliation**: Every workload and platform component has its own dedicated Flux `Kustomization`. Modifying one app reconciles **only** that app.
2. **Zero `ks.yaml` Sprawl & Dynamic Auto-Discovery**:
   - `ArtifactGenerator` (`generator.yaml`) automatically scans `apps/{app}/app` and emits `ExternalArtifact` objects.
   - `ResourceSetInputProvider` (`rsip.yaml`) feeds these discovered paths into `apps.yaml`.
   - `ResourceSet` generates each app's `Kustomization` dynamically—no manual registration lists.
3. **No Artificial Layer Gates**:
   - `components.yaml` manages multi-stage infra (`cert-manager`, `istio`, `kyverno`, `keycloak-operator`) with localized controller-to-config dependencies.
   - `apps.yaml` manages standalone applications (`sealed-secrets`, `metrics-server`, `cnpg`, `headlamp`, `harbor`, `stigman`) in parallel with zero cluster gates.
4. **Shared Defaults Injected Transparently**:
   - Controller feature gates (`DefaultToRetryOnFailure=true`, `CancelHealthCheckOnNewRevision=true`, `StrictPostBuildSubstitutions=true`) enable automatic recovery and fail-fast variable checks.
   - ResourceSet strategic merge patches inject CRD management (`Create` / `CreateReplace`) and drift detection (`enabled`) into all Helm releases.
5. **100% `OCIRepository`**: All Helm charts are pulled via `OCIRepository` with `layerSelector` and `chartRef`, ready for mirroring into Harbor.
6. **Strict File Hygiene**: Strictly 1 resource per file and completely dash-free file names.

---

## Variable Flow & Strict Substitution

Manifests compose hostnames as `<app>.${APPS_SUBDOMAIN}.${NETWORK_DOMAIN}`:

1. **OpenTofu creates `flux-runtime-info`** in `flux-system` with `NETWORK_DOMAIN`, `CLUSTER_NAME`, `CLUSTER_ENV`, `CLUSTER_COLOR`, `HARBOR_REGISTRY`, `HARBOR_PROJECT`, and `GIT_REPO_URL`.
2. **`FluxInstance` passes `flux-runtime-info`** to the top-level `flux-system` `Kustomization`.
3. **Git provides `cluster-settings`** (`clusters/<env>/settings.yaml`) with `APPS_SUBDOMAIN` and `GATEWAY_CLUSTERIP`.
4. **Child `ResourceSet` Kustomizations** (`apps.yaml`, `components.yaml`) reference both `cluster-settings` and `flux-runtime-info` in `postBuild.substituteFrom`.
5. **Strict Substitution (`StrictPostBuildSubstitutions=true`)** fails reconciliation if any variable is missing. Manifests containing literal `${...}` syntax (such as Keycloak realm JSON or MySQL shell scripts) carry the `kustomize.toolkit.fluxcd.io/substitute: disabled` annotation.

---

## Repository Structure

```text
d:/Gitops/
├── .gitlab-ci.yml                      # OpenTofu bootstrap & smoke-test pipeline
├── .sops.yaml                          # SOPS age encryption rules for Kubernetes Secrets
├── docs/
│   └── training.md                     # Team training plan, decision rationale & Mermaid diagrams
├── bootstrap/                          # Day-0 OpenTofu, mirroring, and Supervisor RBAC
│   ├── vks/                            # VKS/CAPI OpenTofu bootstrap (HTTP state, Harbor, SOPS, runtime info)
│   │   ├── main.tf
│   │   └── variables.tf
│   ├── laptop/                         # Local dev bootstrap (public ghcr.io / kind/k3d)
│   ├── mirror/                         # flux mirror configs (hosts.yaml, bootstrap.yaml, platform.yaml, mirror.sh)
│   └── supervisor/                     # vSphere Supervisor ServiceAccount, RBAC, and kubeconfig generator
│
├── shared/                             # Shared ResourceSets, Notifications & Webhook Receiver
│   ├── resourcesets/                   # generator.yaml, rsip.yaml, apps.yaml, components.yaml, operator.yaml
│   ├── notifications/                  # gitlab/ and msteams/ Providers, Secrets, and Alerts
│   └── receiver/                       # GitLab push webhook Receiver, Secret, and HTTPRoute
│
├── clusters/                           # Day-1+: Flux root sync manifests (cluster entrypoints only)
│   ├── management/                     # Management cluster (ImageRepository, ImagePolicy, ImageUpdateAutomation)
│   │   ├── flux-system/                # FluxInstance with image-reflector + image-automation controllers
│   │   ├── gatewayapi/                 # Standard Gateway API v1.7.0 CRDs (management-only)
│   │   ├── imageautomation/            # Automated Harbor tag scanning and Git commit back to apps/
│   │   ├── istio.yaml                  # Self-contained Istio gateway-only ResourceSet (istio-base + istiod, no mesh)
│   │   ├── devcontainer.yaml           # Self-contained ResourceSet syncing + automating the devcontainer repository
│   │   └── notifications.yaml          # Pointer -> shared/notifications
│   ├── production/                     # Production entrypoint (APPS_SUBDOMAIN: apps)
│   │   ├── settings.yaml               # Environment ConfigMap (APPS_SUBDOMAIN, GATEWAY_CLUSTERIP)
│   │   ├── flux-system/                # FluxInstance 'flux' with strict postBuild & feature gates
│   │   ├── resourcesets.yaml           # Pointer -> shared/resourcesets
│   │   ├── notifications.yaml          # Pointer -> shared/notifications
│   │   └── receiver.yaml               # Pointer -> shared/receiver
│   ├── staging/                        # Staging entrypoint (APPS_SUBDOMAIN: staging.apps)
│   │   ├── settings.yaml
│   │   ├── flux-system/
│   │   ├── resourcesets.yaml
│   │   ├── notifications.yaml
│   │   └── receiver.yaml
│   └── laptop/                         # Local dev entrypoint
│       ├── settings.yaml
│       ├── flux-system/
│       └── resourcesets.yaml
│
└── apps/                               # Shared catalog (Single Source of Truth, 0 duplicate manifests)
    ├── metrics-server/app/
    ├── cnpg/
    │   ├── controllers/                # CloudNativePG operator
    │   └── configs/                    # keycloak/ (Cluster + db secret)
    ├── harbor/app/                     # Harbor registry & httproute
    ├── headlamp/app/                   # Headlamp UI, httproute, secrets/, RBAC
    ├── stigman/app/                    # Stigman API, httproute, mysql/ backing store
    ├── cert-manager/
    │   ├── controllers/                # cert-manager
    │   └── configs/                    # ca/, certificate
    ├── istio/
    │   ├── controllers/                # gatewayapi/, base/, istiod/, cni/, ztunnel/
    │   └── configs/                    # gatewayoptions, gateway, peerauthentication
    ├── kyverno/
    │   ├── controllers/                # kyverno controller
    │   └── configs/                    # clusterrole, policies/
    └── keycloak/
        ├── controllers/                # keycloak operator & crds/
        └── configs/                    # secret, keycloak, configcli/, httproute
```

---

## Adding a New Application (Developer Self-Service)

To onboard a new application `my-service`:

1. **Create the directory** under `apps/my-service/app/`:
   ```text
   apps/my-service/app/
   ├── namespace.yaml
   ├── ocirepository.yaml
   ├── helmrelease.yaml
   ├── httproute.yaml
   └── kustomization.yaml
   ```
2. **Use standard domain substitution** in `httproute.yaml` and `helmrelease.yaml`:
   ```text
   my-service.${APPS_SUBDOMAIN}.${NETWORK_DOMAIN}
   ```
3. **Commit and push to Git**: You do **not** need to touch `clusters/`.

---

## Bootstrap Pipeline & Operating Procedures

[`.gitlab-ci.yml`](file:///d:/Gitops/.gitlab-ci.yml) runs in two modes:

| Trigger | Stages | Purpose |
| :--- | :--- | :--- |
| Merge request / default branch | `validate` | Runs `tofu fmt`, `tofu validate`, and `kubectl kustomize` on all clusters |
| Manual run with `CLUSTER=<name>` | `plan` → `apply` → `smoke-test` | Waits for CAPI `Cluster` readiness, fetches kubeconfig, bootstraps Flux, and tests apps via `curl --resolve` |

### Required CI/CD Variables

With **GitLab's Harbor integration** enabled (providing `HARBOR_HOST`, `HARBOR_PROJECT`, `HARBOR_USERNAME`, and `HARBOR_PASSWORD` automatically) and `$CI_PROJECT_URL.git` for the repo URL, you only need to configure:

| Variable | Scope | Purpose |
| :--- | :--- | :--- |
| `TOFU_CI_IMAGE` | project / group | CI image containing `tofu`, `kubectl`, `curl`, and provider mirror |
| `VSPHERE_NS` | project / group | vSphere Supervisor namespace hosting CAPI `Cluster` objects |
| `SUPERVISOR_KUBECONFIG` | project (File, protected) | Long-lived service account kubeconfig for the vSphere Namespace |
| `INTERNAL_CA_BUNDLE` | project (File) | Internal CA bundle for `smoke-test` HTTPS checks |
| `SMOKE_APPS` | project | Space-separated app hostnames to probe (e.g. `harbor headlamp keycloak`) |
| `TF_VAR_network_domain` | group | Network DNS suffix (set per GitLab instance, never committed) |
| `TF_VAR_gitlab_deploy_token_username` | project (Masked, protected) | Flux Git Deploy Token username (`read_repository` only) |
| `TF_VAR_gitlab_deploy_token` | project (Masked, protected) | Flux Git Deploy Token (`read_repository` only) |
| `TF_VAR_image_automation_git_token_username` | project, `*-management-*` (Masked, protected) | GitLab Project Access Token username for image automation (management clusters only) |
| `TF_VAR_image_automation_git_token` | project, `*-management-*` (Masked, protected) | GitLab Project Access Token (`write_repository` scope), stored as `image-automation-push` on management clusters only |
| `TF_VAR_harbor_ca` | project | PEM CA of Harbor's certificate, stored as `harbor-ca` (`ca.crt`) in `flux-system`. Required on management clusters: every ImageRepository and management OCIRepository trusts Harbor through it |
| `TF_VAR_devcontainer_repo_url` | group | Devcontainer repository URL on this GitLab, stored as `DEVCONTAINER_REPO_URL` (management clusters only) |
| `TF_VAR_devcontainer_deploy_token_username` | project, `*-management-*` (Masked, protected) | Devcontainer repository `read_repository` Deploy Token username (management clusters only) |
| `TF_VAR_devcontainer_deploy_token` | project, `*-management-*` (Masked, protected) | Devcontainer repository `read_repository` Deploy Token, stored as `devcontainer-git` (management clusters only) |
| `TF_VAR_devcontainer_push_token_username` | project, `*-management-*` (Masked, protected) | Devcontainer image automation push token username (management clusters only) |
| `TF_VAR_devcontainer_push_token` | project, `*-management-*` (Masked, protected) | GitLab Project/Group Access Token (`write_repository` scope) for devcontainer image automation, stored as `devcontainer-git-push` (management clusters only) |
| `TF_VAR_devcontainer_site_env` | project, `*-management-*` | Map of the Devcontainer Pods' Site Config `site.env` values (`KLOGIN_SERVERS`, `KLOGIN_NAMESPACES`, `KLOGIN_CLUSTERS`, `KLOGIN_INSECURE`, `AI_GATEWAY_URL`), e.g. `{KLOGIN_SERVERS="sup1.example"}`; values are written single-quoted, since login shells source `site.env`; stored base64 as `DEVCONTAINER_SITE_ENV_B64` (management clusters only) |
| `TF_VAR_devcontainer_site_ca` | project, `*-management-*` | PEM CAs the Devcontainer Pods trust (Site Config `site-ca.crt`); empty uses `TF_VAR_harbor_ca`; stored base64 as `DEVCONTAINER_SITE_CA_B64` (management clusters only) |
| `TF_VAR_devcontainer_gateway_address` | project, `*-management-*` | IP to pin on the Devcontainer Pods' shared Gateway (`DEVCONTAINER_GATEWAY_ADDRESS`); give it a DNS name in Infoblox. Empty: the Roster's default `none`, and the load balancer picks one (management clusters only) |
| `TF_VAR_devcontainer_pod_cidr` | project, `*-management-*` | The management cluster's Pod CIDR, kept out of the Devcontainer Pods' egress (`DEVCONTAINER_POD_CIDR`). Default `192.168.0.0/16`, VKS's default (management clusters only) |
| `TF_VAR_sops_age_key` | project (Masked, protected) | Private `age` key stored as `sops-age` in `flux-system` for SOPS decryption |

### Secrets Management (SOPS + `age`)

1. Generate an `age` keypair (`age-keygen -o age.agekey`), set the public key (`age1...`) in [`.sops.yaml`](file:///d:/Gitops/.sops.yaml), and store the private key in GitLab CI/CD as `TF_VAR_sops_age_key`.
2. Populate and encrypt each `Secret` manifest in-place before deploying (`encrypted_regex: ^(data|stringData)$`):

```bash
sops --encrypt --in-place apps/cert-manager/configs/ca/secret.yaml
sops --encrypt --in-place apps/headlamp/app/secrets/client.yaml
sops --encrypt --in-place apps/headlamp/app/secrets/oidc.yaml
sops --encrypt --in-place apps/keycloak/configs/secret.yaml
sops --encrypt --in-place apps/cnpg/configs/keycloak/secret.yaml
sops --encrypt --in-place apps/keycloak/configs/configcli/secret.yaml
sops --encrypt --in-place apps/stigman/app/mysql/secret.yaml
sops --encrypt --in-place shared/notifications/gitlab/secret.yaml
sops --encrypt --in-place shared/notifications/msteams/secret.yaml
sops --encrypt --in-place shared/receiver/secret.yaml
```

During Day-0 bootstrap, OpenTofu injects `TF_VAR_sops_age_key` into `flux-system/sops-age`, and both `flux-system` and `ResourceSet` Kustomizations decrypt secrets automatically via `spec.decryption.provider: sops`.

### Notifications & GitLab Webhook Receiver

1. **GitLab Commit Status & MS Teams Alerts**:
   * [`shared/notifications/gitlab/`](file:///d:/Gitops/shared/notifications/gitlab/provider.yaml) posts green/red commit statuses (`eventSeverity: info`) using a GitLab `api`-scoped token encrypted in `secret.yaml`.
   * [`shared/notifications/msteams/`](file:///d:/Gitops/shared/notifications/msteams/provider.yaml) sends failure alerts (`eventSeverity: error`) to your Teams incoming webhook URL encrypted in `secret.yaml`.
2. **GitLab Push Webhook (`Receiver`)**:
   * After `shared/receiver/` reconciles on a workload cluster, retrieve the generated webhook path:
     ```bash
     kubectl -n flux-system get receiver gitlab -o jsonpath='{.status.webhookPath}'
     ```
   * In your GitLab project under **Settings → Webhooks**, add:
     * **URL**: `https://flux-webhook.<apps-subdomain>.<network-domain><webhookPath>`
     * **Secret token**: The same plaintext token encrypted in `shared/receiver/secret.yaml`
     * **Trigger**: `Push events`

### Management Cluster (`ImageUpdateAutomation`)

1. Every cluster's `TF_VAR_gitlab_deploy_token` is a Deploy Token with **`read_repository`** scope only. When bootstrapping a management cluster (`CLUSTER=<network>-management-<color>`), also supply `TF_VAR_image_automation_git_token` (and its username) as a **GitLab Project Access Token** (or Group Access Token) with **`write_repository`** scope (GitLab Deploy Tokens only support `read_repository`). Scope those CI variables to `*-management-*`—OpenTofu also guards injection with `local.cluster_env == "management"`, storing it as `image-automation-push` solely for `ImageUpdateAutomation`. Without it, automation cannot push.
2. As `mirror.sh` + Charon land new chart or image tags in Harbor, `clusters/management/imageautomation/` commits pinned `tag:` updates to the **`image-updates`** branch—review and merge the MR to promote them to `staging` and `production`.
3. Every ImageRepository on the management cluster sets `certSecretRef: harbor-ca`: Flux's controllers run in Pods and do not see the nodes' trust of Harbor (a Supervisor service's certificate). Supply `TF_VAR_harbor_ca`.

### Management Cluster: Devcontainer Pods

The admins' Devcontainer Pods (the `k8scontainer` repository) run on the management cluster, apart from workload clusters. `clusters/management/` is self-contained and independent of `apps/` and `shared/resourcesets/`:

* **`gatewayapi/`**: vendors the standard Gateway API `v1.7.0` CRDs (`TCPRoute` GA at `v1`) directly for the management cluster.
* **`istio.yaml`**: a patch-free `ResourceSet` that waits for Gateway API CRDs, owns `Namespace/istio-system` (`prune: disabled`, without `privileged` PSA), copies `harbor-pull` and `harbor-ca` from `flux-system`, and deploys `istio-base` and `istiod` (`1.32.0`) directly without `istio-cni`, `ztunnel`, or the ambient profile so `gatewayClassName: istio` Gateways get a gateway Deployment and nothing joins a mesh. With no Kyverno here, `OCIRepository` sources configure `certSecretRef: harbor-ca` and `secretRef: harbor-pull`, and `istiod` sets `global.hub: ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/istio` and `global.imagePullSecrets: [harbor-pull]`.
* **`devcontainer.yaml`**: a `ResourceSet` that waits for `HelmRelease/istiod` (`ready: true`), owns `Namespace/devcontainer` (`restricted` PSA, prune disabled for both the `ResourceSet` and kustomize-controller so admin PVCs are never pruned), copies `harbor-ca` and `harbor-pull` from `flux-system`, configures `ServiceAccount/default` (`prune: disabled`, `harbor-pull`, `automountServiceAccountToken: false`), defines the read-only (`devcontainer`, secret `devcontainer-git`) and push (`devcontainer-push`, secret `devcontainer-git-push`) `GitRepository` objects, syncs `./manifests/devcontainer` with `postBuild.substituteFrom: flux-runtime-info` and no patches, and runs the namespace's `ImageUpdateAutomation`, which commits only the Roster's `imageTag` to `image-updates`. The devcontainer repository commits nothing network-specific: its Registry, Site Config, Gateway address and Pod CIDR are Flux variables named after runtime facts (`HARBOR_REGISTRY`, `HARBOR_PROJECT` and the `DEVCONTAINER_*` facts below), and its `tests/site/facts.env` is the contract. A fact added there is added to `bootstrap/vks` in the same change; with `StrictPostBuildSubstitutions` a missing one fails the sync. Its copy on another network differs only in the Roster's admins (see its Release Owner guide, "Carrying this repository to another network").

Supply the `TF_VAR_devcontainer_*` variables and `TF_VAR_harbor_ca` when bootstrapping the management cluster. Because GitLab Deploy Tokens only support `read_repository`, a GitLab group deploy token can serve as both read tokens (`gitlab_deploy_token` and `devcontainer_deploy_token`), while `TF_VAR_devcontainer_push_token` requires a Project or Group Access Token with `write_repository`.

**Not blue/green.** The management cluster holds every admin's State Directory on cluster-local volumes, so it is upgraded in place (VKS rolling node upgrades), not replaced by a new color: the vSphere CSI volumes stay, and each Devcontainer Pod moves to another node, dropping its admin's live session. Announce those windows. Its name still carries a color (`<network>-management-<color>`), because bootstrap requires one. Blue/green here would mean moving the admins' volumes at each cutover and running two image automations against one repository.

**Outside this repository.** These settings live in other systems, so no check here sees them:

* **Infoblox:** a DNS name for `TF_VAR_devcontainer_gateway_address`. Admins give it to the devcontainer installer (`-GatewayHost`), so the address can change behind the name.
* **NetApp:** a snapshot policy on the datastore behind the management cluster's StorageClass. The devcontainer spec puts volume backups out of scope, but in-place upgrades and a mistaken PVC deletion both depend on the admins' volumes surviving. Ask the storage engineer; SnapMirror to another site covers losing the datastore.
* **Harbor and GitLab** settings for the devcontainer Releases (tag immutability, the `image-updates` merge request with `[skip ci]`): the devcontainer repository's Release Owner guide, "Settings outside this repository".

**Gateway API and Istio versions.** Both `apps/istio/controllers/gatewayapi/crds.yaml` and `clusters/management/gatewayapi/crds.yaml` vendor the **standard** v1.7.0 bundle, and Istio is 1.32.0: Istio reads TCPRoute at `v1` (GA in Gateway API v1.6.0) only from 1.31 (istio/istio#60766); 1.30 read `v1alpha2`, which the standard channel no longer serves. From v1.7.0 the bundle carries a `safe-upgrades` ValidatingAdmissionPolicy (Kubernetes 1.30+) that refuses CRD downgrades. Istio 1.31+ publishes upstream charts at `blob.istio.io/istio-release/charts` (OCI: `ghcr.io/istio/release/charts`); this repository mirrors DHI's builds (`bootstrap/mirror/platform.yaml`).

### Blue/Green Cutover & Retirement

1. **Build & Verify**: Trigger the pipeline with `CLUSTER=<network>-<env>-<new-color>`. `smoke-test` verifies every app over HTTPS against the new cluster's gateway IP (`--resolve`) before DNS changes.
2. **Cut Over / Roll Back**: Repoint the wildcard DNS record (`*.<apps-subdomain>.<network-domain>`) to the new cluster's gateway IP (or back to the old IP to roll back).
3. **Retire Old Color**: Delete the old CAPI `Cluster` manifest from your management repo, then delete its state under **Operate → Terraform states** in GitLab.

---

## Documentation

* [Team Training Plan & Architecture Flowcharts](docs/training.md)
* [vSphere Supervisor CI Access Setup](bootstrap/supervisor/readme.md)
* [Harbor Artifact Mirroring (`flux mirror`)](bootstrap/mirror/readme.md)
