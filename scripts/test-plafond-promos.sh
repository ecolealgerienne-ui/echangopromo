#!/usr/bin/env bash
#
# Banc de concurrence — le plafond de 5 promos actives tient sous course.
#
# La race condition d'origine : deux créations quasi simultanées lisaient
# chacune un compte de 4 et passaient toutes les deux, aboutissant à 6 actives.
# Corrigée par un verrou consultatif Postgres — et jamais éprouvée depuis.
#
# ⚠️ **Un banc de course qui « passe » une fois ne prouve rien.** L'absence de
# collision peut tenir au hasard de l'ordonnancement, d'où plusieurs tours.
#
# Le détail et l'auto-test sont dans `lib/concurrence_plafond.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh    # puis coller le bloc export imprimé
#   ./scripts/test-plafond-promos.sh
#
#   TOURS=6 SIMULTANEES=4 ./scripts/test-plafond-promos.sh
#
# ⚠️ Ce banc ÉCRIT beaucoup : il crée et arrête des promos pour le commerçant
# du décor. À ne pas lancer contre une base qui n'est pas de test.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."
  exit 2
}

cd "$RACINE" || exit 2

echo "── auto-test du banc ──"
python3 "$HERE/lib/concurrence_plafond.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}

echo
exec python3 "$HERE/lib/concurrence_plafond.py" "$@"
