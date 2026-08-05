#!/usr/bin/env python3
"""Résumé lisible d'un rapport JSON Semgrep."""
import json
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/semgrep_promo.json"
with open(path) as f:
    d = json.load(f)

results = d.get("results", [])
errors = d.get("errors", [])
scanned = len(d.get("paths", {}).get("scanned", []))

print(f"fichiers scannés : {scanned}")
print(f"findings bruts   : {len(results)}")
print(f"erreurs parsing  : {len(errors)}")
print("─" * 60)

by_sev = {}
for r in results:
    sev = r.get("extra", {}).get("severity", "?")
    by_sev.setdefault(sev, []).append(r)

for sev in ("ERROR", "WARNING", "INFO"):
    rows = by_sev.get(sev, [])
    if not rows:
        continue
    print(f"\n### {sev} ({len(rows)})")
    for r in rows:
        rule = r["check_id"].split(".")[-1]
        loc = f"{r['path']}:{r['start']['line']}"
        msg = r.get("extra", {}).get("message", "").split("\n")[0][:90]
        print(f"  - {loc}\n      règle : {rule}\n      {msg}")

if errors:
    print("\n### erreurs de parsing")
    for e in errors[:10]:
        print(f"  - {e.get('path','?')}: {e.get('message','')[:80]}")
