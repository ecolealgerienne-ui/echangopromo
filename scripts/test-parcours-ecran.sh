#!/usr/bin/env bash
# Parcours joués sur l'appareil — étape 3 de docs/METHODE_TEST.md.
#
# ── Ce que ce script fait, et pourquoi il existe ─────────────────────────────
#
# Un parcours écran a besoin de trois choses qu'aucune d'elles ne connaît seule :
# un décor posé côté serveur, les identifiants qui vont avec, et les VALEURS
# ATTENDUES mesurées sur ce décor. Les assembler à la main, c'est se tromper une
# fois sur deux et accuser l'écran.
#
# Ce script les assemble : il pose le décor, interroge le serveur pour la mesure
# de référence (`GET /promo/me/slots`), puis lance `flutter drive` avec ces
# valeurs en `--dart-define`.
#
# ⚠️ **La mesure vient du SERVEUR, jamais d'une constante écrite ici.** Recopier
# « 5 » dans ce script reproduirait exactement le défaut que le parcours doit
# empêcher : le plafond était figé dans les fichiers de traduction, et personne
# ne s'en apercevait parce que le chiffre était juste ce jour-là.
#
# ── Prérequis ────────────────────────────────────────────────────────────────
#
#   · le backend tourne (voir docs/status_v0.1.md — § Environnement)
#   · un émulateur ou un appareil est branché (`flutter devices`)
#
# ── Usage ────────────────────────────────────────────────────────────────────
#
#   ./scripts/test-parcours-ecran.sh
#   API_URL=http://10.0.2.2:3000 ./scripts/test-parcours-ecran.sh
set -u

RACINE="$(cd "$(dirname "$0")/.." && pwd)"
API_URL="${API_URL:-http://localhost:3000}"
# ⚠️ Ce que l'APP appelle, vu depuis l'émulateur — pas la même chose que ce que
# ce script appelle depuis la machine. Même piège que S3_ENDPOINT (P9).
API_URL_APP="${API_URL_APP:-http://10.0.2.2:3000}"
DEVICE_ID="parcours-ecran-0001"

echo "════════════════════════════════════════════════════════════════"
echo "  Parcours écran — décor, mesure, puis flutter drive"
echo "════════════════════════════════════════════════════════════════"
echo

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
  echo "❌ python3 requis (lecture du JSON)."; exit 2; }
PY=$(command -v python3 || command -v python)

# ── 1. Décor ────────────────────────────────────────────────────────────────
#
# ⚠️ **Ce script vit à cheval sur deux machines, et il faut le dire.** Sur le
# poste de développement, le décor tourne sous WSL (c'est là que sont le
# backend et `jq`) tandis que `flutter drive` tourne sous Windows (c'est là
# qu'est l'émulateur). Aucun des deux ne peut faire le travail de l'autre.
#
# D'où les deux modes : si `TEST_COMMERCANT_TEL` et `TEST_COMMERCANT_PIN` sont
# déjà dans l'environnement, on les prend et on ne pose rien ; sinon on pose le
# décor ici — ce qui suppose `jq`, donc en pratique une machine où le dépôt et
# le backend cohabitent (CI, Linux).
if [ -n "${TEST_COMMERCANT_TEL:-}" ] && [ -n "${TEST_COMMERCANT_PIN:-}" ]; then
  TEL="$TEST_COMMERCANT_TEL"
  PIN="$TEST_COMMERCANT_PIN"
  echo "── 1. Décor — fourni par l'appelant ($TEL) ──"
  echo "   (pose du décor sautée : identifiants déjà dans l'environnement)"
else
  command -v jq >/dev/null 2>&1 || {
    echo "❌ jq absent, et aucun identifiant fourni."
    echo "   Sur ce poste, poser le décor depuis WSL puis relancer ici avec :"
    echo "     TEST_COMMERCANT_TEL=… TEST_COMMERCANT_PIN=… $0"
    exit 2; }
  # Un commerçant NEUF à chaque passage : le compte par défaut du décor épuise
  # ses quotas anti-abus (5 créations/24 h, cooldown de republication) dès
  # qu'un banc est passé avant. Un parcours qui échoue parce qu'un autre banc a
  # tourné le matin n'apprend rien sur l'écran.
  TEL="+213555$(date +%H%M%S)"
  echo "── 1. Décor (commerçant $TEL) ──"
  if ! D_COMMERCANT_TEL="$TEL" "$RACINE/scripts/provision-decor.sh" \
      > /tmp/parcours-decor.out 2>&1; then
    echo "❌ Le décor a échoué :"
    tail -12 /tmp/parcours-decor.out
    exit 2
  fi
  PIN="$(grep -oE "COMMERCANT_PIN='[^']*'" /tmp/parcours-decor.out \
    | head -1 | cut -d"'" -f2)"
  [ -n "$PIN" ] || { echo "❌ PIN introuvable dans la sortie du décor."; exit 2; }
  echo "✅ Décor posé"
fi

# ── 2. Mesure de référence ──────────────────────────────────────────────────
echo
echo "── 2. Mesure servie par le serveur ──"
lire_champ() { # CHAMP — lit un champ de l'objet JSON reçu sur stdin
  "$PY" -c "import sys,json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
v = d.get('$1')
print('' if v is None else v)"
}

JETON="$(curl -s -X POST "$API_URL/commercant/login" \
  -H 'Content-Type: application/json' -H "X-Device-Id: $DEVICE_ID" \
  -d "{\"telephone\":\"$TEL\",\"pin\":\"$PIN\"}" | lire_champ accessToken)"
if [ -z "$JETON" ]; then
  echo "❌ Connexion du commerçant du décor impossible."
  echo "   ⚠️ Un 429 se déguise en « identifiants incorrects » : le décor vient"
  echo "      de consommer plusieurs connexions sur un plafond de 5/min."
  exit 2
fi

SLOTS="$(curl -s "$API_URL/promo/me/slots" \
  -H "Authorization: Bearer $JETON" -H "X-Device-Id: $DEVICE_ID")"
PLAFOND="$(echo "$SLOTS" | lire_champ plafond)"
EN_LIGNE="$(echo "$SLOTS" | lire_champ enLigne)"
# ⚠️ Chaîne vide et non « 0 » quand le champ manque : une réponse illisible
# doit s'arrêter ici, pas produire un zéro qui ferait échouer le parcours en
# accusant l'écran (règle #29).
if [ -z "$PLAFOND" ] || [ -z "$EN_LIGNE" ]; then
  echo "❌ /promo/me/slots illisible : $(echo "$SLOTS" | head -c 200)"
  exit 2
fi
echo "✅ enLigne=$EN_LIGNE  plafond=$PLAFOND"

# ── 3. Le parcours ──────────────────────────────────────────────────────────
echo
echo "── 3. flutter drive ──"
cd "$RACINE/apps/mobile" || exit 2
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/parcours_plafond_commercant_test.dart \
  --dart-define=API_BASE_URL="$API_URL_APP" \
  --dart-define=TEST_COMMERCANT_TEL="$TEL" \
  --dart-define=TEST_COMMERCANT_PIN="$PIN" \
  --dart-define=TEST_PLAFOND="$PLAFOND" \
  --dart-define=TEST_EN_LIGNE="$EN_LIGNE"
CODE=$?

echo
if [ $CODE -eq 0 ]; then
  echo "✅ parcours écran : le compteur affiche bien $EN_LIGNE / $PLAFOND"
else
  echo "❌ parcours écran en échec (code $CODE)"
fi
exit $CODE
