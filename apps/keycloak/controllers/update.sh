#!/usr/bin/env bash
# Re-vendor the Keycloak operator manifests from upstream.
# Usage: ./update.sh <tag>   e.g. ./update.sh 26.8.2
# Review the resulting git diff before committing — that is the point of
# vendoring (you see exactly what upstream changed before it reaches the
# cluster). Local files (namespace.yaml, kustomization.yaml) are NOT touched.

# Strict mode: exit on error (-e), error on unset variables (-u), fail on pipeline errors (pipefail).
set -euo pipefail

# Require the version tag as the first argument ($1), or print usage and exit.
TAG="${1:?usage: ./update.sh <tag>}"

# Base GitHub raw URL for the requested Keycloak cluster-wide release tag.
BASE="https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${TAG}/kubernetes/cluster-wide"

# Absolute path to the directory containing this script.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Download each upstream YAML file (-f fail on HTTP error, -sS quiet unless error, -L follow redirects).
# Dash-free filenames are used locally to match repository conventions.
curl -fsSL "${BASE}/keycloaks.k8s.keycloak.org-v1.yml"            -o "${DIR}/crds/keycloaks.k8s.keycloak.org.yml"
curl -fsSL "${BASE}/keycloakrealmimports.k8s.keycloak.org-v1.yml" -o "${DIR}/crds/keycloakrealmimports.k8s.keycloak.org.yml"
curl -fsSL "${BASE}/keycloakoidcclients.k8s.keycloak.org-v1.yml"  -o "${DIR}/crds/keycloakoidcclients.k8s.keycloak.org.yml"
curl -fsSL "${BASE}/keycloaksamlclients.k8s.keycloak.org-v1.yml"  -o "${DIR}/crds/keycloaksamlclients.k8s.keycloak.org.yml"
curl -fsSL "${BASE}/kubernetes.yml"                               -o "${DIR}/operator.yml"

echo "Vendored Keycloak operator manifests at ${TAG}. Review 'git diff' before committing."
