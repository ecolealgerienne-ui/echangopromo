#!/usr/bin/env bash
#
# Décor des parcours joués DANS l'application — squelette.
#
# ── Ce script ne teste rien ─────────────────────────────────────────────────
#
# Il **provisionne**. Ce qui est vérifié l'est par `integration_test/`, dans
# l'application. Mélanger les deux (mode M8) fait échouer deux tests ensemble,
# le second accusant le premier.
#
# Il pose ce que le parcours écran ne peut PAS poser lui-même, parce qu'aucun de
# ces gestes n'est un geste d'utilisateur :
#
#   1. **Ce qui demande un rôle d'administration** — activer un compte en
#      attente, valider un registre. Le garde n'est pas contourné : c'est le
#      rôle d'admin qui est tenu ici.
#   2. **Ce qui serait fragile à piloter à l'écran** — désigner un point sur une
#      carte glissante. Fragile, et ça ne prouve rien du métier.
#   3. **Les ressources que le parcours va consommer** — sinon le parcours A
#      doit créer ce que le parcours B consomme, et ils échouent ensemble.
#
# ── ⚠️ Idempotent, et c'est une contrainte de plafond, pas de confort ───────
#
# Les identifiants sont **stables**, jamais aléatoires. Les endpoints
# d'inscription et de connexion sont rate-limités (mode M9) : une version à
# `$RANDOM` rend ce script inutilisable au second passage de la journée. Sur un
# compte déjà présent, l'inscription répond le même refus et l'activation ne
# coûte rien — on rejoue sans rien consommer.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh
#
# Il imprime en fin de course la commande `flutter drive` à lancer côté
# Windows, avec les --dart-define correspondant à ce qu'il vient de poser.

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# À ADAPTER — configuration
# ─────────────────────────────────────────────────────────────────────────────

API_URL="${API_URL:-http://localhost:3000}"
PASSWORD="${PASSWORD:-motdepasse123}"

# ⚠️ Stables. Voir l'en-tête.
MERCHANT_EMAIL="${MERCHANT_EMAIL:-decor-commercant@echango.local}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@echango.local}"

# Une valeur DISTINCTIVE par ressource que le parcours doit reconnaître.
#
# ⚠️ Le parcours reconnaît sa ressource par une **donnée du décor**, jamais par
# un libellé traduit (mode M6) — et pas non plus par un champ que l'écran
# masque. Choisir une valeur qui est réellement AFFICHÉE sur la carte de liste.
PRIX_DISTINCTIF="${PRIX_DISTINCTIF:-777}"
NOM_DISTINCTIF="${NOM_DISTINCTIF:-Commerce Parcours}"

command -v jq >/dev/null 2>&1 || { echo "❌ jq requis." >&2; exit 1; }

pass() { echo "✅ $1"; }
info() { echo "   $1"; }
step() { echo; echo "── $1 ──"; }
fail() { echo "❌ $1" >&2; [ -n "${2:-}" ] && echo "   Réponse : $2" >&2; exit 1; }

# Reconnaît une erreur de l'API sur stdin.
#
# ⚠️ Par le **code HTTP** ou par `statusCode`, jamais par la seule présence d'un
# champ `code` : `code` peut exister sur des réponses de succès, donc le tester
# lirait un succès comme un échec. Constaté ailleurs : une route écrite à
# l'envers rendait un 404 sans champ `code`, et le script annonçait
# « ✅ inscription enregistrée » avant d'échouer trois étapes plus loin en
# accusant l'activation (mode M3 — le pire endroit pour un repli est un test).
is_error() { jq -e 'type == "object" and ((.statusCode | type) == "number")' >/dev/null 2>&1; }

api() { # METHODE CHEMIN [CORPS] [JETON]
  local m="$1" p="$2" body="${3:-}" tok="${4:-}"
  local args=(-sS -X "$m" "$API_URL$p" -H 'Content-Type: application/json')
  [ -n "$body" ] && args+=(-d "$body")
  [ -n "$tok" ] && args+=(-H "Authorization: Bearer $tok")
  curl "${args[@]}"
}

# ─────────────────────────────────────────────────────────────────────────────

echo "════════════════════════════════════════════════════════════════"
echo "  Décor des parcours écran"
echo "════════════════════════════════════════════════════════════════"

step "1. Session d'administration"
# À ADAPTER : c'est l'admin qui active les comptes en attente et valide les
# ressources. Sans lui, aucun persona ne peut se connecter.
ADMIN_TOKEN="$(api POST /admin/login "$(jq -n --arg e "$ADMIN_EMAIL" --arg p "$PASSWORD" \
  '{email:$e, password:$p}')" | jq -r '.token // empty')"
[ -n "$ADMIN_TOKEN" ] || fail "Connexion admin impossible" \
  "vérifier que le seed admin a tourné (npm run seed:admin)"
pass "Admin connecté"

step "2. Comptes personas — inscription puis activation"
# ⚠️ **Ne pas dépenser une inscription pour apprendre ce qu'une connexion dit
# gratuitement.** On tente d'abord la connexion : si elle réussit, le compte
# existe déjà et on ne consomme rien sur le plafond horaire.
MERCHANT_TOKEN="$(api POST /commercant/login "$(jq -n --arg e "$MERCHANT_EMAIL" --arg p "$PASSWORD" \
  '{email:$e, password:$p}')" | jq -r '.token // empty')"

if [ -z "$MERCHANT_TOKEN" ]; then
  info "Compte absent — inscription (consomme 1 sur le plafond horaire)"
  out="$(api POST /commercant/register "$(jq -n --arg e "$MERCHANT_EMAIL" --arg p "$PASSWORD" \
    --arg n "$NOM_DISTINCTIF" '{email:$e, password:$p, nom:$n}')")"
  # À ADAPTER : le refus « en attente » EST le résultat attendu ici.
  echo "$out" | is_error || info "Inscription acceptée directement"

  # L'activation par l'admin — le geste qui n'est pas un geste d'utilisateur.
  ID="$(api GET "/admin/commercant?q=$MERCHANT_EMAIL" '' "$ADMIN_TOKEN" \
    | jq -r '.items[0].id // empty')"
  [ -n "$ID" ] || fail "Commerçant introuvable après inscription" "$out"
  api POST "/admin/commercant/$ID/registre/valider" '{}' "$ADMIN_TOKEN" >/dev/null

  MERCHANT_TOKEN="$(api POST /commercant/login "$(jq -n --arg e "$MERCHANT_EMAIL" --arg p "$PASSWORD" \
    '{email:$e, password:$p}')" | jq -r '.token // empty')"
  [ -n "$MERCHANT_TOKEN" ] || fail "Connexion impossible après activation"
fi
pass "Commerçant activé et connecté"

step "3. Ressources à consommer par le parcours"
# À ADAPTER. ⚠️ Prévoir de la MARGE : un parcours qui échoue en route consomme
# parfois une ressource sans la rendre.
SPARE="${SPARE:-3}"
for i in $(seq 1 "$SPARE"); do
  api POST /commercant/promo "$(jq -n --arg p "$PRIX_DISTINCTIF" \
    '{description:"Promo décor", prixAvant:1000, prixApres:($p|tonumber), categorie:"alimentation"}')" \
    "$MERCHANT_TOKEN" >/dev/null
done
pass "$SPARE ressource(s) posée(s), reconnaissables au prix $PRIX_DISTINCTIF"

# ─────────────────────────────────────────────────────────────────────────────
# La commande de test — c'est le décor qui sait ce qu'il a posé
# ─────────────────────────────────────────────────────────────────────────────

echo
echo "════════════════════════════════════════════════════════════════"
echo "  Décor posé. Côté Windows, lancer :"
echo "════════════════════════════════════════════════════════════════"
cat <<EOF

cd apps/mobile
flutter drive \\
  --driver=test_driver/integration_test.dart \\
  --target=integration_test/parcours_test.dart \\
  -d <émulateur> \\
  --dart-define=API_BASE_URL=http://10.0.2.2:3000 \\
  --dart-define=TEST_MERCHANT_EMAIL=$MERCHANT_EMAIL \\
  --dart-define=TEST_PASSWORD=$PASSWORD \\
  --dart-define=TEST_PRIX_DISTINCTIF=$PRIX_DISTINCTIF \\
  --dart-define=TEST_NOM_DISTINCTIF="$NOM_DISTINCTIF"

⚠️ Depuis un émulateur Android, 'localhost' désigne l'émulateur lui-même.
   10.0.2.2 est l'alias de la machine hôte. Depuis un téléphone réel, mettre
   l'IP de la machine sur le réseau local.

⚠️ Appeler 'flutter' directement, jamais via un lanceur qui reconstruit la
   ligne de commande : les --dart-define s'y perdent silencieusement, le build
   part avec les valeurs par défaut, et le test s'exécute contre la production.

EOF
