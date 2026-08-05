#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/admin_agents.py`. Assignation et transfert de communes
# ÉLARGISSENT le périmètre IDOR consommé par `assertCommuneMatches` : ce sont
# les deux gestes les plus lourds de conséquence de l'interface admin, et les
# deux que l'AuditLogModule devait tracer sans jamais le faire (règle 11).
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-admin-agents.sh
#
# ⚠️ Ce banc MODIFIE les territoires des deux agents du décor, puis les
# rétablit. S'il s'interrompt au milieu, relancer provision-decor.sh remet tout
# d'aplomb — c'est désormais son rôle (`assurer_communes`).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."; exit 2; }
cd "$RACINE" || exit 2
echo "── auto-test du banc ──"
python3 "$HERE/lib/admin_agents.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."; exit 2; }
echo
exec python3 "$HERE/lib/admin_agents.py" "$@"
