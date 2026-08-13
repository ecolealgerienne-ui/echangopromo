#!/usr/bin/env bash
#
# Banc du point par défaut — ce que voit un client qui vient d'installer l'app.
#
# `.env.example` avertit depuis des semaines : « le pilote est à Djelfa, le
# défaut ci-dessous est Alger… sinon un rayon de 5 km autour d'Alger rend la
# liste VIDE pour tout client qui n'a pas enregistré son point ». C'est un
# commentaire, et un commentaire ne peut pas échouer (règle 30). Ce banc en
# fait un contrôle.
#
# Le détail et l'auto-test sont dans `lib/defaut_client.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ATTENDU_LAT=34.6703 ATTENDU_LNG=3.2630 ./scripts/test-defaut-client.sh
#
# ⚠️ `ATTENDU_LAT`/`ATTENDU_LNG` sont **facultatifs mais recommandés** : sans
# eux, le banc constate le point servi sans pouvoir le refuser, et le dit.
#
# ⚠️ Aucun décor, aucun identifiant, aucune écriture — il lit deux routes
# publiques. Il peut se lancer à tout moment, y compris contre la production.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
  echo "❌ python3 ou python requis — l'absence de verdict n'est pas un verdict."
  exit 2; }
PY=$(command -v python3 || command -v python)

cd "$RACINE" || exit 2

echo "── auto-test du banc ──"
SORTIE_AUTOTEST="$("$PY" "$HERE/lib/defaut_client.py" --self-test)" || {
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
exec "$PY" "$HERE/lib/defaut_client.py" "$@"
