#!/usr/bin/env bash
# Re-vendor the Kubernetes Gateway API CRDs from upstream.
# Usage: ./update.sh <tag>   e.g. ./update.sh v1.2.1
# Review the resulting git diff before committing.

# Strict mode:
#   -e : stop the script immediately if any command fails
#   -u : treat unset variables as an error instead of empty strings
#   -o pipefail : fail a pipeline if any command in it fails (not just the last one)
set -euo pipefail

# Read the first command-line argument ($1). If it wasn't provided, print the usage message and exit.
TAG="${1:?usage: ./update.sh <tag>}"

# Resolve the absolute directory where this script lives so output paths work regardless of where you run it from.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Download the official Gateway API CRD bundle:
#   -f : fail on HTTP errors (e.g. 404) instead of saving an error page
#   -sS : silent progress bar, but still show errors
#   -L : follow HTTP redirects (GitHub release URLs redirect to a CDN)
#   -o : write the downloaded file directly to crds.yaml in this script's folder
curl -fsSL "https://github.com/kubernetes-sigs/gateway-api/releases/download/${TAG}/standard-install.yaml" \
  -o "${DIR}/crds.yaml"

echo "Vendored Gateway API CRDs at ${TAG}. Review 'git diff' before committing."
