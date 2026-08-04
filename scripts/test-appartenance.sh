#!/usr/bin/env bash
#
# Banc d'appartenance — un agent n'agit que dans ses communes.
#
# Le jeton est valide, le rôle est le bon : la question n'est plus « qui
# êtes-vous » mais « cette ressource est-elle à vous ». C'est la seconde moitié
# du contrôle d'accès, et celle qui a produit la faille critique de l'audit V0.
#
# Le détail, les corps de requête et l'auto-test sont dans `lib/appartenance.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh     # pose agent A, agent B, commerçant, promo
#   # … coller le bloc export imprimé, attendre une minute …
#   ./scripts/test-appartenance.sh
#
# ⚠️ Ce banc ÉCRIT : il suspend puis réactive le commerçant du décor pour son
# témoin positif. L'état est restauré, mais ne pas le lancer contre une base
# qui n'est pas de test.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."
  exit 2
}

cd "$RACINE" || exit 2

echo "── auto-test du banc ──"
python3 "$HERE/lib/appartenance.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}

echo
exec python3 "$HERE/lib/appartenance.py" "$@"
