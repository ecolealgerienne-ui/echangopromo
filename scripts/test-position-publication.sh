#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/position_publication.py`. Publier exige une position ;
# préparer un brouillon, non.
#
# Un seul commerçant, une seule variable : il naît sans position, on lui refuse
# de publier, on lui pose sa position, il publie. Si la seconde tentative
# réussit, c'est la position qui manquait — et rien d'autre.
#
#   ./scripts/provision-decor.sh   # … pour le référentiel commune …
#   ./scripts/test-position-publication.sh
#
# ⚠️ Ce banc ÉCRIT : il crée SON PROPRE commerçant par auto-inscription — le
# seul chemin qui autorise encore un compte sans position, la création par agent
# l'exigeant depuis le 2026-08-12. Il ne touche à aucun compte existant.
#
# ⚠️ Il consomme 2 requêtes sur le seau strict (5/min/IP).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."; exit 2; }
cd "$RACINE" || exit 2

# ⚠️ L'auto-test d'abord, et il est BLOQUANT : un banc dont les verdicts ne
# savent pas refuser ne peut rien affirmer sur le produit (règle #28).
echo "── auto-test des verdicts ──"
python3 scripts/lib/position_publication.py --self-test || {
  echo "❌ les verdicts de ce banc ne savent pas refuser — rien n'est mesurable."
  exit 2; }

echo
python3 scripts/lib/position_publication.py
