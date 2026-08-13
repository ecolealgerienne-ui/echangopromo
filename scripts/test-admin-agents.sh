#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/admin_agents.py`. ⚠️ **Son sujet a changé le
# 2026-08-13** : il éprouvait l'assignation et le transfert de communes, deux
# routes supprimées avec le territoire de l'agent.
#
# Ce qui survit est ce qui comptait le plus — `verdict_trace`, le seul contrôle
# du parc qui éprouve qu'une action d'administration LAISSE UNE TRACE. Il porte
# le cas fondateur de la règle 11 : un AuditLogModule présent depuis le premier
# commit et qui n'a jamais rien tracé pendant des semaines.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-admin-agents.sh
#
# ⚠️ Ce banc CRÉE un agent et ne le supprime pas : il n'existe aucune route de
# suppression d'agent. Chaque passage laisse donc un compte de plus — c'est un
# manque du produit, pas seulement une gêne de banc.
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
"$PY" "$HERE/lib/admin_agents.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."; exit 2; }
echo
exec "$PY" "$HERE/lib/admin_agents.py" "$@"
