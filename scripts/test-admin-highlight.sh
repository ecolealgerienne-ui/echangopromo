#!/usr/bin/env bash
#
# Banc du bandeau « Top promos » — curation admin et projection client.
#
# Le module a été livré fin juillet 2026 et jamais éprouvé de bout en bout. Ce
# banc ne le « couvre » pas : il sonde les trois règles qui y ont déjà produit
# un défaut réel — la fuite d'un identifiant interne dans la projection
# publique, la diapositive dont la promo est morte, et le réordonnancement
# partiel.
#
# Le détail, les corps de requête et l'auto-test sont dans
# `lib/admin_highlight.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh     # pose admin, agent, commerçant
#   # … coller le bloc export imprimé, attendre une minute …
#   ./scripts/test-admin-highlight.sh
#
# ⚠️ Ce banc ÉCRIT : il crée une promo (par l'agent, exempté du plafond
# quotidien), la met en avant, l'arrête, puis supprime sa diapositive. La
# promo reste arrêtée à la fin — elle appartient au banc, pas au décor. Ne pas
# le lancer contre une base qui n'est pas de test.

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
"$PY" "$HERE/lib/admin_highlight.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}

echo
exec "$PY" "$HERE/lib/admin_highlight.py" "$@"
