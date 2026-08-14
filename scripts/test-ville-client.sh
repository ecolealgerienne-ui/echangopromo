#!/usr/bin/env bash
#
# Banc du point client — le point enregistré sépare-t-il vraiment deux villes ?
#
# Les parcours d'écran éprouvent les GESTES du client (le bandeau, le
# consentement, le recentrage). Ils ne peuvent pas prouver que le SERVEUR sépare
# les villes : sur un décor tenant dans un seul rayon, ils resteraient verts
# avec un serveur qui ignore complètement le point.
#
# Ce banc mesure exactement ça, sur les trois villes du décor (Djelfa, Hassi
# Bahbah, Alger) : chaque paire doit être mutuellement invisible, la requête
# sans coordonnées doit suivre le point configuré, et chaque promo servie doit
# porter la position de son commerce — sans quoi la carte est plus pauvre que
# la liste, en silence.
#
# Le détail, les verdicts et l'auto-test sont dans `lib/ville_client.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/test-ville-client.sh
#
# ⚠️ Aucun décor à provisionner, aucune écriture, aucun identifiant — il lit une
# route publique. Il suppose seulement que le décor à trois villes est en base.
#
# ⚠️ Sur un décor mono-ville il rend « non concluant », jamais vert : la
# disjonction serait vraie par vacuité.
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
SORTIE_AUTOTEST="$("$PY" "$HERE/lib/ville_client.py" --self-test)" || {
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
exec "$PY" "$HERE/lib/ville_client.py" "$@"
