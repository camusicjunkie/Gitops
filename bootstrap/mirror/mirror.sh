#!/usr/bin/env bash
# Authenticate and mirror Flux distribution + bootstrap + platform artifacts into Harbor.
# Uses HARBOR_HOST, HARBOR_PROJECT, HARBOR_USERNAME, and HARBOR_PASSWORD
# (automatically populated by GitLab's Harbor integration).

# Strict mode: exit on error (-e), error on unset variables (-u), fail on pipeline errors (pipefail).
set -euo pipefail

# Absolute path to bootstrap/mirror/ so we can locate hosts.yaml, bootstrap.yaml, and platform.yaml from anywhere.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# First argument chooses what to mirror; defaults to "all" if no argument is passed.
SCOPE="${1:-all}"

# Flux version stream to mirror; uses existing FLUX_VERSION env var or defaults to "2.10.x".
FLUX_VERSION="${FLUX_VERSION:-2.10.x}"

# Verify all four Harbor environment variables are set and non-empty before doing any work.
# The ":?" syntax prints the message and aborts if a variable is missing.
: "${HARBOR_HOST:?HARBOR_HOST must be set}"
: "${HARBOR_PROJECT:?HARBOR_PROJECT must be set}"
: "${HARBOR_USERNAME:?HARBOR_USERNAME must be set}"
: "${HARBOR_PASSWORD:?HARBOR_PASSWORD must be set}"

# Create a temporary file to hold the rendered hosts.yaml (which contains credentials).
TMP_HOSTS="$(mktemp)"

# Ensure the temporary file is always deleted when the script exits (even if an error occurs).
trap 'rm -f "${TMP_HOSTS}"' EXIT

# Substitute ${VAR} placeholders in hosts.yaml with real environment variable values, then log in.
envsubst < "${DIR}/hosts.yaml" > "${TMP_HOSTS}"
flux mirror login -f "${TMP_HOSTS}"

# Helper function to render a mirror config file with envsubst and run `flux mirror sync`.
sync_config() {
  local src="$1"            # Path to the source YAML template (e.g. bootstrap.yaml)
  local rendered
  rendered="$(mktemp)"      # Temporary file for the rendered YAML
  envsubst < "${src}" > "${rendered}"
  flux mirror sync "${rendered}" --no-progress
  rm -f "${rendered}"       # Clean up the temporary file immediately
}

# Branch based on the requested scope argument.
case "${SCOPE}" in
  bootstrap)
    # Mirror core Flux controllers and manifests, then Day-0 bootstrap extras.
    flux operator distro mirror "${HARBOR_HOST}/${HARBOR_PROJECT}/flux" \
      --version "${FLUX_VERSION}" --variant upstream-alpine --immutable
    sync_config "${DIR}/bootstrap.yaml"
    ;;
  platform)
    # Mirror only steady-state application charts and container images.
    sync_config "${DIR}/platform.yaml"
    ;;
  all)
    # Mirror everything: Flux distro, bootstrap extras, and steady-state platform artifacts.
    flux operator distro mirror "${HARBOR_HOST}/${HARBOR_PROJECT}/flux" \
      --version "${FLUX_VERSION}" --variant upstream-alpine --immutable
    sync_config "${DIR}/bootstrap.yaml"
    sync_config "${DIR}/platform.yaml"
    ;;
  *)
    # Unknown argument: print usage to stderr (>&2) and exit with failure code 1.
    echo "Usage: $0 [bootstrap|platform|all]" >&2
    exit 1
    ;;
esac
