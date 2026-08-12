#!/usr/bin/env bash
#
# Banc du tableau de bord — cohérence des compteurs, portée globale de l'agent.
#
# ⚠️ **Retourné le 2026-08-13.** Il prouvait le cloisonnement de l'agent ; le
# chantier « agent global » le supprime, et les sections 2 et 3 sont devenues
# des assertions incapables de refuser. La section 4 prouve désormais
# l'inverse : deux agents distincts voient exactement la même chose, égale à ce
# que voit l'admin. Un filtre de périmètre oublié quelque part les ferait
# diverger — c'est le seul contrôle du parc qui le verrait.
#
# Le tableau de bord est le seul endroit du produit où l'on regarde des NOMBRES
# plutôt que des objets. C'est ce qui le rend dangereux : un chiffre faux a
# toujours l'air juste, et rien dans l'interface ne permet de le contredire.
# Deux défauts réels y sont déjà nés — le surcompte des promos actives (cas
# fondateur de la règle 8) et `countPendingModeration` qui rendait 6 pour 2.
#
# Il éprouve aussi une surface que `test-appartenance` ne couvre pas : celui-ci
# regarde les ACTIONS d'un agent hors de ses communes, celui-là ses
# PROJECTIONS. Un agent qui ne peut rien faire ailleurs mais qui voit tout
# n'est pas cloisonné.
#
# Le détail et l'auto-test sont dans `lib/admin_dashboard.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh     # pose admin, agent, commerçant
#   # … coller le bloc export imprimé, attendre une minute …
#   ./scripts/test-admin-dashboard.sh
#
# ⚠️ Ce banc ne fait que LIRE. Il est le seul du lot dans ce cas — il peut donc
# se relancer sans précaution, et ne perturbe aucun autre.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."
  exit 2
}

cd "$RACINE" || exit 2

echo "── auto-test du banc ──"
python3 "$HERE/lib/admin_dashboard.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}

echo
exec python3 "$HERE/lib/admin_dashboard.py" "$@"
