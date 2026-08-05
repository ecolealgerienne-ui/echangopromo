#!/usr/bin/env bash
#
# Banc de cycle de vie — suspension ≠ suppression.
#
# Deux états qu'il serait facile de confondre, et dont la confusion se paie
# cher. Le vrai discriminant est le NUMÉRO DE TÉLÉPHONE : c'est la seule
# différence observable de l'extérieur, et celle qui casse en silence — si la
# suspension libérait le numéro, un tiers pourrait s'inscrire avec celui d'un
# commerçant momentanément suspendu.
#
# Le détail et l'auto-test sont dans `lib/cycle_commercant.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh    # puis coller le bloc export imprimé
#   ./scripts/test-cycle-commercant.sh
#
# ⚠️ Ce banc SUPPRIME réellement un commerçant. Il travaille sur le sien, créé
# au début et jamais réutilisé ailleurs — jamais sur celui du décor. La
# suppression libérant le numéro, il est rejouable tel quel.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."
  exit 2
}

cd "$RACINE" || exit 2

echo "── auto-test du banc ──"
python3 "$HERE/lib/cycle_commercant.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}

echo
exec python3 "$HERE/lib/cycle_commercant.py" "$@"
