#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/commercant_dashboard.py`. `profileViewCount` compte des APPAREILS
# DISTINCTS (insert `orIgnore`), pas des consultations : un dédoublonnage qui
# saute ne casse rien, ne lève rien, et gonfle l'audience perçue du commerçant.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-commercant-dashboard.sh
#
# ⚠️ Ce banc ÉCRIT une trace de consultation (deux appareils fictifs, horodatés).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."; exit 2; }
cd "$RACINE" || exit 2
echo "── auto-test du banc ──"
python3 "$HERE/lib/commercant_dashboard.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."; exit 2; }
echo
exec python3 "$HERE/lib/commercant_dashboard.py" "$@"
