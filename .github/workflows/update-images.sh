#!/usr/bin/env bash
#
# Resolve and write the published multi-arch digest for every OpenBao
# image flavor at one version. Called by
# .github/workflows/update-images.yaml.
#
# Required env:
#   VERSION      - OpenBao version (e.g. v2.6.2)
#   REGISTRY     - image registry, e.g. ghcr.io/controlplaneio
# Optional env:
#   DISTRIBUTION - output file prefix (default: enterprise)
#
# Writes:
#   images/<version>/<DISTRIBUTION>-<variant>.yaml  (one per variant)

set -eoux pipefail

VERSION="${VERSION:?VERSION is required}"
REGISTRY="${REGISTRY:?REGISTRY is required}"
DISTRIBUTION="${DISTRIBUTION:-enterprise}"

VARIANTS=( ubi ubi-fips distroless distroless-fips )

ROOT_DIR="$(git rev-parse --show-toplevel)"
WORK_DIR="${ROOT_DIR}/images/${VERSION}"
mkdir -p "${WORK_DIR}"

for variant in "${VARIANTS[@]}"; do
  repo="${REGISTRY}/${variant}/openbao"
  digest="$(docker buildx imagetools inspect "${repo}:${VERSION}" \
    --format '{{json .}}' | jq -r .manifest.digest)"
  [ -n "$digest" ] && [ "$digest" != "null" ] || {
    echo "no digest for ${repo}:${VERSION}" >&2
    exit 1
  }
  out="${WORK_DIR}/${DISTRIBUTION}-${variant}.yaml"
  cat >"${out}" <<EOF
images:
  - name: ${repo}
    newTag: ${VERSION}
    digest: ${digest}
EOF
  echo "wrote ${out}"
  cat "${out}"
done
