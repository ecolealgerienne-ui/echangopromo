#!/usr/bin/env bash
#
# Banc de l'auto-suppression — `DELETE /commercant/me`, action irréversible.
#
# Seule route par laquelle un commerçant efface son propre compte, et aucun
# test à ce jour. Elle fait trois choses d'un coup — marquer le compte
# supprimé, révoquer la session, effacer les promos — et chacune peut manquer
# sans que rien ne le dise.
#
# Le détail et l'auto-test sont dans `lib/autosuppression.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh     # pose admin, agent
#   # … coller le bloc export imprimé, attendre une minute …
#   ./scripts/test-commercant-autosuppression.sh
#
# ⚠️ Ce banc ÉCRIT, et de façon IRRÉVERSIBLE — mais jamais sur le décor : il
# crée ses propres commerçants (numéros horodatés, par l'agent) et n'en
# supprime qu'un. Le commerçant du décor n'est jamais touché, précisément
# parce qu'aucune sonde ne justifie de détruire ce dont les autres bancs ont
# besoin.
#
# ⚠️ Il laisse derrière lui deux comptes de test et un repreneur. C'est le prix
# d'une sonde sur une action sans retour ; ne pas le lancer contre une base
# qui n'est pas de test.

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
"$PY" "$HERE/lib/autosuppression.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}

echo
exec "$PY" "$HERE/lib/autosuppression.py" "$@"
