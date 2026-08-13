#!/usr/bin/env bash
#
# Fluidité de la carte — profilage des temps d'image sur l'appareil.
#
# `banc_perf` mesure le serveur : 12 à 17 ms en p95, rien à optimiser de ce
# côté. Ce que le client ressent comme « ça rame » se joue dans le nombre
# d'images que l'app rate pendant qu'il fait glisser la carte.
#
# ⚠️ **`--profile`, et c'est le point entier de ce script.** En `debug`, le Dart
# est interprété et les assertions tournent : les temps d'image y sont deux à
# dix fois pires qu'en production, sans aucun rapport avec ce que vit un
# utilisateur. Un profilage en debug ne mesure pas le produit, il mesure le mode
# debug — et il ferait « optimiser » du code qui n'a rien.
#
# ⚠️ Un lanceur SÉPARÉ (`test_driver/perf_driver.dart`) : `integrationDriver()`
# sans rappel JETTE les données de performance. Le parcours pourrait mesurer des
# milliers d'images et rien n'en sortirait — un profilage silencieusement vide,
# qui se lit comme un profilage réussi.
#
# ⚠️ Un émulateur n'est pas un téléphone : sans accélération GPU, la
# rastérisation y est exagérée. Un dépassement de ce côté doit être remesuré sur
# un vrai appareil avant d'être cru ; la construction, elle, est du code Dart et
# se transpose beaucoup mieux.
#
# ⚠️ `flutter drive` DÉSINSTALLE l'application à la fin : les préférences de vos
# tests manuels seront effacées.
#
#   ./scripts/test-perf-carte.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
  echo "❌ python3 ou python requis — l'absence de verdict n'est pas un verdict."
  exit 2; }
PY=$(command -v python3 || command -v python)
export PYTHONIOENCODING=utf-8

cd "$RACINE" || exit 2

echo "── auto-test du banc ──"
SORTIE="$("$PY" "$HERE/lib/perf_carte.py" --self-test)" || {
  echo "$SORTIE"; echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2; }
echo "$SORTIE"
echo "$SORTIE" | grep -q "^auto-test : [0-9]\+ cas, dont [0-9]\+ refus$" || {
  echo "❌ l'auto-test n'a annoncé aucun cas — module vide ou tronqué."; exit 2; }

# ⚠️ **À changer pour un vrai téléphone, et ce n'est pas cosmétique.** La
# rastérisation mesurée sur cet émulateur dépasse largement le budget (p90
# 34,7 ms le 2026-08-13) alors que la construction Dart est excellente (2,6 ms).
# Sans accélération GPU, un émulateur exagère le dessin dans des proportions qui
# n'ont aucun rapport avec un appareil réel : tant que la mesure n'a pas été
# refaite sur un téléphone, le rouge côté rastérisation n'accuse pas le produit.
#
#   APPAREIL=<id adb du téléphone> ./scripts/test-perf-carte.sh
APPAREIL="${APPAREIL:-emulator-5554}"

VILLE_LAT="${VILLE_LAT:-34.6703}"
VILLE_LNG="${VILLE_LNG:-3.2630}"

# ⚠️ La capture précédente est supprimée AVANT de lancer : sans ça, un parcours
# qui échoue laisserait le banc juger les chiffres de la fois d'avant, et rendre
# vert sur une mesure qui n'a pas eu lieu.
rm -f apps/mobile/build/perf_carte.json

echo
echo "── profilage sur l'appareil (--profile), point $VILLE_LAT,$VILLE_LNG ──"
# ⚠️ **`--no-dds` est indispensable, et l'erreur ne le dit qu'après coup.**
# `watchPerformance` ouvre une connexion au VM Service depuis l'appareil pour
# activer la timeline. Le Dart Development Service s'interpose sur ce port et la
# refuse : « Bad state: Failed to connect to VM Service … Connection refused ».
# Le parcours échoue alors APRÈS avoir démarré l'app et ouvert la carte, ce qui
# ressemble à un défaut du parcours plutôt qu'à un défaut d'outillage.
# Mesuré le 2026-08-13, au premier lancement.
( cd apps/mobile && flutter drive \
    --driver=test_driver/perf_driver.dart \
    --target=integration_test/perf_carte_test.dart \
    --profile \
    --no-dds \
    -d "$APPAREIL" \
    --dart-define=SANS_GPS=oui \
    --dart-define=TEST_VILLE_LAT="$VILLE_LAT" \
    --dart-define=TEST_VILLE_LNG="$VILLE_LNG" )
CODE_DRIVE=$?

if [ ! -f apps/mobile/build/perf_carte.json ]; then
  echo
  echo "❌ aucune capture produite (flutter drive a rendu $CODE_DRIVE)."
  echo "   Un profilage sans mesure n'est pas un profilage réussi."
  exit 2
fi

echo
exec "$PY" "$HERE/lib/perf_carte.py" "$@"
