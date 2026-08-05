#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/client_fiche.py` : ce qu'il éprouve, et le défaut réel qui
# l'a fait naître.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export …
#   ./scripts/test-client-fiche.sh
#
# ⚠️ Ce banc ne fait que LIRE : il peut se relancer sans précaution.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."; exit 2; }
cd "$RACINE" || exit 2
echo "── auto-test du banc ──"
python3 "$HERE/lib/client_fiche.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."; exit 2; }
echo
exec python3 "$HERE/lib/client_fiche.py" "$@"
