#!/usr/bin/env bash
# Run Nextstrain ncov for one or more lineage families from a single combined input.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NCOV_DIR="${ROOT}/.ncov"
PROFILE_DIR="${ROOT}/profiles/lineage-builds"
DATA_DIR="${ROOT}/data"
OUT_DIR="${ROOT}/results"

# Runtime options (env-overridable)
LINEAGE_PREFIXES="${LINEAGE_PREFIXES:-XFG XEC}"   # space-separated lineage families
NCOV_REF="${NCOV_REF:-main}"                      # tag/branch/commit (main by default)
CORES="${CORES:-4}"                               # snakemake cores
INCLUDE_REFERENCE="${INCLUDE_REFERENCE:-0}"       # 1 to also include tutorial reference dataset

# Sanity checks for required inputs
[[ -f "${DATA_DIR}/custom.metadata.tsv" ]] || { echo "Missing ${DATA_DIR}/custom.metadata.tsv"; exit 1; }
[[ -f "${DATA_DIR}/custom.sequences.fasta" ]] || { echo "Missing ${DATA_DIR}/custom.sequences.fasta"; exit 1; }

# 1) Fresh clone of official workflow
rm -rf "${NCOV_DIR}"
git clone --depth 1 --branch "${NCOV_REF}" https://github.com/nextstrain/ncov.git "${NCOV_DIR}"

# 2) Render builds.yaml from template, expanding lineage lists
python3 "${ROOT}/scripts/extract_lineages.py" \
  --prefix ${LINEAGE_PREFIXES} \
  --infile "${DATA_DIR}/LineageDescription.txt" \
  --template "${PROFILE_DIR}/builds.template.yaml" \
  --outfile "${PROFILE_DIR}/builds.yaml"

# Optional: add reference dataset via a small overlay
REF_OVERLAY=""
if [[ "${INCLUDE_REFERENCE}" == "1" ]]; then
  REF_OVERLAY="$(mktemp)"
  cat > "${REF_OVERLAY}" <<'YAM'
inputs:
  - name: reference_data
    metadata: https://data.nextstrain.org/files/ncov/open/reference/metadata.tsv.xz
    sequences: https://data.nextstrain.org/files/ncov/open/reference/sequences.fasta.xz
YAM
fi

# 3) Run the build
pushd "${NCOV_DIR}" >/dev/null
if [[ -n "${REF_OVERLAY}" ]]; then
  nextstrain build . --cores "${CORES}" \
    --configfile "${PROFILE_DIR}/builds.yaml" \
    --configfile "${REF_OVERLAY}"
else
  nextstrain build . --cores "${CORES}" \
    --configfile "${PROFILE_DIR}/builds.yaml"
fi
popd >/dev/null

# 4) Collect outputs
mkdir -p "${OUT_DIR}"
cp -v "${NCOV_DIR}"/auspice/*.json "${OUT_DIR}/" || true

echo "✅ Done. Auspice JSON written to ${OUT_DIR}/"
echo "👉 Serve locally with: nextstrain view results/"
