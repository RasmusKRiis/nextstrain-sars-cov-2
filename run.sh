#!/usr/bin/env bash
# Run the Nextstrain ncov workflow for the configured lineages.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NCOV_DIR="${ROOT}/.ncov"
PROFILE_DIR="${ROOT}/profiles/lineage-builds"
DATA_DIR="${ROOT}/data"
OUT_DIR="${ROOT}/results"

LINEAGE_PREFIXES="${LINEAGE_PREFIXES:-XFG XEC}"
NCOV_REF="${NCOV_REF:-master}"
CORES="${CORES:-4}"
INCLUDE_REFERENCE="${INCLUDE_REFERENCE:-0}"
: "${AUSPICE_PREFIX:=sars-cov-2}"

[[ -f "${DATA_DIR}/custom.metadata.tsv" ]] || { echo "Missing ${DATA_DIR}/custom.metadata.tsv"; exit 1; }
[[ -f "${DATA_DIR}/custom.sequences.fasta" ]] || { echo "Missing ${DATA_DIR}/custom.sequences.fasta"; exit 1; }

rm -rf "${NCOV_DIR}"
if ! git clone --depth 1 --branch "${NCOV_REF}" https://github.com/nextstrain/ncov.git "${NCOV_DIR}"; then
  echo "⚠️ Falling back to master"
  git clone --depth 1 --branch master https://github.com/nextstrain/ncov.git "${NCOV_DIR}"
fi

if [[ -f "${DATA_DIR}/LineageDescription.txt" ]]; then
  python3 "${ROOT}/scripts/extract_lineages.py" \
    --prefix ${LINEAGE_PREFIXES} \
    --infile "${DATA_DIR}/LineageDescription.txt" \
    --template "${PROFILE_DIR}/builds.template.yaml" \
    --outfile "${PROFILE_DIR}/builds.yaml"
else
  python3 "${ROOT}/scripts/extract_lineages.py" \
    --prefix ${LINEAGE_PREFIXES} \
    --template "${PROFILE_DIR}/builds.template.yaml" \
    --outfile "${PROFILE_DIR}/builds.yaml"
fi
echo "Wrote ${PROFILE_DIR}/builds.yaml"

mkdir -p "${NCOV_DIR}/data" "${NCOV_DIR}/profiles/lineage-builds"
cp "${DATA_DIR}/custom.metadata.tsv" "${NCOV_DIR}/data/"
cp "${DATA_DIR}/custom.sequences.fasta" "${NCOV_DIR}/data/"
cp -f "${PROFILE_DIR}/"* "${NCOV_DIR}/profiles/lineage-builds/"

BUILDS_CFG_REL="profiles/lineage-builds/builds.yaml"
REF_OVERLAY=""

if [[ "${INCLUDE_REFERENCE}" == "1" ]]; then
  REF_OVERLAY="${NCOV_DIR}/profiles/lineage-builds/reference.overlay.yaml"
  cat > "${REF_OVERLAY}" <<'YAM'
inputs:
  - name: reference_data
    metadata: https://data.nextstrain.org/files/ncov/open/reference/metadata.tsv.xz
    sequences: https://data.nextstrain.org/files/ncov/open/reference/sequences.fasta.xz
YAM
fi

CONFIG_ARGS=(
  "auspice_json_prefix=${AUSPICE_PREFIX}"
)

pushd "${NCOV_DIR}" >/dev/null
CMD=(nextstrain build . --cores "${CORES}" --config "${CONFIG_ARGS[@]}" --configfile "${BUILDS_CFG_REL}")
if [[ -n "${REF_OVERLAY}" ]]; then
  CMD+=(--configfile "profiles/lineage-builds/$(basename "${REF_OVERLAY}")")
fi
"${CMD[@]}"
popd >/dev/null

mkdir -p "${OUT_DIR}"
cp -v "${NCOV_DIR}"/auspice/*.json "${OUT_DIR}/" 2>/dev/null || true

if [[ -n "${REF_OVERLAY}" ]]; then
  rm -f "${REF_OVERLAY}"
fi

echo "✅ Done. Auspice JSON in ${OUT_DIR}/"
echo "👉 View locally: nextstrain view results/"
