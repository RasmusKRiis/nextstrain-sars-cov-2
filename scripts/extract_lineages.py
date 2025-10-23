#!/usr/bin/env python3
"""
Expand lineage families (prefixes) like XFG/XEC into explicit lists using a local
pangolin overview file if present (data/LineageDescription.txt), otherwise fetch
the latest lineage_notes.txt from pango-designation. Then render builds.yaml by
injecting build blocks into a template.
"""
import argparse, pathlib, urllib.request, urllib.error, re, sys
RAW_URL = "https://raw.githubusercontent.com/cov-lineages/pango-designation/master/lineage_notes.txt"

def load_metadata_lineages(path: pathlib.Path | None) -> set[str]:
    if not path or not path.exists():
        return set()
    try:
        fh = path.open(encoding="utf-8")
    except OSError:
        return set()
    with fh:
        header = fh.readline().rstrip("\n").split("\t")
        try:
            idx = header.index("pango_lineage")
        except ValueError:
            try:
                idx = header.index("pangolin_lineage")
            except ValueError:
                return set()
        lineages: set[str] = set()
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if idx < len(parts):
                lineage = parts[idx].strip()
                if lineage:
                    lineages.add(lineage)
    return lineages

def load_lines(path: pathlib.Path | None) -> list[str]:
    if path and path.exists():
        return path.read_text(encoding="utf-8", errors="ignore").splitlines()
    try:
        with urllib.request.urlopen(RAW_URL) as r:
            return r.read().decode("utf-8", errors="ignore").splitlines()
    except urllib.error.URLError as err:
        print(f"Warning: could not fetch lineage notes ({err}). Continuing without remote lineage expansion.", file=sys.stderr)
        return []

TOKEN_RE = re.compile(r"^[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)*$")

def collect_prefix(lines: list[str], prefix: str, metadata_lineages: set[str] | None = None) -> list[str]:
    want: list[str] = []
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        tok = line.split()[0]
        if TOKEN_RE.match(tok) and (tok == prefix or tok.startswith(prefix + ".")):
            want.append(tok)
    if prefix not in want:
        want = [prefix] + want
    # stable unique
    seen, out = set(), []
    for t in want:
        if t not in seen:
            seen.add(t)
            out.append(t)
    if metadata_lineages:
        for lineage in metadata_lineages:
            if lineage == prefix or lineage.startswith(prefix + "."):
                if lineage not in seen:
                    seen.add(lineage)
                    out.append(lineage)
    return out

def pylist(items: list[str]) -> str:
    return "[" + ", ".join("'" + x + "'" for x in items) + "]"

def sanitize_prefix(prefix: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]+", "_", prefix)


def build_block(prefix: str, lineage_list: list[str]) -> str:
    safe_prefix = sanitize_prefix(prefix)
    return f"""  {safe_prefix}:
    title: "SARS-CoV-2 — {prefix}"
    subsampling_scheme: by-pango-list
    pango_lineage: {pylist(lineage_list)}
"""

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefix", nargs="+", required=True, help="Lineage family prefixes (e.g., XFG XEC BA.2.86)")
    ap.add_argument("--infile", default="data/LineageDescription.txt", help="Local pangolin overview (optional)")
    ap.add_argument("--template", default="profiles/lineage-builds/builds.template.yaml")
    ap.add_argument("--outfile",  default="profiles/lineage-builds/builds.yaml")
    ap.add_argument("--metadata", default="data/custom.metadata.tsv", help="Metadata file used to confirm available sequences")
    args = ap.parse_args()

    lines = load_lines(pathlib.Path(args.infile))
    metadata_lineages = load_metadata_lineages(pathlib.Path(args.metadata))
    blocks = []
    selected: list[str] = []
    for p in args.prefix:
        lst = collect_prefix(lines, p, metadata_lineages)
        if metadata_lineages:
            has_data = any(
                lineage == p or lineage.startswith(p + ".")
                for lineage in metadata_lineages
            )
            if not has_data:
                print(f"Skipping {p}: no sequences found in metadata", file=sys.stderr)
                continue
        blocks.append(build_block(p, lst))
        selected.append(p)

    tpl = pathlib.Path(args.template).read_text(encoding="utf-8")
    rendered = tpl.replace("__BUILDS__", "".join(blocks).rstrip())
    pathlib.Path(args.outfile).write_text(rendered, encoding="utf-8")
    print(f"Wrote {args.outfile}")
    for p in selected:
        print(f"  {p} OK")

if __name__ == "__main__":
    sys.exit(main())
