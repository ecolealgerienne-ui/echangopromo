#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/client_rayon.py`. Le cadre n'est pas le cercle.
#
# La recherche par rayon se fait en deux temps côté serveur : un cadre
# rectangulaire (qui seul emprunte l'index) puis une distance haversine qui en
# rogne les coins. Une implémentation qui oublie le rognage rend vert sur
# presque tous les jeux d'essai — le seul cas qui la démasque est un point
# DANS le carré et HORS du cercle, en diagonale.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-client-rayon.sh
#
# ⚠️ Ce banc ÉCRIT : il crée SES PROPRES commerçants via l'agent, à des
# positions calculées, et leur publie une promo. Il ne touche à aucun compte
# existant.
#
# ⚠️ Exige AGENT_EMAIL et AGENT_PASSWORD : seul l'agent peut créer un
# commerçant à des coordonnées choisies — et depuis le 2026-08-12 cette route
# les EXIGE, ce qui garantit qu'un décor bancal est refusé franchement au lieu
# de produire des commerces invisibles.
#
# ⚠️ Il consomme 3 requêtes sur le seau strict (agent + 2 nettoyages) et ~7 sur celui
# des écritures (20/min/IP, partagé). Attendre une minute après un autre banc —
# un 429 se déguise en refus métier.
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

# ⚠️ L'auto-test d'abord, et il est BLOQUANT. Il ne vérifie pas que les
# verdicts savent refuser : il vérifie AUSSI que la géométrie du décor place
# bien son point dans le cadre et hors du cercle. Un décor qui vise à côté
# rendrait vert un serveur cassé, sans que rien ne le dise.
echo "── auto-test des verdicts et de la géométrie ──"
"$PY" scripts/lib/client_rayon.py --self-test || {
  echo "❌ verdicts ou géométrie en défaut — rien n'est mesurable."
  exit 2; }

echo
"$PY" scripts/lib/client_rayon.py
