# Harbor Artifact Mirroring (`flux mirror`)

This directory contains the `mirror.plugin.fluxcd.io/v1beta1` configurations and helper script used to mirror all Flux distribution images, Day-0 bootstrap dependencies, and Day-2 application charts/images into your internal Harbor instance.

---

## Files in This Directory

| File | Purpose |
| :--- | :--- |
| [`hosts.yaml`](hosts.yaml) | Registry credentials template for `flux mirror login` (rendered via `envsubst`) |
| [`bootstrap.yaml`](bootstrap.yaml) | Day-0 bootstrap extras not covered by `flux operator distro mirror` (`flux-operator` chart, `flux-operator-bootstrap`, `gitlab-runner`, `gitlab-opentofu`, Trivy DBs) |
| [`platform.yaml`](platform.yaml) | Steady-state `apps/` Helm charts and `dhi.io` hardened container images |
| [`mirror.sh`](mirror.sh) | Wrapper script that authenticates and runs `flux operator distro mirror` + `flux mirror sync` |

---

## Prerequisites

1. **`flux` CLI** with the `flux-operator` / `mirror` plugin installed.
2. **`envsubst`** (from `gettext`).
3. **Environment variables** (provided automatically in GitLab CI when the Harbor integration is enabled, or exported manually on a jump host):
   * `HARBOR_HOST` (e.g. `harbor.example.local`)
   * `HARBOR_PROJECT` (e.g. `gitops`)
   * `HARBOR_USERNAME` / `HARBOR_PASSWORD` (robot or user with push access to `${HARBOR_PROJECT}`)
   * Upstream pull credentials referenced in `hosts.yaml` (if pulling from authenticated registries): `DHI_USER` / `DHI_TOKEN`, `IRON_BANK_USER` / `IRON_BANK_TOKEN`

---

## Usage

Run [`mirror.sh`](mirror.sh) with the desired scope (`bootstrap`, `platform`, or `all`):

```bash
# Mirror everything (Flux distro + bootstrap extras + platform apps)
./mirror.sh all

# Mirror only Day-0 Flux distro + bootstrap extras
./mirror.sh bootstrap

# Mirror only steady-state platform charts and images
./mirror.sh platform
```

To pin a specific Flux distribution stream (defaults to `2.10.x`):

```bash
FLUX_VERSION=2.10.x ./mirror.sh bootstrap
```

### Air-Gapped Transfer Workflow

1. Run `./mirror.sh all` on the connected side to populate your source Harbor project (`${HARBOR_HOST}/${HARBOR_PROJECT}`).
2. Use an OCI delta-transfer tool (e.g., `skopeo` / OCI layout export) to move delta blobs across the air gap into your isolated Harbor instance.
3. Inside the air-gapped clusters, Flux `OCIRepository` resources and Kyverno's `imagerewrite` policy resolve artifacts from `${HARBOR_REGISTRY}/${HARBOR_PROJECT}/...`.
