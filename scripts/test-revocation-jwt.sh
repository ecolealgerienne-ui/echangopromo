#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/revocation_jwt.py`. JWT_EXPIRES_IN vaut 30 JOURS : sans
# révocation, un jeton volé reste exploitable un mois sans recours (règle 6).
# Mécanisme ajouté à l'audit V1 et JAMAIS REJOUÉ depuis.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-revocation-jwt.sh
#
# ⚠️ Ce banc RÉVOQUE les jetons admin et agent du décor — c'est son objet. Les
# comptes restent valides, il suffit de se reconnecter. Il consomme 3 connexions
# sur le seau d'authentification (50/min) — ce n'est plus lui qui impose de le
# lancer isolé, c'est la révocation.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."; exit 2; }
cd "$RACINE" || exit 2
echo "── auto-test du banc ──"
python3 "$HERE/lib/revocation_jwt.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."; exit 2; }
echo
exec python3 "$HERE/lib/revocation_jwt.py" "$@"
