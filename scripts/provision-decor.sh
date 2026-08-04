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
D_AGENT_B_EMAIL="${D_AGENT_B_EMAIL:-decor-agent-b@echango.local}"
D_AGENT_B_PASSWORD="${D_AGENT_B_PASSWORD:-decor-agent-b-2026}"
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
step "2. Deux communes DISJOINTES"

# ⚠️ Deux communes, et c'est le cœur du banc d'appartenance : sans une seconde
# commune, l'agent intrus serait un agent sans commune — un cas dégénéré qui ne
# prouve rien du filtre réel.
COMMUNE_JSON="$(api GET /commune)"
COMMUNE_ID="$(echo "$COMMUNE_JSON" | jq -r '.items[0].id // empty')"
COMMUNE_NOM="$(echo "$COMMUNE_JSON" | jq -r '.items[0].nom // empty')"
COMMUNE_B_ID="$(echo "$COMMUNE_JSON" | jq -r '.items[1].id // empty')"
COMMUNE_B_NOM="$(echo "$COMMUNE_JSON" | jq -r '.items[1].nom // empty')"
[ -n "$COMMUNE_ID" ] || fail "Aucune commune en base" "lancer npm run seed:communes"
[ -n "$COMMUNE_B_ID" ] || fail "Une seule commune en base — le banc d'appartenance en exige deux"
pass "Commune A « $COMMUNE_NOM » · Commune B « $COMMUNE_B_NOM »"

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
pass "Agent A connecté ($D_AGENT_EMAIL) — commune « $COMMUNE_NOM »"

# ── Agent B : l'intrus du banc d'appartenance ────────────────────────────────
agent_b_login() {
  api POST /agent/login "$(jq -n --arg e "$D_AGENT_B_EMAIL" --arg p "$D_AGENT_B_PASSWORD" \
    '{email:$e, password:$p}')" | jq -r '.accessToken // empty'
}

sleep "$PACE"
AGENT_B_TOKEN="$(agent_b_login)"
if [ -z "$AGENT_B_TOKEN" ]; then
  info "Absent — création via POST /admin/agent, sur la commune B"
  out="$(api POST /admin/agent "$(jq -n --arg e "$D_AGENT_B_EMAIL" --arg p "$D_AGENT_B_PASSWORD" \
    --arg c "$COMMUNE_B_ID" '{email:$e, password:$p, nom:"Agent Décor B", communeIds:[$c]}')" \
    "$ADMIN_TOKEN")"
  echo "$out" | est_erreur && fail "Création agent B refusée" "$(echo "$out" | jq -c '{code,message}')"
  sleep "$PACE"
  AGENT_B_TOKEN="$(agent_b_login)"
  [ -n "$AGENT_B_TOKEN" ] || fail "Connexion agent B impossible après création"
fi
pass "Agent B connecté ($D_AGENT_B_EMAIL) — commune « $COMMUNE_B_NOM »"

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
  | jq -r --arg t "$D_COMMERCANT_TEL" '.items[]? | select(.telephone==$t) | .id' | head -1)"
[ -n "$CID" ] || fail "Commerçant introuvable côté admin après inscription"

# ⚠️ **Deux gestes, pas un.** Le commerçant SOUMET son registre, l'admin le
# VALIDE. Une première version n'appelait que la validation, et masquait son
# échec derrière `|| true` : le décor annonçait « registre validé » sur un
# refus `COMMERCANT_NO_PENDING_REGISTRE_VERIFICATION`, et la création de promo
# échouait trois étapes plus loin en accusant autre chose. Le pire endroit pour
# un repli est un script de décor.
# ⚠️ `limit` est plafonné côté serveur : une valeur trop grande rend un 400, et
# un `(.items // .)` complaisant se met alors à itérer l'objet d'erreur au lieu
# d'échouer. Le repli masquait la panne — on lit donc `.items` et rien d'autre.
liste="$(api GET "/admin/commercant?limit=100" '' "$ADMIN_TOKEN")"
echo "$liste" | est_erreur && fail "Liste des commerçants refusée" \
  "$(echo "$liste" | jq -c '{code,message}')"
ETAT="$(echo "$liste" | jq -r --arg t "$D_COMMERCANT_TEL" \
  '.items[] | select(.telephone==$t) | .registreStatus // "aucun"')"

if [ "$ETAT" != "valide" ]; then
  # La clé doit porter le préfixe posé par StorageService.buildKey, sinon
  # COMMERCANT_REGISTRE_KEY_MISMATCH (garde d'appartenance sur le document).
  out="$(api POST /commercant/me/registre \
    "$(jq -n --arg k "registre-documents/$CID/decor.jpg" '{registreKey:$k}')" "$COMMERCANT_TOKEN")"
  echo "$out" | est_erreur && fail "Soumission du registre refusée" \
    "$(echo "$out" | jq -c '{code,message}')"

  out="$(api POST "/admin/commercant/$CID/registre/valider" '{}' "$ADMIN_TOKEN")"
  echo "$out" | est_erreur && fail "Validation du registre refusée" \
    "$(echo "$out" | jq -c '{code,message}')"
fi
pass "Registre validé — commerçant $CID"

# ─────────────────────────────────────────────────────────────────────────────
step "5. Une promo appartenant à ce commerçant"

# Le banc d'appartenance a besoin d'une ressource RÉELLE à cibler : une promo
# inexistante rendrait « introuvable » pour la mauvaise raison, et le banc
# conclurait juste par accident.
PROMO_ID="$(api GET "/promo/me/all?limit=1" '' "$COMMERCANT_TOKEN" \
  | jq -r '.items[0].id // empty')"

if [ -z "$PROMO_ID" ]; then
  info "Aucune — création"
  fin="$(date -u -d '+20 days' +%Y-%m-%dT%H:%M:%S.000Z)"
  out="$(api POST /promo "$(jq -n --arg f "$fin" \
    '{description:"Promo du décor", prixAvant:1000, prixApres:700,
      categorie:"alimentation", photoKeys:["promo-photos/decor/decor.jpg"], dateFin:$f}')" \
    "$COMMERCANT_TOKEN")"
  echo "$out" | est_erreur && fail "Création promo refusée" "$(echo "$out" | jq -c '{code,message}')"
  PROMO_ID="$(echo "$out" | jq -r '.id // empty')"
  [ -n "$PROMO_ID" ] || fail "Promo créée sans id" "$(echo "$out" | head -c 200)"
  api POST "/promo/$PROMO_ID/publish" '{}' "$COMMERCANT_TOKEN" >/dev/null 2>&1 || true
fi
pass "Promo $PROMO_ID"

# ─────────────────────────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════════════════════"
echo "  Décor posé. Bloc à exporter avant de lancer un banc :"
echo "════════════════════════════════════════════════════════════════"
cat <<EOF

export API_URL='$API_URL'
export ADMIN_EMAIL='$D_ADMIN_EMAIL'             ADMIN_PASSWORD='$D_ADMIN_PASSWORD'
export AGENT_EMAIL='$D_AGENT_EMAIL'             AGENT_PASSWORD='$D_AGENT_PASSWORD'
export AGENT_B_EMAIL='$D_AGENT_B_EMAIL'   AGENT_B_PASSWORD='$D_AGENT_B_PASSWORD'
export COMMERCANT_TEL='$D_COMMERCANT_TEL'       COMMERCANT_PIN='$D_COMMERCANT_PIN'
export COMMERCANT_ID='$CID'
export PROMO_ID='$PROMO_ID'

⚠️ Le banc de refus révoque le jeton admin au démarrage — c'est son troisième
   échantillon. Ce décor étant rejouable, il suffit de le relancer si besoin.

⚠️ Ce script vient de consommer plusieurs connexions sur un plafond de 5/min.
   Attendre une minute avant de lancer un banc, sinon le 429 se déguisera en
   « identifiants incorrects ».

EOF
