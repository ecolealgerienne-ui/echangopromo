#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/promo_cycle.py` : quatre règles anti-abus qui ne se
# déclenchent qu'au cinquième geste, à 24 h d'écart ou au septième jour —
# c'est-à-dire jamais pendant un développement, et toujours en production.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-promo-cycle.sh
#
# ⚠️ Ce banc ÉCRIT beaucoup : il crée plusieurs promos jusqu'à épuiser le
# plafond quotidien du commerçant du décor. Celui-ci ne pourra donc plus rien
# créer pendant 24 h — lancer ce banc EN DERNIER, ou sur un décor jetable.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."; exit 2; }
cd "$RACINE" || exit 2
echo "── auto-test du banc ──"
python3 "$HERE/lib/promo_cycle.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."; exit 2; }
echo
exec python3 "$HERE/lib/promo_cycle.py" "$@"
