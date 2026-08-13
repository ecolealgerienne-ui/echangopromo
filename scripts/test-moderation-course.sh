#!/usr/bin/env bash
#
# Banc de la course de modération — deux modérateurs, une seule promo.
#
# Éprouve la garde posée le 2026-08-13 : chaque décision de modération porte
# l'état que le modérateur avait à l'écran, et l'écriture y est conditionnée.
# Sans elle, le second modérateur écrasait la décision du premier en silence —
# le seul point du chantier « agent global » capable de corrompre des données
# sans qu'aucun écran ni aucun journal ne le montre.
#
# Le détail, les quatre sondes et l'auto-test sont dans `lib/moderation_course.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh
#   # … coller le bloc export imprimé …
#   ./scripts/test-moderation-course.sh
#
# ⚠️ Ce banc ÉCRIT : il crée sa propre promo, la signale trois fois et la
# modère. Il ne touche jamais à celle du décor — la masquer la retirerait des
# bancs qui la lisent.
#
# ⚠️ Il consomme 3 signalements sur le seau strict (5/min/IP) : ne pas
# l'enchaîner avec `test-abus-signalement.sh`, qui vide ce seau exprès.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
  echo "❌ python3 ou python requis — l'absence de verdict n'est pas un verdict."
  exit 2; }
PY=$(command -v python3 || command -v python)

# ⚠️ La console Windows est en cp1252 : sans ça, le moindre « ═ » fait planter
# le banc en UnicodeEncodeError, et un banc qui ne peut pas AFFICHER son verdict
# n'en rend aucun.
export PYTHONIOENCODING=utf-8

cd "$RACINE" || exit 2

echo "── auto-test du banc ──"
SORTIE_AUTOTEST="$("$PY" "$HERE/lib/moderation_course.py" --self-test)" || {
  echo "$SORTIE_AUTOTEST"
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}
echo "$SORTIE_AUTOTEST"

# ⚠️ Un code de sortie 0 ne vaut rien ici : un fichier Python vide sort en 0
# (défaut réel du 2026-08-12).
echo "$SORTIE_AUTOTEST" | grep -q "^auto-test : [0-9]\+ cas, dont [0-9]\+ refus$" || {
  echo "❌ l'auto-test n'a annoncé aucun cas — le module est vide, tronqué ou"
  echo "   n'exécute plus son auto-test."
  exit 2; }

echo
exec "$PY" "$HERE/lib/moderation_course.py" "$@"
