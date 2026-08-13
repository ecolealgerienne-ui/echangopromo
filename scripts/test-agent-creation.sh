#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/agent_creation.py`. ⚠️ **Son sujet a changé le
# 2026-08-13** : il éprouvait la règle 1 sur une `communeId` fournie par
# l'appelant — la forme même d'un IDOR. Le territoire de l'agent ayant disparu,
# il éprouve désormais le seul invariant qui reste sur cette route : **la
# position est obligatoire**, la garde qui empêche une tournée de fabriquer des
# fiches invisibles (40 des 44 mesurées le 2026-08-12 venaient d'ici).
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-agent-creation.sh
#
# ⚠️ Ce banc ÉCRIT : il crée un commerçant (numéro horodaté) et tente d'en
# créer un second sans position, qui doit être refusé. Rien n'est supprimé.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."; exit 2; }
cd "$RACINE" || exit 2
echo "── auto-test du banc ──"
python3 "$HERE/lib/agent_creation.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."; exit 2; }
echo
exec python3 "$HERE/lib/agent_creation.py" "$@"
