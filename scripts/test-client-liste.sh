#!/usr/bin/env bash
#
# Banc de la liste client — une seule définition de « visible », zéro fuite.
#
# Deux défauts réels y sont nés : `photoKey` qui fuyait dans la réponse (un
# spread désactive les @Exclude, règle 4), et « visible » qui avait DEUX
# définitions — une promo arrêtée restait consultable par quiconque avait le
# lien. La sonde centrale fait BASCULER une promo et vérifie que la liste et le
# détail disent la même chose : c'est le seul moyen de voir deux définitions
# diverger, puisqu'elles ne se contredisent que sur les cas limites.
#
# Le détail et l'auto-test sont dans `lib/client_liste.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh
#   # … coller le bloc export, attendre une minute …
#   ./scripts/test-client-liste.sh
#
# ⚠️ Ce banc ÉCRIT : il crée une promo (par l'agent, exempté du plafond
# quotidien) et l'arrête. Elle reste arrêtée — elle appartient au banc.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."
  exit 2
}

cd "$RACINE" || exit 2

echo "── auto-test du banc ──"
python3 "$HERE/lib/client_liste.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}

echo
exec python3 "$HERE/lib/client_liste.py" "$@"
