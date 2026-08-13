#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/abus_signalement.py`. La règle 7 dans son énoncé exact : un
# endpoint public protégé par un identifiant DÉCLARATIF doit être borné par IP.
# Le défaut d'origine : trois requêtes changeant juste `X-Device-Id`
# suffisaient à masquer la promo d'un concurrent.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-abus-signalement.sh
#
# ⚠️ Ce banc ÉPUISE le seau strict (5/min) et MASQUE une promo — la sienne. Il
# doit tourner SEUL, et il faut attendre une minute après son passage.
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
"$PY" "$HERE/lib/abus_signalement.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."; exit 2; }
echo
exec "$PY" "$HERE/lib/abus_signalement.py" "$@"
