#!/usr/bin/env bash
# Builds a kubeconfig for the platform-ci ServiceAccount and prints it to stdout.

# Strict mode: exit on error (-e), error on unset variables (-u), fail on pipeline errors (pipefail).
set -euo pipefail

# Require two command-line arguments:
#   $1 : vSphere Supervisor namespace containing platform-ci-token
#   $2 : Supervisor Kubernetes API URL (e.g. https://10.0.0.10:6443)
NS="${1:?usage: buildkubeconfig.sh <vsphere-namespace> <supervisor-api-server-url>}"
SERVER="${2:?usage: buildkubeconfig.sh <vsphere-namespace> <supervisor-api-server-url>}"
SA=platform-ci

# Fetch the base64-encoded ServiceAccount token from the Secret and decode it to plain text.
TOKEN=$(kubectl -n "$NS" get secret platform-ci-token -o jsonpath='{.data.token}' | base64 -d)

# Fetch the cluster CA certificate (kept base64-encoded because kubeconfig's certificate-authority-data expects base64).
CA=$(kubectl -n "$NS" get secret platform-ci-token -o jsonpath='{.data.ca\.crt}')

# Print a complete kubeconfig YAML block to stdout using a heredoc (everything until the closing KUBECONFIG line).
cat <<KUBECONFIG
apiVersion: v1
kind: Config
clusters:
  - name: supervisor
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA}
contexts:
  - name: ${NS}
    context:
      cluster: supervisor
      namespace: ${NS}
      user: ${SA}
current-context: ${NS}
users:
  - name: ${SA}
    user:
      token: ${TOKEN}
KUBECONFIG
