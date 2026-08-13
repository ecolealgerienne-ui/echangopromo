#!/usr/bin/env bash
#
# Banc des absences — ce qui a été retiré le 2026-08-13 l'est vraiment.
#
# Trois routes, deux tables et une colonne ont disparu avec le découpage
# administratif, et rien ne le constatait : `frontiere_http.py` DÉRIVE ses
# routes de la source, donc une route supprimée en sort simplement sans manquer
# à personne. Côté base, la migration `DropCommune` a tourné une fois, sans
# contrôle rejouable.
#
# Le détail, les témoins et l'auto-test sont dans `lib/absences_commune.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/test-absences-commune.sh
#
# ⚠️ **Aucun décor requis, aucun identifiant, aucune écriture.** Le banc sonde
# sans jeton : la polarité route-par-route de ce produit fait qu'une route
# supprimée rend 404 et une route existante 401. Il ne consomme aucun seau de
# connexion et peut se lancer à tout moment, y compris entre deux autres bancs.
#
# ⚠️ La moitié « base » passe par `docker exec` sur le conteneur Postgres
# (`psql` n'est pas installé sur l'hôte). Réglable par `PG_CONTAINER`, `PG_USER`
# et `PG_DB` si l'environnement diffère — et si la base est injoignable, le banc
# le DIT au lieu de conclure à l'absence.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."
  exit 2
}

cd "$RACINE" || exit 2

echo "── auto-test du banc ──"
SORTIE_AUTOTEST="$(python3 "$HERE/lib/absences_commune.py" --self-test)" || {
  echo "$SORTIE_AUTOTEST"
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}
echo "$SORTIE_AUTOTEST"

# ⚠️ Un code de sortie 0 ne vaut rien ici : un fichier Python vide sort en 0
# (défaut réel du 2026-08-12). Et c'est d'autant plus vrai pour un banc
# d'ABSENCE, dont le vert est déjà l'état par défaut de tout ce qui ne marche
# pas.
echo "$SORTIE_AUTOTEST" | grep -q "^auto-test : [0-9]\+ cas, dont [0-9]\+ refus$" || {
  echo "❌ l'auto-test n'a annoncé aucun cas — le module est vide, tronqué ou"
  echo "   n'exécute plus son auto-test."
  exit 2; }

echo
exec python3 "$HERE/lib/absences_commune.py" "$@"
