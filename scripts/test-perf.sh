#!/usr/bin/env bash
#
# Performance — des chiffres, avant toute optimisation.
#
# Le dépôt porte 46 bancs de correction et AUCUNE mesure de performance. Une
# cible de fluidité qu'on ne mesure pas est un commentaire, et un commentaire ne
# peut pas échouer (règle 30).
#
# Quatre grandeurs : le poids sur le fil (brut et gzip), la latence p50/p95, la
# présence d'un cache HTTP, et le nombre de transactions PostgreSQL par appel —
# la seule sonde qui voit venir un N+1 pendant qu'il ne coûte encore rien.
#
# ⚠️ Ce n'est PAS un test de charge : un appel à la fois, sans concurrence. Il
# répond à « cette route est-elle bien formée ? », pas à « que se passe-t-il à
# 500 utilisateurs ? ».
#
# ⚠️ Trois pièges de mesure évités, et dits : un 429 est TRÈS rapide et
# flatterait le p50 (seules les 200 comptent) ; la compression ne s'observe pas
# sans la demander ; le premier appel n'est pas représentatif (chauffe jetée).
#
# ⚠️ La sonde SQL exige un accès à PostgreSQL (psycopg2, psql ou docker exec).
# Depuis le clone Windows elle n'en a aucun et LE DIT ; depuis WSL elle mesure.
#
# ⚠️ Aucune écriture, aucun identifiant — il peut se lancer contre n'importe
# quel environnement, y compris la production.
#
# Le détail, les verdicts et l'auto-test sont dans `lib/banc_perf.py`.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-perf.sh
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
SORTIE_AUTOTEST="$("$PY" "$HERE/lib/banc_perf.py" --self-test)" || {
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
exec "$PY" "$HERE/lib/banc_perf.py" "$@"
