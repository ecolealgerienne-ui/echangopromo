#!/usr/bin/env bash
#
# Plan SQL — la FORME de la requête géographique, pas sa durée du jour.
#
# `banc_perf` mesure des millisecondes. À 310 promos et 154 commerçants, ce
# chiffre ne dit rien : deux petites tables se parcourent instantanément. Ce banc
# regarde ce qui ne dépend pas de la taille du jour — quels index la requête
# emprunte, et combien de lignes ils écartent avant la lecture de table.
#
# ⚠️ La reconstitution SQL est VALIDÉE contre le `total` servi par l'API pour le
# même point. Si les deux divergent, le banc s'arrête : un plan tiré d'une
# requête approximative est crédible et faux, donc pire qu'aucun plan.
#
# ⚠️ Il n'écrit RIEN : l'index de comparaison est créé dans une transaction
# annulée, et la dernière sonde vérifie qu'il ne reste rien en base.
#
# ⚠️ Exige psycopg2 ET le backend en ligne (la validation compare à l'API).
#
# Le détail, les verdicts et l'auto-test sont dans `lib/plan_sql.py`.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-plan-sql.sh
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
SORTIE_AUTOTEST="$("$PY" "$HERE/lib/plan_sql.py" --self-test)" || {
  echo "$SORTIE_AUTOTEST"
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}
echo "$SORTIE_AUTOTEST"

# ⚠️ Un code de sortie 0 ne vaut rien ici : un fichier Python vide sort en 0.
echo "$SORTIE_AUTOTEST" | grep -q "^auto-test : [0-9]\+ cas, dont [0-9]\+ refus$" || {
  echo "❌ l'auto-test n'a annoncé aucun cas — module vide ou tronqué."
  exit 2; }

echo
exec "$PY" "$HERE/lib/plan_sql.py" "$@"
