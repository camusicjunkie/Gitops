# vSphere Supervisor CI Access (`SUPERVISOR_KUBECONFIG`)

This directory provisions a **long-lived Kubernetes `ServiceAccount`** inside a vSphere Supervisor Namespace so the GitLab CI bootstrap pipeline (`.gitlab-ci.yml`) can:

1. Wait for a newly provisioned VKS `Cluster` object (`clusters.cluster.x-k8s.io`) to reach `Ready`.
2. Read the generated `${CLUSTER}-kubeconfig` `Secret` for that workload cluster and pass it to OpenTofu (`bootstrap/vks/`).

## Why a ServiceAccount Instead of `kubectl vsphere login`?

`kubectl vsphere login` issues short-lived vCenter SSO tokens that expire after a few hours, which causes unattended GitLab CI/CD runs to fail. Creating a dedicated `ServiceAccount` with a `kubernetes.io/service-account-token` `Secret` gives CI a stable, namespace-scoped credential that does not depend on interactive SSO.

---

## Files in This Directory

| File | Resource | Purpose |
| :--- | :--- | :--- |
| [`serviceaccount.yaml`](serviceaccount.yaml) | `ServiceAccount` (`platform-ci`) | Dedicated identity for GitLab CI in the target vSphere Namespace |
| [`rbac.yaml`](rbac.yaml) | `Role` + `RoleBinding` (`platform-ci-cluster-manager`) | Grants access to `clusters.cluster.x-k8s.io` and `secrets` in that namespace only |
| [`token.yaml`](token.yaml) | `Secret` (`platform-ci-token`) | Long-lived `kubernetes.io/service-account-token` bound to `platform-ci` |
| [`buildkubeconfig.sh`](buildkubeconfig.sh) | Helper script | Extracts the token and CA cert from `platform-ci-token` and prints a standalone kubeconfig |

---

## Setup Instructions

Run these steps once per vSphere Namespace using an administrator context (VI Admin or Namespace Owner).

### 1. Set Your Target Namespace & Apply Manifests

Replace `<vsphere-namespace>` with your actual vSphere Supervisor Namespace (the same value you will set for `VSPHERE_NS` in GitLab CI/CD):

```bash
export VSPHERE_NS="<your-vsphere-namespace>"

for f in serviceaccount.yaml rbac.yaml token.yaml; do
  sed "s/<vsphere-namespace>/${VSPHERE_NS}/g" "$f" | kubectl apply -f -
done
```

> [!TIP]
> **Least-Privilege Option**: If another management cluster or team creates CAPI `Cluster` objects and this repo's pipeline only *reads* readiness and kubeconfigs, tighten `rbac.yaml` `clusters` verbs to `["get", "list", "watch"]`.

### 2. Generate the Kubeconfig

Find your Supervisor API server URL (`kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'`) and run:

```bash
./buildkubeconfig.sh "${VSPHERE_NS}" "https://<supervisor-api-vip>:6443" > /tmp/supervisor.kubeconfig
chmod 600 /tmp/supervisor.kubeconfig
```

### 3. Verify Permissions

Confirm the generated kubeconfig works and is strictly scoped to `${VSPHERE_NS}`:

```bash
export KUBECONFIG=/tmp/supervisor.kubeconfig
kubectl -n "${VSPHERE_NS}" get clusters
kubectl -n "${VSPHERE_NS}" auth can-i get secrets
kubectl get namespaces   # Should be forbidden (namespace-scoped only)
```

### 4. Store in GitLab CI/CD

In your GitLab Project (or Group) under **Settings → CI/CD → Variables**:

1. **`SUPERVISOR_KUBECONFIG`**
   * **Type**: `File`
   * **Flags**: `Protect variable` (recommended; only runs on protected branches/tags)
   * **Value**: Contents of `/tmp/supervisor.kubeconfig`
2. **`VSPHERE_NS`**
   * **Type**: `Variable`
   * **Value**: `<your-vsphere-namespace>`

Delete `/tmp/supervisor.kubeconfig` from your local workstation once saved in GitLab.

---

## Token Rotation

To rotate the `platform-ci` credential without interrupting cluster workloads:

1. Delete and recreate `platform-ci-token` in `${VSPHERE_NS}`:
   ```bash
   kubectl -n "${VSPHERE_NS}" delete secret platform-ci-token
   sed "s/<vsphere-namespace>/${VSPHERE_NS}/g" token.yaml | kubectl apply -f -
   ```
2. Re-run `./buildkubeconfig.sh` and update `SUPERVISOR_KUBECONFIG` in GitLab CI/CD.
