#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/commercant_b.py`. La promo d'un autre.
#
# `PROMO_NOT_OWNED_BY_COMMERCANT` n'était provoqué par AUCUN banc jusqu'au
# 2026-08-13 : le code n'apparaissait qu'en tant que code *accepté*, jamais
# déclenché, et aucun second commerçant n'existait dans les décors. Le chantier
# « agent global » fait de cette branche la garde d'appartenance principale de
# tout `PromoController` — elle ne pouvait pas rester non éprouvée.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-commercant-b.sh
#
# ⚠️ Ce banc ÉCRIT : il crée SON PROPRE commerçant B via l'agent, lui publie
# une promo, et le supprime en fin de course (y compris si une sonde échoue).
# Les trois sondes hostiles doivent toutes être REFUSÉES, donc rester sans
# effet sur le commerçant A du décor.
#
# ⚠️ Exige AGENT_EMAIL, AGENT_PASSWORD et PROMO_ID — ce dernier est la promo du
# commerçant A, la cible des sondes. Aucune valeur par défaut : un banc qui
# inventerait une promo échouerait en accusant la garde.
#
# ⚠️ Il consomme 2 requêtes sur le seau strict (agent + commerçant B) et ~8 sur
# celui des écritures (20/min/IP, partagé). Attendre une minute après un autre
# banc — un 429 se déguise en refus métier.
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

# ⚠️ L'auto-test d'abord, et il est BLOQUANT. Il porte autant de cas qui
# doivent échouer que de cas qui passent — dont le plus important : « refusé,
# mais par une AUTRE garde ». Un banc qui n'asserterait que le statut resterait
# vert le jour où l'appartenance disparaît, pourvu qu'une autre garde tombe à
# sa place.
echo "── auto-test des verdicts ──"
SORTIE="$("$PY" scripts/lib/commercant_b.py --self-test)" || {
  echo "$SORTIE"
  echo "❌ les verdicts ne savent pas refuser — rien n'est mesurable."
  exit 2; }
echo "$SORTIE"

# ⚠️ Le code de sortie ne suffit pas : un fichier Python vide sort en 0. Le
# module de frontière l'a appris à ses dépens le 2026-08-12 (vidé par accident,
# banc vert pendant 24 h). On exige que l'auto-test ait annoncé ses cas.
echo "$SORTIE" | grep -q "^auto-test : [0-9]\+ cas, dont [0-9]\+ refus$" || {
  echo "❌ l'auto-test n'a annoncé aucun cas — module vide, tronqué, ou qui"
  echo "   n'exécute plus son auto-test."
  exit 2; }

echo
exec "$PY" scripts/lib/commercant_b.py "$@"
