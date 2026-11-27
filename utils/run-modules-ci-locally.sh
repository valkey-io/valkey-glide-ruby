#!/usr/bin/env bash
# Usage:
#   utils/run-modules-ci-locally.sh                                  # image's search module, EMULATE_RELEASE 1.3.0
#   EMULATE_RELEASE="" utils/run-modules-ci-locally.sh               # image's search module, module's own release level
#   IMAGE=valkey/valkey-bundle:9.1.3 SEARCH_MODULE_PATH="" EMULATE_RELEASE="" utils/run-modules-ci-locally.sh   # image's bundled search module
#
# Environment variables:
#   IMAGE               Valkey bundle image (default valkey/valkey-bundle:9.2.0-rc2)
#   ENGINE_VERSION      Valkey engine version (default 9.0)
#   CLUSTER_PORT_START  First of six cluster ports (default 8101)
#   STANDALONE_PORT     Standalone port (default 6489)
#   SEARCH_MODULE_PATH  Search module .so mounted over the image's own module (default: empty, the image's own module)
#   EMULATE_RELEASE     search.emulate-release level as X.Y.Z (default 1.3.0; empty: module default)
#
# Required tools: docker (on macOS, Docker Desktop with host networking enabled), valkey-cli.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_DIR="${REPO_ROOT}/.module-ci-local-scratch"
mkdir -p "$SCRATCH_DIR"

IMAGE="${IMAGE:-valkey/valkey-bundle:9.2.0-rc2}"
ENGINE_VERSION="${ENGINE_VERSION:-9.0}"
CLUSTER_PORT_START="${CLUSTER_PORT_START:-8101}"
STANDALONE_PORT="${STANDALONE_PORT:-6489}"
SEARCH_MODULE_PATH="${SEARCH_MODULE_PATH-}"
EMULATE_RELEASE="${EMULATE_RELEASE-1.3.0}"

if [ -n "$EMULATE_RELEASE" ] && ! [[ "$EMULATE_RELEASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: EMULATE_RELEASE must be X.Y.Z (e.g. 1.3.0) or empty, got: ${EMULATE_RELEASE}" >&2
    exit 1
fi

cleanup() {
    echo "=== Tearing down module containers ==="
    docker rm -f valkey-rb-modules-standalone >/dev/null 2>&1 || true
    for port in $(seq "$CLUSTER_PORT_START" "$((CLUSTER_PORT_START + 5))"); do
        docker rm -f "valkey-rb-modules-cluster-${port}" >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

echo "=== Starting module servers (IMAGE=${IMAGE}, SEARCH_MODULE_PATH=${SEARCH_MODULE_PATH:-<image default>}, EMULATE_RELEASE=${EMULATE_RELEASE:-<module default>}) ==="
export IMAGE ENGINE_VERSION CLUSTER_PORT_START STANDALONE_PORT SCRATCH_DIR SEARCH_MODULE_PATH
if [ -n "$EMULATE_RELEASE" ]; then
    export SEARCH_MODULE_ARGS="--emulate-release ${EMULATE_RELEASE}"
else
    export SEARCH_MODULE_ARGS=""
fi
ENV_CAPTURE="${SCRATCH_DIR}/env-capture"
GITHUB_ENV="$ENV_CAPTURE" "${REPO_ROOT}/utils/start-valkey-docker-modules.sh"
# shellcheck disable=SC1090
source "$ENV_CAPTURE"
rm -f "$ENV_CAPTURE"

echo "=== Liveness: valkey_version, MODULE LIST, search.emulate-release ==="
for port in "$STANDALONE_PORT" $(seq "$CLUSTER_PORT_START" "$((CLUSTER_PORT_START + 5))"); do
    echo "--- port $port ---"
    valkey-cli -p "$port" INFO server | grep -i valkey_version
    valkey-cli -p "$port" MODULE LIST
    valkey-cli -p "$port" CONFIG GET search.emulate-release
done

echo "=== Running module tests ==="
cd "$REPO_ROOT"
MODULES_STANDALONE_ENDPOINT="$MODULES_STANDALONE_ENDPOINT" \
    MODULES_CLUSTER_ENDPOINTS="$MODULES_CLUSTER_ENDPOINTS" \
    bundle exec rake test:modules
