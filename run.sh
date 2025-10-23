#!/usr/bin/env bash
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

[[ -f "${DATA_DIR}/custom.metadata.tsv" ]] || { echo "Missing ${DATA_DIR}/custom.metadata.tsv"; exit 1; }
[[ -f "${DATA_DIR}/custom.sequences.fasta" ]] || { echo "Missing ${DATA_DIR}/custom.sequences.fasta"; exit 1; }

rm -rf "${NCOV_DIR}"
if ! git clone --depth 1 --branch "${NCOV_REF}" https://github.com/nextstrain/ncov.git "${NCOV_DIR}"; then
  echo "⚠️ Falling back to master"
  git clone --depth 1 --branch master https://github.com/nextstrain/ncov.git "${NCOV_DIR}"
fi

# Generate lineage-aware builds.yaml
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

# Pick correct Snakefile
if [[ -f ".ncov/Snakefile" ]]; then
  SNAKEFILE=".ncov/Snakefile"
elif [[ -f ".ncov/workflow/Snakefile" ]]; then
  SNAKEFILE=".ncov/workflow/Snakefile"
elif [[ -f ".ncov/workflow/snakefile" ]]; then
  SNAKEFILE=".ncov/workflow/snakefile"
else
  echo "❌ Cannot find Snakefile inside .ncov" >&2
  ls -la .ncov .ncov/workflow || true
  exit 1
fi

# Ensure required defaults are loaded (provides auspice_json_prefix, etc.)
DEFAULTS_CFG=".ncov/defaults/parameters.yaml"
CONDA_ENV="workflow/envs/nextstrain.yaml"

mkdir -p "${OUT_DIR}"

if [[ "${INCLUDE_REFERENCE}" == "1" ]]; then
  cat > "${PROFILE_DIR}/reference.overlay.yaml" <<'YAM'
inputs:
  - name: reference_data
    metadata: https://data.nextstrain.org/files/ncov/open/reference/metadata.tsv.xz
    sequences: https://data.nextstrain.org/files/ncov/open/reference/sequences.fasta.xz
YAM
  nextstrain build . --cores "${CORES}" --use-conda \
    --snakefile "${SNAKEFILE}" \
    --config conda_environment="${CONDA_ENV}" \
    --configfile "${DEFAULTS_CFG}" \
    --configfile "profiles/lineage-builds/builds.yaml" \
    --configfile "profiles/lineage-builds/reference.overlay.yaml"
else
  nextstrain build . --cores "${CORES}" --use-conda \
    --snakefile "${SNAKEFILE}" \
    --config conda_environment="${CONDA_ENV}" \
    --configfile "${DEFAULTS_CFG}" \
    --configfile "profiles/lineage-builds/builds.yaml"
fi

# Collect outputs (depending on where ncov writes them)
cp -v auspice/*.json "${OUT_DIR}/" 2>/dev/null || true
cp -v "${NCOV_DIR}"/auspice/*.json "${OUT_DIR}/" 2>/dev/null || true

echo "✅ Done. Auspice JSON in ${OUT_DIR}/"
echo "👉 View locally: nextstrain view results/"
