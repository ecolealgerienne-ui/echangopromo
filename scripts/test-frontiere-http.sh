#!/usr/bin/env bash
#
# Banc de refus de la frontière HTTP — echango Promo (étape 1).
#
# Chaque route protégée est appelée sans jeton, avec le jeton d'un rôle qui n'y
# a pas droit, et avec un jeton révoqué. Les trois doivent être refusées, avec
# le bon statut ET le bon code — un refus sans code est un refus que
# l'application ne sait pas traduire.
#
# Le détail, les motifs et l'auto-test sont dans `lib/frontiere_http.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/test-frontiere-http.sh
#
#   PACE_SECONDS=1.5 ./scripts/test-frontiere-http.sh   # si le débit plafonne
#   python3 scripts/lib/frontiere_http.py --list        # les routes vues
#
# ── Identifiants ────────────────────────────────────────────────────────────
#
# Aucune valeur par défaut, délibérément : un banc qui se rabattrait sur un
# compte imaginaire échouerait à la connexion en accusant la frontière.
#
#   export API_URL=http://localhost:3000
#   export ADMIN_EMAIL=...       ADMIN_PASSWORD=...
#   export AGENT_EMAIL=...       AGENT_PASSWORD=...
#   export COMMERCANT_TEL=...    COMMERCANT_PIN=...
#
# ⚠️ Le banc RÉVOQUE le jeton admin au démarrage (c'est ce qui lui donne son
# troisième échantillon). Une session admin ouverte ailleurs sera déconnectée —
# c'est sans gravité, il suffit de se reconnecter.
#
# ⚠️ Cadence : le plafond global est de 60 req/min/IP. ~140 sondes à 1,1 s font
# environ 3 minutes. Descendre PACE_SECONDS fait apparaître des 429, que le banc
# nomme au lieu de les compter comme des échecs métier.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
  echo "❌ python3 ou python requis — l'absence de verdict n'est pas un verdict."
  exit 2
}
PY=$(command -v python3 || command -v python)

# ⚠️ La console Windows est en cp1252 : sans ça, le moindre « ═ » fait planter
# le banc en UnicodeEncodeError, et un banc qui ne peut pas AFFICHER son
# verdict n'en rend aucun.
export PYTHONIOENCODING=utf-8

cd "$RACINE" || exit 2

# ⚠️ L'auto-test d'abord, et son échec est bloquant. Un banc dont on n'a pas
# vérifié qu'il sait dire non ne prouve rien de ce qu'il déclare ensuite.
echo "── auto-test du banc ──"
SORTIE_AUTOTEST="$("$PY" "$HERE/lib/frontiere_http.py" --self-test)" || {
  echo "$SORTIE_AUTOTEST"
  echo "❌ l'auto-test échoue : le banc lui-même est en cause, pas les routes."
  exit 2
}
echo "$SORTIE_AUTOTEST"

# ⚠️ **Le code de sortie ne suffit pas, et ça s'est payé.** Le 2026-08-12, le
# module a été VIDÉ par accident (489 lignes, commit 72d43d3 qui n'annonçait
# qu'un décompte). Or `python3 fichier_vide.py --self-test` sort en **0** : le
# `||` ci-dessus n'a rien vu, le `exec` suivant non plus, et le banc a rendu 0
# en n'affichant que son propre titre. Pendant 24 h, plus rien dans ce dépôt ne
# pouvait voir une route ouverte non épinglée — le contrôle censé tenir la
# règle 33 était devenu un `exit 0` déguisé.
#
# On exige donc que l'auto-test ait **mesuré quelque chose**, pas qu'il se soit
# tu. C'est la règle 28 appliquée au banc lui-même : un contrôle qui ne peut
# pas produire sa propre mesure n'a pas prouvé qu'il sait refuser.
echo "$SORTIE_AUTOTEST" | grep -q "^auto-test : [0-9]\+ cas, dont [0-9]\+ refus$" || {
  echo "❌ l'auto-test n'a annoncé aucun cas — le module est vide, tronqué ou"
  echo "   n'exécute plus son auto-test. Un code de sortie 0 ne vaut rien ici :"
  echo "   un fichier Python vide sort en 0 (défaut réel du 2026-08-12)."
  exit 2
}

echo
exec "$PY" "$HERE/lib/frontiere_http.py" "$@"
