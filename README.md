# nextstrain-sars-cov-2

Minimal, future-proof Nextstrain runner for SARS-CoV-2 that:
- takes **one combined** metadata + FASTA,
- builds one dataset **per lineage family** (e.g., XFG, XEC),
- auto-expands sublineages (e.g., XFG.* / XEC.*) from `lineage_notes.txt` (local or latest upstream),
- clones the official **nextstrain/ncov** fresh each run.

## Requirements
- Nextstrain CLI installed and configured (`nextstrain check-setup`)
- Python 3.9+ and `git`
- (Optional) GitHub CLI `gh` if you want auto-create & push

## Quick start
1) Add your inputs:
```
data/custom.metadata.tsv
data/custom.sequences.fasta
# optional local Pango overview; otherwise we'll fetch upstream
data/LineageDescription.txt
```

2) Run (defaults to XFG and XEC):
```bash
bash run.sh
```
Or specify other families:
```bash
LINEAGE_PREFIXES="XFG XEC BA.2.86" bash run.sh
```

3) View results:
- Auspice JSON files in `results/`.
- Serve them locally: `nextstrain view results/`

## Notes
- Each build filters by `pangolin_lineage in {pangolin_lineage}` (expanded list).
- You can add or remove families at run-time via `LINEAGE_PREFIXES="..."`.
- We clone `.ncov/` fresh every run to stay current; pin with `NCOV_REF=v13.0.0` for stability.
- Override `AUSPICE_PREFIX` (default `sars-cov-2`) or `AUSPICE_DIR` (default `results/auspice/`) if you need custom Auspice naming or destination paths.
