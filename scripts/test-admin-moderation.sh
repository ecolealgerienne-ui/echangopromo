#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/admin_moderation.py`. Trois décisions d'admin dont l'effet réel
# se produit AILLEURS — dans la liste que voit le client. Le défaut fondateur
# date du 2026-08-05 : avertir une promo MASQUÉE la laissait masquée, et
# l'admin croyait avoir levé la sanction.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-admin-moderation.sh
#
# ⚠️ Ce banc ÉCRIT : il crée SA PROPRE promo et la modère. Masquer celle du
# décor la retirerait des bancs qui en ont besoin.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."; exit 2; }
cd "$RACINE" || exit 2
echo "── auto-test du banc ──"
python3 "$HERE/lib/admin_moderation.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."; exit 2; }
echo
exec python3 "$HERE/lib/admin_moderation.py" "$@"
