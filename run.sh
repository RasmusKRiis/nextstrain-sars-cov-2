#!/usr/bin/env bash
# Run the Nextstrain ncov workflow for the configured lineages.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NCOV_DIR="${ROOT}/.ncov"
PROFILE_DIR="${ROOT}/profiles/lineage-builds"
DATA_DIR="${ROOT}/data"
OUT_DIR="${ROOT}/results"

LINEAGE_PREFIXES="${LINEAGE_PREFIXES:-XFG XEC JN.1 KP.3.1.1 LP.8.1 NB.1.8.1}"
NCOV_REF="${NCOV_REF:-master}"
CORES="${CORES:-4}"
INCLUDE_REFERENCE="${INCLUDE_REFERENCE:-0}"
: "${AUSPICE_PREFIX:=sars-cov-2}"
: "${AUSPICE_DIR:=${OUT_DIR}/auspice}"

copy_tree() {
  local src="$1"
  local dest="$2"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src" "$dest"
  else
    rm -rf "${dest%/}"
    mkdir -p "${dest%/}"
    cp -a "$src" "${dest%/}"
  fi
}

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

# Pick correct Snakefile
if [[ -f "${NCOV_DIR}/Snakefile" ]]; then
  SNAKEFILE="Snakefile"
elif [[ -f "${NCOV_DIR}/workflow/Snakefile" ]]; then
  SNAKEFILE="workflow/Snakefile"
elif [[ -f "${NCOV_DIR}/workflow/snakefile" ]]; then
  SNAKEFILE="workflow/snakefile"
else
  echo "❌ Cannot find Snakefile inside .ncov" >&2
  ls -la "${NCOV_DIR}" "${NCOV_DIR}/workflow" || true
  exit 1
fi

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

mapfile -t BUILD_INFO < <(
  python3 - <<'PY'
import yaml, pathlib
cfg = yaml.safe_load(pathlib.Path("profiles/lineage-builds/builds.yaml").read_text(encoding="utf-8"))
builds = cfg.get("builds", {})
for key, value in builds.items():
    title = value.get("title", key)
    print(f"{key}\t{title}")
PY
)

if [[ ${#BUILD_INFO[@]} -eq 0 || ( ${#BUILD_INFO[@]} -eq 1 && -z "${BUILD_INFO[0]}" ) ]]; then
  echo "⚠️ No builds with available sequences. Nothing to run."
  exit 0
fi

declare -a BUILD_KEYS=()
declare -A BUILD_TITLES=()
for line in "${BUILD_INFO[@]}"; do
  [[ -z "${line}" ]] && continue
  key="${line%%$'\t'*}"
  title="${line#*$'\t'}"
  BUILD_KEYS+=("${key}")
  BUILD_TITLES["${key}"]="${title}"
done

mkdir -p "${OUT_DIR}"
mkdir -p "${AUSPICE_DIR}"
rm -f "${AUSPICE_DIR}/"sars-cov-2_*.json 2>/dev/null || true

declare -a SUCCESS_BUILDS=()
declare -a SKIPPED_BUILDS=()
declare -a FAILED_BUILDS=()

for build_key in "${BUILD_KEYS[@]}"; do
  title="${BUILD_TITLES[${build_key}]}"
  echo "▶ Running build ${title} (${build_key})"

  pushd "${NCOV_DIR}" >/dev/null
  BUILD_CMD=(nextstrain build . --cores "${CORES}" --snakefile "${SNAKEFILE}" --config "${CONFIG_ARGS[@]}" "active_builds=${build_key}" --configfile "${BUILDS_CFG_REL}")
  if [[ -n "${REF_OVERLAY}" ]]; then
    BUILD_CMD+=(--configfile "profiles/lineage-builds/$(basename "${REF_OVERLAY}")")
  fi

  if "${BUILD_CMD[@]}"; then
    popd >/dev/null
    SUCCESS_BUILDS+=("${build_key}")

    # Copy per-build results
    if [[ -d "${NCOV_DIR}/results/${build_key}" ]]; then
      mkdir -p "${OUT_DIR}/${build_key}"
      copy_tree "${NCOV_DIR}/results/${build_key}/" "${OUT_DIR}/${build_key}/"
    fi

    # Copy shared artifacts
    for shared_file in \
      "${NCOV_DIR}/results/aligned_custom_data.fasta.xz" \
      "${NCOV_DIR}/results/sanitized_metadata_custom_data.tsv.xz"; do
      if [[ -f "${shared_file}" ]]; then
        cp -f "${shared_file}" "${OUT_DIR}/"
      fi
    done

    # Copy Auspice outputs
    if compgen -G "${NCOV_DIR}/auspice/sars-cov-2_${build_key}*.json" > /dev/null; then
      if command -v rsync >/dev/null 2>&1; then
        rsync -a "${NCOV_DIR}/auspice/sars-cov-2_${build_key}"*.json "${AUSPICE_DIR}/"
      else
        cp -a "${NCOV_DIR}/auspice/sars-cov-2_${build_key}"*.json "${AUSPICE_DIR}/"
      fi
    fi
  else
    popd >/dev/null
    log_file="${NCOV_DIR}/logs/filtered_${build_key}.txt"
    if [[ -f "${log_file}" ]] && grep -q "All samples have been dropped" "${log_file}"; then
      echo "⚠️ Skipping ${title}: all sequences were filtered out."
      SKIPPED_BUILDS+=("${build_key}")
      mkdir -p "${OUT_DIR}/${build_key}"
      cp -f "${log_file}" "${OUT_DIR}/${build_key}/" 2>/dev/null || true
      if [[ -d "${NCOV_DIR}/results/${build_key}" ]]; then
        cp -f "${NCOV_DIR}/results/${build_key}/excluded_by_diagnostics.txt" "${OUT_DIR}/${build_key}/" 2>/dev/null || true
      fi
    else
      echo "❌ Build ${title} failed. See logs in ${OUT_DIR}/${build_key}/logs/"
      FAILED_BUILDS+=("${build_key}")
      mkdir -p "${OUT_DIR}/${build_key}/logs"
      if [[ -d "${NCOV_DIR}/logs" ]]; then
        copy_tree "${NCOV_DIR}/logs/" "${OUT_DIR}/${build_key}/logs/"
      fi
      if [[ -d "${NCOV_DIR}/.snakemake/log" ]]; then
        copy_tree "${NCOV_DIR}/.snakemake/log/" "${OUT_DIR}/${build_key}/logs/snakemake/"
      fi
    fi
  fi

  # Reset intermediate outputs before the next build
  rm -rf "${NCOV_DIR}/results" "${NCOV_DIR}/auspice"
  mkdir -p "${NCOV_DIR}/results" "${NCOV_DIR}/auspice"
done

if [[ -n "${REF_OVERLAY}" ]]; then
  rm -f "${REF_OVERLAY}"
fi

# Remove stale build directories from previous runs
for dir in "${OUT_DIR}"/*/; do
  [[ ! -d "${dir}" ]] && continue
  base="$(basename "${dir}")"
  [[ "${base}" == "$(basename "${AUSPICE_DIR}")" ]] && continue
  keep=0
  for key in "${BUILD_KEYS[@]}"; do
    if [[ "${base}" == "${key}" ]]; then
      keep=1
      break
    fi
  done
  if [[ "${keep}" -eq 0 ]]; then
    rm -rf "${dir}"
  fi
done

echo "✅ Done."
if [[ ${#SUCCESS_BUILDS[@]} -gt 0 ]]; then
  echo "   Successful builds:"
  for key in "${SUCCESS_BUILDS[@]}"; do
    echo "    - ${BUILD_TITLES[${key}]} (${key})"
  done
fi
if [[ ${#SKIPPED_BUILDS[@]} -gt 0 ]]; then
  echo "   Skipped (no sequences passed filters):"
  for key in "${SKIPPED_BUILDS[@]}"; do
    echo "    - ${BUILD_TITLES[${key}]} (${key})"
  done
fi
if [[ ${#FAILED_BUILDS[@]} -gt 0 ]]; then
  echo "   Failed builds:"
  for key in "${FAILED_BUILDS[@]}"; do
    echo "    - ${BUILD_TITLES[${key}]} (${key})"
  done
fi
echo "👉 View locally: nextstrain view results/"

if [[ ${#FAILED_BUILDS[@]} -gt 0 ]]; then
  exit 1
fi
