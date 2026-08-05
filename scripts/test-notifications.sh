#!/usr/bin/env bash
#
# Banc des notifications — compteur, projection, cloisonnement.
#
# Module entier resté sans aucune couverture jusqu'ici. Ce banc ne le
# « couvre » pas : il sonde quatre règles dont l'échec ne se voit nulle part —
# un compteur faux pose un badge qui a toujours l'air juste, et une
# notification d'autrui qu'on peut marquer lue est un IDOR silencieux.
#
# Le détail, les corps de requête et l'auto-test sont dans
# `lib/notifications.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh     # pose admin, agent, commerçant
#   # … coller le bloc export imprimé, attendre une minute …
#   ./scripts/test-notifications.sh
#
# ⚠️ Ce banc ÉCRIT : il remet à zéro les notifications du commerçant du décor,
# crée une promo (par l'agent, exempté du plafond quotidien) et la modère deux
# fois. Ne pas le lancer contre une base qui n'est pas de test.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."
  exit 2
}

cd "$RACINE" || exit 2

echo "── auto-test du banc ──"
python3 "$HERE/lib/notifications.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}

echo
exec python3 "$HERE/lib/notifications.py" "$@"
