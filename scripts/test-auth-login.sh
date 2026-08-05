#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/auth_login.py`. Sans verrou, un PIN à 6 chiffres est
# brute-forçable en ligne (règle 2) — `@nestjs/throttler` n'était même pas
# installé avant l'audit V0.
#
#   ./scripts/test-auth-login.sh
#
# ⚠️ Ce banc DÉCLENCHE le verrou volontairement. Il doit tourner SEUL : pendant
# une minute après son passage, toute connexion depuis la même IP est refusée —
# y compris celles des autres bancs, qui accuseraient alors leurs propres
# identifiants (« un 429 se déguise en identifiants incorrects »).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."; exit 2; }
cd "$RACINE" || exit 2
echo "── auto-test du banc ──"
python3 "$HERE/lib/auth_login.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."; exit 2; }
echo
exec python3 "$HERE/lib/auth_login.py" "$@"
