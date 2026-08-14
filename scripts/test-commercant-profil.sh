#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/commercant_profil.py`. Le défaut central est celui du 2026-07-12 :
# un PATCH partiel faisait disparaître les champs non visés DE LA RÉPONSE (pas
# de la base), et le parsing mobile plantait alors que rien n'était perdu.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-commercant-profil.sh
#
# ⚠️ Ce banc ÉCRIT : il crée SON PROPRE commerçant (numéro horodaté) et lui
# change son PIN. Il ne touche jamais à celui du décor — le faire le rendrait
# inutilisable pour tous les autres bancs.
#
# ⚠️ Il consomme 3 connexions sur le seau d'authentification (50/min).
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
"$PY" "$HERE/lib/commercant_profil.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."; exit 2; }
echo
exec "$PY" "$HERE/lib/commercant_profil.py" "$@"
