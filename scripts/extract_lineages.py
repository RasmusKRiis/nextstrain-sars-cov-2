#!/usr/bin/env python3
"""
Expand lineage families (prefixes) like XFG/XEC into explicit lists using a local
pangolin overview file if present (data/LineageDescription.txt), otherwise fetch
the latest lineage_notes.txt from pango-designation. Then render builds.yaml by
injecting build blocks into a template.
"""
import argparse, pathlib, urllib.request, re, sys
RAW_URL = "https://raw.githubusercontent.com/cov-lineages/pango-designation/master/lineage_notes.txt"

def load_lines(path: pathlib.Path | None) -> list[str]:
    if path and path.exists():
        return path.read_text(encoding="utf-8", errors="ignore").splitlines()
    with urllib.request.urlopen(RAW_URL) as r:
        return r.read().decode("utf-8", errors="ignore").splitlines()

TOKEN_RE = re.compile(r"^[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)*$")

def collect_prefix(lines: list[str], prefix: str) -> list[str]:
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
    return out

def pylist(items: list[str]) -> str:
    return "[" + ", ".join("'" + x + "'" for x in items) + "]"

def build_block(prefix: str, lineage_list: list[str]) -> str:
    return f"""  {prefix}:
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
    args = ap.parse_args()

    lines = load_lines(pathlib.Path(args.infile))
    blocks = []
    for p in args.prefix:
        lst = collect_prefix(lines, p)
        blocks.append(build_block(p, lst))

    tpl = pathlib.Path(args.template).read_text(encoding="utf-8")
    rendered = tpl.replace("__BUILDS__", "".join(blocks).rstrip())
    pathlib.Path(args.outfile).write_text(rendered, encoding="utf-8")
    print(f"Wrote {args.outfile}")
    for p in args.prefix:
        print(f"  {p} OK")

if __name__ == "__main__":
    sys.exit(main())
