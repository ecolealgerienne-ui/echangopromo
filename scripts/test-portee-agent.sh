#!/usr/bin/env bash
#
# Banc de portée — un agent agit sur TOUT le parc, et pas au-delà.
#
# Remplace `test-appartenance.sh`, dont le sujet a disparu le 2026-08-13 :
# quatorze gardes d'appartenance ont été retirées, l'agent est global. L'ancien
# banc prouvait que ces routes REFUSAIENT ; celui-ci prouve qu'elles ACCEPTENT,
# et que les trois routes restées réservées à l'admin refusent toujours.
#
# Le détail, l'ordre des sondes et l'auto-test sont dans `lib/portee_agent.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh     # pose l'agent
#   # … coller le bloc export imprimé …
#   ./scripts/test-portee-agent.sh
#
# ⚠️ Ce banc ÉCRIT et SUPPRIME. Il crée son propre commerçant par
# auto-inscription et le supprime à la fin — il ne touche jamais à celui du
# décor. Ne pas le lancer contre une base qui n'est pas de test.
#
# ⚠️ Il dure environ deux minutes, et c'est voulu : une vingtaine d'écritures
# sur `SENSITIVE_ACTION_THROTTLE` (20/min/IP, seau PARTAGÉ). Baisser
# `PACE_SECONDS` le fait échouer sur son propre plafond, pas sur le produit.
#
# ⚠️ Il consomme UNE inscription sur le seau strict (5/min/IP) : ne pas
# l'enchaîner immédiatement après un banc qui inscrit aussi.

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
SORTIE_AUTOTEST="$("$PY" "$HERE/lib/portee_agent.py" --self-test)" || {
  echo "$SORTIE_AUTOTEST"
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}
echo "$SORTIE_AUTOTEST"

# ⚠️ Un code de sortie 0 ne vaut rien ici : un fichier Python vide sort en 0.
# Défaut réel du 2026-08-12, où `frontiere_http.py` a passé 24 h à 0 octet en
# rendant « succès » à chaque passage.
echo "$SORTIE_AUTOTEST" | grep -q "^auto-test : [0-9]\+ cas, dont [0-9]\+ refus$" || {
  echo "❌ l'auto-test n'a annoncé aucun cas — le module est vide, tronqué ou"
  echo "   n'exécute plus son auto-test."
  exit 2; }

echo
exec "$PY" "$HERE/lib/portee_agent.py" "$@"
