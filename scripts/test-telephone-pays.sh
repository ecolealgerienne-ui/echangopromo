#!/usr/bin/env bash
#
# Banc du téléphone et de son pays — une écriture, un compte.
#
# Éprouve les trois propriétés que la normalisation en E.164 a introduites le
# 2026-08-15 : deux écritures du même numéro ne font qu'un compte, un
# commerçant non algérien existe réellement, et le pays déclaré fait autorité
# dans les TROIS formulaires (inscription, connexion, création par un agent).
#
# Le détail et l'auto-test sont dans `lib/telephone_pays.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh    # puis coller le bloc export imprimé
#   ./scripts/test-telephone-pays.sh
#
# ⚠️ Ce banc CRÉE de vrais comptes et les supprime en fin de course. Il
# travaille sur des numéros qui lui sont propres (07701122…), jamais sur ceux
# du décor. La suppression libérant le numéro, il est rejouable tel quel.
#
# ⚠️ Il consomme le seau d'inscription (5/min/IP) et s'espace donc de 15 s
# entre deux inscriptions — comptez environ deux minutes. Réduire
# `PACE_REGISTER` fait apparaître des 429, que le banc classe « non concluant »
# plutôt que de les prendre pour des refus métier.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
  echo "❌ python3 ou python requis — l'absence de verdict n'est pas un verdict."
  exit 2
}
PY=$(command -v python3 || command -v python)

# ⚠️ La console Windows est en cp1252 : sans ça, le moindre « ═ » fait planter
# le banc en UnicodeEncodeError, et un banc qui ne peut pas AFFICHER son
# verdict n'en rend aucun.
export PYTHONIOENCODING=utf-8

cd "$RACINE" || exit 2

echo "── auto-test du banc ──"
"$PY" "$HERE/lib/telephone_pays.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}

echo
exec "$PY" "$HERE/lib/telephone_pays.py" "$@"
