#!/usr/bin/env bash
#
# Banc du filtre par catégorie — la somme des parts fait-elle le tout ?
#
# Écrit sur une observation du 2026-08-13, à Djelfa : l'app annonçait 22 promos
# en « Alimentation », 4 en « Autre », et 24 en « Toutes ». 22 + 4 = 26. Les
# trois nombres sont plausibles pris un par un, et rien ne signale l'écart —
# on ne le voit qu'en additionnant, et personne n'additionne.
#
# ⚠️ Ce banc interroge le SERVEUR, pas les écrans. C'est ce qui permet de savoir
# où chercher : vert, l'écart vient de l'app (la carte se borne au cadre
# visible, la liste au rayon) ; rouge, il vient de la requête SQL et aucune
# retouche d'affichage ne le réparera.
#
# Le détail, les verdicts et l'auto-test sont dans `lib/filtre_categorie.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/test-filtre-categorie.sh
#
# ⚠️ Aucun décor, aucun identifiant, aucune écriture — il lit une route
# publique. Il peut se lancer à tout moment, y compris contre la production.
#
# ⚠️ Il ne peut rien affirmer sur un décor mono-catégorie : un filtre inopérant
# y rendrait exactement les mêmes chiffres. Le banc le dit (« non concluant »)
# plutôt que de passer au vert.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
  echo "❌ python3 ou python requis — l'absence de verdict n'est pas un verdict."
  exit 2; }
PY=$(command -v python3 || command -v python)

# ⚠️ Sur Windows, la console est en cp1252 et le moindre « ═ » fait planter le
# banc en UnicodeEncodeError — un banc qui ne peut pas AFFICHER son verdict n'en
# rend aucun. Les autres bancs tournent depuis WSL et n'ont jamais rencontré le
# cas ; celui-ci se lance des deux côtés.
export PYTHONIOENCODING=utf-8

cd "$RACINE" || exit 2

echo "── auto-test du banc ──"
SORTIE_AUTOTEST="$("$PY" "$HERE/lib/filtre_categorie.py" --self-test)" || {
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
exec "$PY" "$HERE/lib/filtre_categorie.py" "$@"
