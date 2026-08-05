#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/agent_promo.py`. `POST /promo/agent/:cid` fait agir un
# compte POUR LE COMPTE D'UN AUTRE : la promo appartient au commerçant, mais la
# clé S3 peut porter le préfixe de l'AGENT — subtilité documentée qu'un
# resserrement ultérieur casserait sans qu'on s'en aperçoive.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-agent-promo.sh
#
# ⚠️ Ce banc ÉCRIT : il crée jusqu'à deux promos pour le commerçant du décor.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."; exit 2; }
cd "$RACINE" || exit 2
echo "── auto-test du banc ──"
python3 "$HERE/lib/agent_promo.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."; exit 2; }
echo
exec python3 "$HERE/lib/agent_promo.py" "$@"
