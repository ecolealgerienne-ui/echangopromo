#!/usr/bin/env bash
#
# Recherche dans le parc — le geste de l'agent en tournée.
#
# Sept bancs appellent GET /admin/commercant, tous en ?limit=100 sec : le
# paramètre `search` n'était exercé par personne. Ce banc cherche un commerçant
# situé AU-DELÀ de la première page — la seule sonde qui distingue une vraie
# recherche d'un filtre appliqué à une page tronquée (règle 15).
#
# ⚠️ Il éprouve aussi le piège du « + » : non encodé dans une chaîne de
# requête, il se décode en espace. Silencieusement.
#
# ⚠️ Aucune écriture : il peut se relancer sans précaution.
#
# Le détail, les verdicts et l'auto-test sont dans `lib/recherche_parc.py`.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-recherche-parc.sh
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
SORTIE_AUTOTEST="$("$PY" "$HERE/lib/recherche_parc.py" --self-test)" || {
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
exec "$PY" "$HERE/lib/recherche_parc.py" "$@"
