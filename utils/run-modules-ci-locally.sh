#!/usr/bin/env bash
# Runs this repo's module tests (test/integration/modules/) against a
# Docker-based standalone + cluster Valkey deployment with real valkey-search
# modules loaded -- not the vendored RediSearch .so test/support/ files use
# for the rest of the suite. Adapted from valkey-glide's
# utils/run-modules-ci-locally.sh. ci.yml's existing module-tests job already
# runs the vendored-.so-backed Module/Json/VectorSearch lint tests against
# valkey-bundle:9.1.3 via the shared start-valkey-docker action; this script
# is for the valkey-search 1.3 surface specifically, which needs a
# source-built rc2 .so (BUILD-MODULES-1.3.md) that no bundle tag ships.
#
# Usage: three image/release combinations, matching the port's three
# required local configurations:
#   utils/run-modules-ci-locally.sh                                                    # 1: rc2, emulate-release 1.3.0
#   EMULATE_RELEASE="" utils/run-modules-ci-locally.sh                                  # 2: rc2, module's own default (1.0.0)
#   IMAGE=valkey/valkey-bundle:9.1.3 SEARCH_MODULE_PATH="" EMULATE_RELEASE="" \
#     utils/run-modules-ci-locally.sh                                                   # 3: 9.1.3 (search 1.2.1), 1.3 tests skip
#
# SEARCH_MODULE_PATH defaults to the pre-built rc2 .so from
# BUILD-MODULES-1.3.md (tools/module-src/valkey-search/.build-release/
# libsearch.so in the parent Glide/ directory) so configs 1 and 2 use the
# real rc2 binary, not the 9.1.3 bundle image's bundled 1.2.1 module. Set it
# to an empty string to use the image's own module unmodified (config 3).
#
# Requires: docker, valkey-cli (Homebrew: `brew install valkey`), and
# shlock (around any local module-CI run -- see the port's CI-flakes rule:
# the container names here are fixed, so parallel runs across languages
# collide; take /tmp/glide-modules-ci.lock before invoking this script).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_DIR="${REPO_ROOT}/.module-ci-local-scratch"
mkdir -p "$SCRATCH_DIR"

IMAGE="${IMAGE:-valkey/valkey-bundle:9.2.0-rc2}"
ENGINE_VERSION="${ENGINE_VERSION:-9.0}"
CLUSTER_PORT_START="${CLUSTER_PORT_START:-8101}"
STANDALONE_PORT="${STANDALONE_PORT:-6489}"
DEFAULT_RC2_SO="$(cd "${REPO_ROOT}/.." && pwd)/tools/module-src/valkey-search/.build-release/libsearch.so"
SEARCH_MODULE_PATH="${SEARCH_MODULE_PATH-${DEFAULT_RC2_SO}}"
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
