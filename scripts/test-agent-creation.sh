#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/agent_creation.py` : `POST /agent/commercant` prend une
# `communeId` FOURNIE PAR L'APPELANT — la forme même d'un IDOR (règle 1).
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-agent-creation.sh
#
# ⚠️ Ce banc ÉCRIT : il crée un commerçant (numéro horodaté) et tente d'en
# créer un second, qui doit être refusé. Rien n'est supprimé.
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
