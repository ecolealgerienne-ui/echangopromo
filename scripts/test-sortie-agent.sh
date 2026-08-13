#!/usr/bin/env bash
#
# Sortie d'un agent — comment on arrête celui qui peut tout faire.
#
# Depuis le 2026-08-13 l'agent agit sur TOUT le parc, sans aucune limite a
# priori. Ce banc établit ce que chaque geste d'admin fait réellement :
# `revoke-token` invalide les jetons émis mais NE FERME PAS le compte (l'agent
# se reconnecte aussitôt) ; seul `reset-password` verrouille. C'est justement
# l'effet que `admin_agents` n'éprouvait pas — il ne lisait que la trace.
#
# ⚠️ Il crée un agent jetable et ne peut pas le supprimer : aucune route ne
# supprime un agent. La trace est assumée plutôt que cachée.
#
# Le détail, les verdicts et l'auto-test sont dans `lib/sortie_agent.py`.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-sortie-agent.sh
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
SORTIE_AUTOTEST="$("$PY" "$HERE/lib/sortie_agent.py" --self-test)" || {
  echo "$SORTIE_AUTOTEST"
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}
echo "$SORTIE_AUTOTEST"

# ⚠️ Un code de sortie 0 ne vaut rien ici : un fichier Python vide sort en 0.
echo "$SORTIE_AUTOTEST" | grep -q "^auto-test : [0-9]\+ cas, dont [0-9]\+ refus$" || {
  echo "❌ l'auto-test n'a annoncé aucun cas — module vide ou tronqué."
  exit 2; }

echo
exec "$PY" "$HERE/lib/sortie_agent.py" "$@"
