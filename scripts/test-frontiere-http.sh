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

command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — le banc ne peut pas s'exécuter, et l'absence de"
  echo "   verdict n'est pas un verdict."
  exit 2
}

cd "$RACINE" || exit 2

# ⚠️ L'auto-test d'abord, et son échec est bloquant. Un banc dont on n'a pas
# vérifié qu'il sait dire non ne prouve rien de ce qu'il déclare ensuite.
echo "── auto-test du banc ──"
python3 "$HERE/lib/frontiere_http.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause, pas les routes."
  exit 2
}

echo
exec python3 "$HERE/lib/frontiere_http.py" "$@"
