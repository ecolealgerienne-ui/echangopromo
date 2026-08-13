#!/usr/bin/env bash
#
# Plafond réglé par l'admin — le réglage change-t-il quelque chose ?
#
# `PATCH /admin/commercant/:id/plafond-promos` est la seule route admin-SEULEMENT
# sur un commerçant. Un banc la touche — `portee_agent` — et il prouve une seule
# chose : que l'AGENT en est refusé. Personne n'éprouvait qu'elle FASSE quelque
# chose. C'est le miroir de la règle 28 : on y exige qu'un contrôle sache
# refuser, ici on exige qu'un réglage sache agir.
#
# Éprouvé dans les DEUX sens, et il en faut deux : serré au nombre d'actives, la
# publication doit être refusée ; desserré d'un cran, la même doit passer. Le
# refus seul serait satisfait par un serveur qui refuse toujours.
#
# ⚠️ Ce banc ÉCRIT : il change le plafond du commerçant du décor, publie une
# promo, puis restaure le plafond de départ et arrête la promo. Un banc qui
# laisserait le décor bridé casserait tous les suivants, en silence.
#
# Le détail, les verdicts et l'auto-test sont dans `lib/plafond_admin.py`.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-plafond-admin.sh
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
SORTIE_AUTOTEST="$("$PY" "$HERE/lib/plafond_admin.py" --self-test)" || {
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
exec "$PY" "$HERE/lib/plafond_admin.py" "$@"
