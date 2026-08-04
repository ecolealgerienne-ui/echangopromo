#!/usr/bin/env bash
#
# Pose le décor minimal des bancs — echango Promo.
#
# ── Ce script ne teste rien ─────────────────────────────────────────────────
#
# Il **provisionne**, et rien d'autre. Ce qui est vérifié l'est par les bancs.
# Mélanger les deux fait échouer deux choses ensemble, la seconde accusant la
# première.
#
# Il pose ce qu'un banc ne peut pas poser lui-même :
#   - un **admin** aux identifiants connus (le seul en base a un mot de passe
#     que personne ne connaît) ;
#   - un **agent** rattaché à une commune — il n'y en a aucun en base ;
#   - un **commerçant** actif, registre validé.
#
# ── ⚠️ Idempotent, et c'est une contrainte de plafond ───────────────────────
#
# Les identifiants sont **stables**, jamais aléatoires : `STRICT_THROTTLE`
# plafonne connexions et inscriptions à 5/min/IP. On tente donc la connexion
# d'abord — si elle réussit, le compte existe et on ne consomme rien de plus.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh
#
# Il imprime en fin de course le bloc `export` à coller avant de lancer un banc.

set -uo pipefail

API_URL="${API_URL:-http://localhost:3000}"
PACE="${PACE_SECONDS:-13}"   # 5 connexions/min => ~12s entre deux

# ⚠️ Stables. Voir l'en-tête.
D_ADMIN_EMAIL="${D_ADMIN_EMAIL:-decor-admin@echango.local}"
D_ADMIN_PASSWORD="${D_ADMIN_PASSWORD:-decor-admin-2026}"
D_AGENT_EMAIL="${D_AGENT_EMAIL:-decor-agent@echango.local}"
D_AGENT_PASSWORD="${D_AGENT_PASSWORD:-decor-agent-2026}"
D_COMMERCANT_TEL="${D_COMMERCANT_TEL:-+213555000101}"
D_COMMERCANT_PIN="${D_COMMERCANT_PIN:-654321}"

BACKEND_DIR="${BACKEND_DIR:-$(cd "$(dirname "$0")/../apps/backend" && pwd)}"

command -v jq >/dev/null 2>&1 || { echo "❌ jq requis."; exit 2; }

pass() { echo "✅ $1"; }
info() { echo "   $1"; }
step() { echo; echo "── $1 ──"; }
fail() { echo "❌ $1" >&2; [ -n "${2:-}" ] && echo "   Réponse : $2" >&2; exit 2; }

api() { # METHODE CHEMIN [CORPS] [JETON]
  local m="$1" p="$2" body="${3:-}" tok="${4:-}"
  local args=(-sS -X "$m" "$API_URL$p" -H 'Content-Type: application/json')
  [ -n "$body" ] && args+=(-d "$body")
  [ -n "$tok" ] && args+=(-H "Authorization: Bearer $tok")
  curl "${args[@]}"
}

# ⚠️ Reconnaît une erreur par `statusCode`, jamais par la seule présence d'un
# champ `code` : `code` existe aussi sur des réponses de succès, donc le tester
# lirait un succès comme un échec.
est_erreur() { jq -e 'type == "object" and ((.statusCode | type) == "number")' >/dev/null 2>&1; }

echo "════════════════════════════════════════════════════════════════"
echo "  Décor des bancs — $API_URL"
echo "════════════════════════════════════════════════════════════════"

curl -sS -o /dev/null "$API_URL/commune" || fail "Backend injoignable sur $API_URL"

# ─────────────────────────────────────────────────────────────────────────────
step "1. Admin aux identifiants connus"

admin_login() {
  api POST /admin/login "$(jq -n --arg e "$D_ADMIN_EMAIL" --arg p "$D_ADMIN_PASSWORD" \
    '{email:$e, password:$p}')" | jq -r '.accessToken // empty'
}

ADMIN_TOKEN="$(admin_login)"
if [ -z "$ADMIN_TOKEN" ]; then
  info "Absent — création par le script de seed (hors API, rôle d'administration)"
  ( cd "$BACKEND_DIR" && npm run --silent seed:admin -- \
      "$D_ADMIN_EMAIL" "$D_ADMIN_PASSWORD" "Admin Décor" ) >/dev/null 2>&1 \
    || fail "seed:admin a échoué" "lancer à la main dans $BACKEND_DIR pour voir l'erreur"
  sleep "$PACE"
  ADMIN_TOKEN="$(admin_login)"
  [ -n "$ADMIN_TOKEN" ] || fail "Connexion admin impossible après création"
fi
pass "Admin connecté ($D_ADMIN_EMAIL)"

# ─────────────────────────────────────────────────────────────────────────────
step "2. Commune de travail"

COMMUNE_JSON="$(api GET /commune)"
COMMUNE_ID="$(echo "$COMMUNE_JSON" | jq -r '(.items // .)[0].id // empty')"
COMMUNE_NOM="$(echo "$COMMUNE_JSON" | jq -r '(.items // .)[0].nom // empty')"
[ -n "$COMMUNE_ID" ] || fail "Aucune commune en base" "lancer npm run seed:communes"
pass "Commune « $COMMUNE_NOM »"

# ─────────────────────────────────────────────────────────────────────────────
step "3. Agent rattaché à cette commune"

agent_login() {
  api POST /agent/login "$(jq -n --arg e "$D_AGENT_EMAIL" --arg p "$D_AGENT_PASSWORD" \
    '{email:$e, password:$p}')" | jq -r '.accessToken // empty'
}

sleep "$PACE"
AGENT_TOKEN="$(agent_login)"
if [ -z "$AGENT_TOKEN" ]; then
  info "Absent — création via POST /admin/agent"
  out="$(api POST /admin/agent "$(jq -n --arg e "$D_AGENT_EMAIL" --arg p "$D_AGENT_PASSWORD" \
    --arg c "$COMMUNE_ID" '{email:$e, password:$p, nom:"Agent Décor", communeIds:[$c]}')" \
    "$ADMIN_TOKEN")"
  echo "$out" | est_erreur && fail "Création agent refusée" "$(echo "$out" | jq -c '{code,message}')"
  sleep "$PACE"
  AGENT_TOKEN="$(agent_login)"
  [ -n "$AGENT_TOKEN" ] || fail "Connexion agent impossible après création"
fi
pass "Agent connecté ($D_AGENT_EMAIL)"

# ─────────────────────────────────────────────────────────────────────────────
step "4. Commerçant actif, registre validé"

commercant_login() {
  api POST /commercant/login "$(jq -n --arg t "$D_COMMERCANT_TEL" --arg p "$D_COMMERCANT_PIN" \
    '{telephone:$t, pin:$p}')" | jq -r '.accessToken // empty'
}

sleep "$PACE"
COMMERCANT_TOKEN="$(commercant_login)"
if [ -z "$COMMERCANT_TOKEN" ]; then
  info "Absent — inscription (consomme 1 sur le plafond horaire)"
  out="$(api POST /commercant/register "$(jq -n --arg t "$D_COMMERCANT_TEL" \
    --arg p "$D_COMMERCANT_PIN" --arg c "$COMMUNE_ID" \
    '{telephone:$t, nom:"Commerce Décor", adresse:"Rue du Décor", categorie:"alimentation",
      communeId:$c, pin:$p, acceptedTerms:true}')")"
  echo "$out" | est_erreur && fail "Inscription commerçant refusée" \
    "$(echo "$out" | jq -c '{code,message}')"
  sleep "$PACE"
  COMMERCANT_TOKEN="$(commercant_login)"
  [ -n "$COMMERCANT_TOKEN" ] || fail "Connexion commerçant impossible après inscription"
fi
pass "Commerçant connecté ($D_COMMERCANT_TEL)"

# Validation du registre — geste d'administration, pas geste d'utilisateur.
CID="$(api GET "/admin/commercant?limit=100" '' "$ADMIN_TOKEN" \
  | jq -r --arg t "$D_COMMERCANT_TEL" '(.items // .)[] | select(.telephone==$t) | .id' | head -1)"
if [ -n "$CID" ]; then
  api POST "/admin/commercant/$CID/registre/valider" '{}' "$ADMIN_TOKEN" >/dev/null 2>&1 || true
  info "Registre validé (ou déjà validé)"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════════════════════"
echo "  Décor posé. Bloc à exporter avant de lancer un banc :"
echo "════════════════════════════════════════════════════════════════"
cat <<EOF

export API_URL='$API_URL'
export ADMIN_EMAIL='$D_ADMIN_EMAIL'         ADMIN_PASSWORD='$D_ADMIN_PASSWORD'
export AGENT_EMAIL='$D_AGENT_EMAIL'         AGENT_PASSWORD='$D_AGENT_PASSWORD'
export COMMERCANT_TEL='$D_COMMERCANT_TEL'   COMMERCANT_PIN='$D_COMMERCANT_PIN'

⚠️ Le banc de refus révoque le jeton admin au démarrage — c'est son troisième
   échantillon. Ce décor étant rejouable, il suffit de le relancer si besoin.

⚠️ Ce script vient de consommer plusieurs connexions sur un plafond de 5/min.
   Attendre une minute avant de lancer un banc, sinon le 429 se déguisera en
   « identifiants incorrects ».

EOF
