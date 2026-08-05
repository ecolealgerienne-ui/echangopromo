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
# Identifiant d'appareil du décor, requis par les routes client anonymes
# (`@DeviceId()`). Fixe et reconnaissable : ce décor ne mesure pas de vues, il
# a seulement besoin que l'en-tête existe.
D_DEVICE_ID="${D_DEVICE_ID:-decor-provisioning-0001}"

BACKEND_DIR="${BACKEND_DIR:-$(cd "$(dirname "$0")/../apps/backend" && pwd)}"

command -v jq >/dev/null 2>&1 || { echo "❌ jq requis."; exit 2; }

pass() { echo "✅ $1"; }
info() { echo "   $1"; }
step() { echo; echo "── $1 ──"; }
fail() { echo "❌ $1" >&2; [ -n "${2:-}" ] && echo "   Réponse : $2" >&2; exit 2; }

api() { # METHODE CHEMIN [CORPS] [JETON]
  local m="$1" p="$2" body="${3:-}" tok="${4:-}"
  local args=(-sS -X "$m" "$API_URL$p" -H 'Content-Type: application/json')
  # ⚠️ `X-Device-Id` sur TOUS les appels (2026-08-05). Les routes client
  # anonymes l'exigent (`@DeviceId()` — `GET /promo/:id` compte les vues,
  # `POST /report` en dépend pour l'anti-abus) et refusent en
  # `DEVICE_ID_MISSING` sans lui. Il est inoffensif partout ailleurs.
  #
  # Sans ça, la vérification d'état finale de l'étape 5 ne lisait pas un
  # statut mais un objet d'erreur, et `.lifecycleStatus // empty` le
  # transformait en chaîne vide : le décor annonçait « promo non publiée » sur
  # une promo parfaitement publiée. Ce contrôle n'avait donc JAMAIS pu réussir
  # depuis son ajout — un contrôle qu'on n'a jamais vu passer est aussi
  # suspect qu'un contrôle qu'on n'a jamais vu refuser (règle #28).
  args+=(-H "X-Device-Id: $D_DEVICE_ID")
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
# ⚠️ **Le rattachement est VÉRIFIÉ, pas annoncé** (2026-08-05).
#
# Les communes n'étaient posées qu'à la CRÉATION de l'agent. Sur un agent déjà
# existant, le décor se contentait de se connecter puis d'imprimer
# « commune « Ain Chouhada » » — une affirmation, pas une mesure. Agent A avait
# ainsi accumulé QUATRE communes au fil des sessions, dont celle de l'agent B :
# les deux territoires, annoncés disjoints, se chevauchaient.
#
# Ce n'est pas un détail de confort. `test-appartenance` repose entièrement sur
# cette disjonction : l'agent B y sert d'intrus, et s'il partage une commune
# avec A, la sonde teste un refus qui n'avait pas lieu d'être. Un décor qui
# affirme sans vérifier fabrique exactement le genre de banc qui rassure.
assurer_communes() { # JETON_AGENT EMAIL COMMUNE_ID LIBELLE
  local tok="$1" email="$2" commune="$3" libelle="$4"
  local actuelles
  actuelles="$(api GET /agent/me '' "$tok" | jq -r '[.communes[]?.id] | sort | join(",")')"
  if [ "$actuelles" = "$commune" ]; then
    return 0
  fi
  info "$libelle : rattachement à corriger (actuel : ${actuelles:-aucun})"
  local aid
  aid="$(api GET "/admin/agent?limit=100" '' "$ADMIN_TOKEN" \
    | jq -r --arg e "$email" '.items[]? | select(.email == $e) | .id' | head -1)"
  [ -n "$aid" ] || fail "$libelle introuvable dans /admin/agent"
  out="$(api PATCH "/admin/agent/$aid/communes" \
    "$(jq -n --arg c "$commune" '{communeIds:[$c]}')" "$ADMIN_TOKEN")"
  echo "$out" | est_erreur && fail "$libelle : réassignation refusée" \
    "$(echo "$out" | jq -c '{code,message}')"
  sleep "$PACE"
  # Relu APRÈS écriture : c'est l'état final qui compte, pas le code de sortie
  # de la requête qui prétend l'avoir posé.
  actuelles="$(api GET /agent/me '' "$tok" | jq -r '[.communes[]?.id] | sort | join(",")')"
  [ "$actuelles" = "$commune" ] || fail \
    "$libelle : rattachement toujours faux après réassignation" \
    "attendu $commune, obtenu ${actuelles:-aucun}"
}

assurer_communes "$AGENT_TOKEN" "$D_AGENT_EMAIL" "$COMMUNE_ID" "Agent A"
pass "Agent A connecté ($D_AGENT_EMAIL) — commune « $COMMUNE_NOM » (vérifiée)"

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
assurer_communes "$AGENT_B_TOKEN" "$D_AGENT_B_EMAIL" "$COMMUNE_B_ID" "Agent B"
pass "Agent B connecté ($D_AGENT_B_EMAIL) — commune « $COMMUNE_B_NOM » (vérifiée)"

# Les deux territoires sont maintenant d'un seul élément chacun, et distincts
# par construction (`COMMUNE_ID` ≠ `COMMUNE_B_ID`, garanti à l'étape 2). La
# disjonction sur laquelle reposent `test-appartenance` et
# `test-admin-dashboard` n'est donc plus une supposition.
[ "$COMMUNE_ID" != "$COMMUNE_B_ID" ] || fail \
  "Les deux communes du décor sont identiques — la disjonction est perdue"

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
#
# ⚠️ **Une promo PUBLIÉE, pas la première venue** (2026-08-05). On lisait
# `items[0]` de `/promo/me/all`, qui rend TOUS les statuts, les plus récentes
# d'abord — donc le brouillon ou l'arrêtée que le banc de plafond vient de
# laisser derrière lui. Le décor annonçait alors une promo au banc
# d'appartenance, qui a besoin d'une ressource RÉELLEMENT visible : ciblée sur
# un brouillon, ce banc conclurait « introuvable » pour la mauvaise raison.
#
# `dateFin` est vérifiée aussi : le cron d'expiration ne passe qu'à 1h,
# « publiee » ne suffit pas à dire « en ligne » (même distinction que
# `PromoService.isEnLigne`).
#
# ⚠️ Cette correction n'est PAS celle qui débloquait l'échec observé le
# 2026-08-05 — l'échec venait de `X-Device-Id` manquant dans `api()` (voir
# plus haut), qui faisait lire un objet d'erreur au lieu d'un statut. Les deux
# défauts étaient réels et indépendants ; les confondre aurait laissé celui-ci
# en place, invisible jusqu'au jour où le décor tomberait sur un brouillon.
PROMO_ID="$(api GET "/promo/me/all?limit=100" '' "$COMMERCANT_TOKEN" \
  | jq -r --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '[.items[]? | select(.lifecycleStatus == "publiee" and .dateFin > $now)][0].id // empty')"

# ⚠️ **Publier un brouillon existant AVANT d'en créer un** (2026-08-05).
# Le plafond anti-abus est de 5 créations par 24 h et par commerçant : après un
# passage du banc de plafond, le décor ne pouvait plus rien créer pendant une
# journée entière et échouait en `PROMO_DAILY_CREATION_CAP_REACHED` — un décor
# qui ne se repose que sur la création n'est rejouable qu'une fois par jour.
#
# `publish` ne consomme PAS ce plafond (voir `PromoService.publish` : ni
# `assertUnderDailyCreationCap`, ni cooldown pour une promo jamais publiée) —
# et un brouillon traîne précisément là où le banc de plafond en laisse.
if [ -z "$PROMO_ID" ]; then
  BROUILLON_ID="$(api GET "/promo/me/all?limit=100" '' "$COMMERCANT_TOKEN" \
    | jq -r '[.items[]? | select(.lifecycleStatus == "brouillon")][0].id // empty')"
  if [ -n "$BROUILLON_ID" ]; then
    info "Aucune promo visible — publication d'un brouillon existant"
    pub="$(api POST "/promo/$BROUILLON_ID/publish" '{}' "$COMMERCANT_TOKEN")"
    if echo "$pub" | est_erreur; then
      fail "Publication du brouillon du décor refusée" \
        "$(echo "$pub" | jq -c '{code,message}')"
    fi
    PROMO_ID="$BROUILLON_ID"
  fi
fi

if [ -z "$PROMO_ID" ]; then
  info "Ni promo visible ni brouillon — création"
  # ⚠️ La durée est plafonnée côté serveur (PROMO_MAX_DURATION_DAYS, 7 jours par
  # défaut). On reste dessous — et on ne recopie pas le plafond : 5 jours vaut
  # pour toute valeur de configuration supérieure ou égale à 5.
  #
  # `dureeJours` et non `dateFin` (2026-08-05) : c'est la façon dont l'app
  # exprime désormais une durée, donc ce que le décor doit exercer. Envoyer une
  # date absolue faisait en outre comparer l'horloge de ce script à celle du
  # serveur, sans tolérance — un décalage de quelques secondes suffisait à se
  # voir refuser une durée pourtant légale.
  # ⚠️ La clé S3 doit APPARTENIR au commerçant (2026-08-05). Le décor posait
  # `promo-photos/decor/decor.jpg`, un préfixe qui n'appartient à personne :
  # `assertPhotoKeysOwned` le refuse désormais en `STORAGE_KEY_NOT_OWNED`.
  # Avant ce garde, n'importe quel compte pouvait rattacher à sa promo un
  # fichier envoyé par un autre — le décor exerçait donc, sans le savoir, la
  # faille elle-même.
  out="$(api POST /promo "$(jq -n --arg k "promo-photos/$CID/decor.jpg" \
    '{description:"Promo du décor", prixAvant:1000, prixApres:700,
      categorie:"alimentation", photoKeys:[$k], dureeJours:5}')" \
    "$COMMERCANT_TOKEN")"
  echo "$out" | est_erreur && fail "Création promo refusée" "$(echo "$out" | jq -c '{code,message}')"
  PROMO_ID="$(echo "$out" | jq -r '.id // empty')"
  [ -n "$PROMO_ID" ] || fail "Promo créée sans id" "$(echo "$out" | head -c 200)"
  # ⚠️ C'était le seul appel écrivant du script à ne pas passer par
  # `est_erreur` — un `|| true` posé 49 lignes après le commentaire qui
  # condamne ce geste. Le décor annonçait « ✅ Promo » sur une promo restée
  # en BROUILLON, et le banc suivant accusait autre chose (revue 2026-08-05).
  #
  # Le refus attendu est nommé, pas avalé : la création ci-dessus publie déjà
  # (pas de `asDraft`), donc republier rend `PROMO_ALREADY_PUBLISHED`. C'est
  # le seul refus acceptable ici — tout autre est une panne de décor.
  pub="$(api POST "/promo/$PROMO_ID/publish" '{}' "$COMMERCANT_TOKEN")"
  if echo "$pub" | est_erreur; then
    code_pub="$(echo "$pub" | jq -r '.code // empty')"
    [ "$code_pub" = "PROMO_ALREADY_PUBLISHED" ] || fail \
      "Publication de la promo du décor refusée" \
      "$(echo "$pub" | jq -c '{code,message}')"
  fi
fi
# L'état final est vérifié, pas déduit du code de sortie d'un appel : c'est
# « publiée » qui compte pour les bancs, pas « la requête n'a pas planté ».
etat_promo="$(api GET "/promo/$PROMO_ID" '' "$COMMERCANT_TOKEN" \
  | jq -r '.lifecycleStatus // empty')"
[ "$etat_promo" = "publiee" ] || fail \
  "Promo du décor non publiée" "lifecycleStatus=${etat_promo:-<absent>}"
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
