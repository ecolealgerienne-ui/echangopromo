#!/usr/bin/env bash
#
# Banc de la recherche — globale par décision, mais le proche d'abord.
#
# Écrit sur une observation du 2026-08-14, sur téléphone réel : « dans la
# recherche il fait une recherche globale, pas une recherche autour de mon point
# de localisation ». Mesuré : `search=promo` rend 65 résultats de 0,1 km à
# 245 km, dont 38 hors du rayon de 5 km.
#
# ⚠️ Ce n'est PAS un défaut : `promo.service.ts` lève délibérément le rayon sur
# une recherche textuelle (« chercher est un acte intentionnel avec une cible »).
# Mais la décision ne tient que par sa contrepartie, écrite juste en dessous :
# « le tri par distance reste actif, donc le proche remonte quand même en tête ».
# C'est cette phrase que ce banc éprouve, parce qu'un commentaire ne peut pas
# échouer (règle 30).
#
# ⚠️ **Ce banc ne voit pas le défaut qui a été trouvé ce jour-là**, et c'est
# important : il était dans l'app, qui re-triait par date par-dessus l'ordre du
# serveur. Le serveur, lui, a toujours eu raison. Ce banc tient la PRÉMISSE dont
# l'app dépend ; le versant app est tenu par
# `apps/mobile/test/features/client/tri_proximite_test.dart`.
#
# Le détail, les verdicts et l'auto-test sont dans `lib/recherche_globale.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/test-recherche-globale.sh
#   TERME_RECHERCHE=pain ./scripts/test-recherche-globale.sh
#
# ⚠️ Aucun décor, aucun identifiant, aucune écriture — il ne lit que des routes
# publiques. Il peut se lancer à tout moment.
#
# ⚠️ Il ne peut rien affirmer sur un décor tout entier proche ou tout entier
# lointain : un serveur qui applique le rayon et un serveur qui l'ignore y
# rendraient la même chose. Le banc le dit (« non concluant ») plutôt que de
# passer au vert.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
  echo "❌ python3 ou python requis — l'absence de verdict n'est pas un verdict."
  exit 2; }
PY=$(command -v python3 || command -v python)

# ⚠️ Sur Windows, la console est en cp1252 et le moindre « ═ » fait planter le
# banc en UnicodeEncodeError — un banc qui ne peut pas AFFICHER son verdict n'en
# rend aucun.
export PYTHONIOENCODING=utf-8

cd "$RACINE" || exit 2

echo "── auto-test du banc ──"
SORTIE_AUTOTEST="$("$PY" "$HERE/lib/recherche_globale.py" --self-test)" || {
  echo "$SORTIE_AUTOTEST"
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}
echo "$SORTIE_AUTOTEST"

# ⚠️ Un code de sortie 0 ne vaut rien ici : un fichier Python vide sort en 0
# (défaut réel du 2026-08-12).
echo "$SORTIE_AUTOTEST" | grep -q "^auto-test : [0-9]\+ cas, dont [0-9]\+ refus$" || {
  echo "❌ l'auto-test n'a annoncé aucun cas — module vide ou tronqué."
  exit 2; }

echo
exec "$PY" "$HERE/lib/recherche_globale.py" "$@"
