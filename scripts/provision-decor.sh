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
#   - **deux agents** (le second est le témoin de la portée globale) ;
#   - un **commerçant** actif, registre validé.
#
# ── ⚠️ Idempotent, et c'est une contrainte de plafond ───────────────────────
#
# Les identifiants sont **stables**, jamais aléatoires : on tente donc la
# connexion d'abord — si elle réussit, le compte existe et on ne consomme ni
# une inscription ni une création. Le motif date de l'époque où les connexions
# étaient plafonnées à 5/min/IP ; il reste juste pour `POST /commercant/register`,
# resté à 5 (`STRICT_THROTTLE`), et il évite de toute façon de dupliquer un
# compte à chaque rejeu.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh
#
# Il imprime en fin de course le bloc `export` à coller avant de lancer un banc.

set -uo pipefail

API_URL="${API_URL:-http://localhost:3000}"
# ⚠️ Valait 13 s tant que les connexions étaient à 5/min (« ~12 s entre deux »).
# Elles sont à 50/min depuis le 2026-08-13 (`AUTH_THROTTLE`) et ce décor en
# consomme six : la temporisation ne protège plus rien de ce côté. Elle reste,
# courte, parce que deux des huit pauses encadrent une inscription (seau strict,
# toujours 5/min) et une écriture (seau des écritures, 20/min).
PACE="${PACE_SECONDS:-2}"

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

# ⚠️ **`--fail`, et sur une route qui existe** (2026-08-13). Cette sonde visait
# `GET /commune` SANS `--fail` : `curl` sort en 0 sur un 404, donc elle restait
# verte alors même que la route venait de disparaître. Un `curl -o /dev/null`
# sans `--fail` dans un banc est un aveu — on a décidé de ne pas savoir
# (règle 29). `GET /promo/config` est épinglée comme route ouverte, donc stable.
curl -sS --fail -o /dev/null "$API_URL/promo/config" \
  || fail "Backend injoignable sur $API_URL"

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
# ⚠️ **L'étape « deux communes disjointes » a disparu le 2026-08-13** avec le
# découpage administratif. Elle posait la prémisse de `test-appartenance` :
# deux territoires sans intersection, pour qu'un refus mesuré soit un refus
# d'appartenance et pas autre chose.
#
# **Les DEUX agents restent, et c'est essentiel.** Ils ne servent plus à
# prouver un cloisonnement mais son contraire : que deux agents distincts
# voient exactement la même chose, égale à ce que voit l'admin. Avec un seul
# agent, « il voit tout » serait indiscernable de « il voit ce qu'il voyait » —
# la sonde ne pourrait pas refuser (règle 28). C'est le second agent qui fait
# la mesure, hier comme aujourd'hui.
# ─────────────────────────────────────────────────────────────────────────────
step "2. Deux agents, sans territoire"

agent_login() {
  api POST /agent/login "$(jq -n --arg e "$D_AGENT_EMAIL" --arg p "$D_AGENT_PASSWORD" \
    '{email:$e, password:$p}')" | jq -r '.accessToken // empty'
}

sleep "$PACE"
AGENT_TOKEN="$(agent_login)"
if [ -z "$AGENT_TOKEN" ]; then
  info "Absent — création via POST /admin/agent"
  out="$(api POST /admin/agent "$(jq -n --arg e "$D_AGENT_EMAIL" --arg p "$D_AGENT_PASSWORD" \
    '{email:$e, password:$p, nom:"Agent Décor"}')" \
    "$ADMIN_TOKEN")"
  echo "$out" | est_erreur && fail "Création agent refusée" "$(echo "$out" | jq -c '{code,message}')"
  sleep "$PACE"
  AGENT_TOKEN="$(agent_login)"
  [ -n "$AGENT_TOKEN" ] || fail "Connexion agent impossible après création"
fi
# ⚠️ **`assurer_communes` a été supprimée le 2026-08-13**, et il vaut la peine
# de dire ce qu'elle corrigeait — le défaut, lui, peut revenir sous une autre
# forme. Les communes n'étaient posées qu'à la CRÉATION de l'agent : sur un
# agent déjà existant, le décor se contentait de se connecter puis d'imprimer
# « commune « Ain Chouhada » ». Une affirmation, pas une mesure. Agent A avait
# ainsi accumulé QUATRE communes au fil des sessions, dont celle de l'agent B,
# et les deux territoires annoncés disjoints se chevauchaient — les sondes
# d'appartenance testaient alors un refus qui n'avait pas lieu d'être.
#
# **La leçon survit au chantier** : un décor qui affirme sans relire l'état
# fabrique exactement le genre de banc qui rassure. Toute propriété dont un
# banc dépend se lit après écriture, jamais depuis le code de sortie de la
# requête qui prétend l'avoir posée.
pass "Agent A connecté ($D_AGENT_EMAIL)"

# ── Agent B : le témoin de la portée globale ─────────────────────────────────
agent_b_login() {
  api POST /agent/login "$(jq -n --arg e "$D_AGENT_B_EMAIL" --arg p "$D_AGENT_B_PASSWORD" \
    '{email:$e, password:$p}')" | jq -r '.accessToken // empty'
}

sleep "$PACE"
AGENT_B_TOKEN="$(agent_b_login)"
if [ -z "$AGENT_B_TOKEN" ]; then
  info "Absent — création via POST /admin/agent"
  out="$(api POST /admin/agent "$(jq -n --arg e "$D_AGENT_B_EMAIL" --arg p "$D_AGENT_B_PASSWORD" \
    '{email:$e, password:$p, nom:"Agent Décor B"}')" \
    "$ADMIN_TOKEN")"
  echo "$out" | est_erreur && fail "Création agent B refusée" "$(echo "$out" | jq -c '{code,message}')"
  sleep "$PACE"
  AGENT_B_TOKEN="$(agent_b_login)"
  [ -n "$AGENT_B_TOKEN" ] || fail "Connexion agent B impossible après création"
fi
# ⚠️ **Ce n'est plus « l'intrus », c'est le témoin.** Il servait à prouver un
# refus ; il sert maintenant à prouver que les deux agents voient la même
# chose. La vérification de disjonction qui suivait ici n'a plus d'objet — il
# n'y a plus rien à disjoindre.
pass "Agent B connecté ($D_AGENT_B_EMAIL)"

# ─────────────────────────────────────────────────────────────────────────────
# ── Envoi d'une VRAIE photo ────────────────────────────────────────────────
#
# ⚠️ **Le décor annonçait des photos qui n'existaient pas.** Il fabriquait des
# clés (`promo-photos/<id>/decor.jpg`) que le serveur accepte — elles
# appartiennent bien au commerçant — mais auxquelles aucun objet ne
# correspondait dans MinIO. Chaque écran affichant une promo du décor recevait
# donc un 404 d'image, et les parcours joués sur l'appareil ont dû apprendre à
# ignorer ces erreurs pour ne pas échouer en accusant l'écran. **Une donnée de
# décor qui ment coûte toujours plus cher qu'elle ne fait gagner.**
#
# On envoie donc un vrai fichier — l'icône de l'app, un PNG 1024×1024 déjà
# versionné — et on utilise la clé RENDUE par le serveur.
FICHIER_PHOTO="${FICHIER_PHOTO:-$(cd "$(dirname "$0")/.." && pwd)/apps/mobile/assets/images/brand/icon-master-terracotta-1024.png}"

envoyer_photo() { # TOKEN PURPOSE → clé S3 rendue par le serveur, ou vide
  [ -f "$FICHIER_PHOTO" ] || return 1
  curl -s -X POST "$API_URL/storage/upload" \
    -H "Authorization: Bearer $1" -H "X-Device-Id: $D_DEVICE_ID" \
    -F "purpose=$2" -F "file=@$FICHIER_PHOTO" \
    | jq -r '.key // empty'
}

step "4. Commerçant actif, registre validé"

commercant_login() {
  api POST /commercant/login "$(jq -n --arg t "$D_COMMERCANT_TEL" --arg p "$D_COMMERCANT_PIN" \
    '{telephone:$t, pin:$p}')" | jq -r '.accessToken // empty'
}

sleep "$PACE"
COMMERCANT_TOKEN="$(commercant_login)"
if [ -z "$COMMERCANT_TOKEN" ]; then
  info "Absent — inscription (consomme 1 sur le plafond horaire)"
  # ⚠️ Les coordonnées ne sont PAS décoratives. Sans elles, ce commerçant
  # n'apparaît sur aucune carte, ne sort dans aucune liste au rayon, et
  # **ne peut plus rien publier** depuis le 2026-08-12 : le banc `client-carte`
  # mesurerait une carte vide et les autres se feraient refuser leurs promos.
  # Le décor prétend préparer le terrain de TOUS les bancs ; il lui manquait le
  # point que la moitié d'entre eux vont chercher.
  # (Constaté le 2026-08-05 : `seed-demo.sh` en posait, `provision-decor.sh`
  # non — d'où un décor sans point de repère.)
  out="$(api POST /commercant/register "$(jq -n --arg t "$D_COMMERCANT_TEL" \
    --arg p "$D_COMMERCANT_PIN" \
    '{telephone:$t, nom:"Commerce Décor", adresse:"Rue du Décor", categorie:"alimentation",
      pin:$p, acceptedTerms:true,
      latitude:34.6714, longitude:3.2630}')")"
  echo "$out" | est_erreur && fail "Inscription commerçant refusée" \
    "$(echo "$out" | jq -c '{code,message}')"
  sleep "$PACE"
  COMMERCANT_TOKEN="$(commercant_login)"
  [ -n "$COMMERCANT_TOKEN" ] || fail "Connexion commerçant impossible après inscription"
fi
pass "Commerçant connecté ($D_COMMERCANT_TEL)"

# ⚠️ **Réparer un compte de décor ANTÉRIEUR au correctif du 2026-08-05.**
# Ce script est idempotent *par la connexion* : si le compte existe déjà, il
# n'est jamais réinscrit — donc les coordonnées ajoutées à sa charge utile
# d'inscription ne s'appliquent jamais à lui. Un décor monté avant cette date
# reste sans position indéfiniment, et depuis le 2026-08-12 il ne peut plus
# publier : le décor échouait à l'étape 5 sur `COMMERCANT_POSITION_REQUIRED`,
# constaté ce jour-là.
#
# C'est exactement le cas pour lequel `PATCH /commercant/me/position` existe :
# elle pose le point SANS déclencher de revue de profil à la première pose, là
# où `PATCH /commercant/me` renverrait le compte attendre un admin — et le
# décor se saboterait lui-même, comme le 2026-08-05.
POSITION_ACTUELLE="$(api GET /commercant/me '' "$COMMERCANT_TOKEN" | jq -r '.latitude // empty')"
if [ -z "$POSITION_ACTUELLE" ]; then
  info "Commerçant sans position (compte antérieur) — pose via PATCH /commercant/me/position"
  out="$(api PATCH /commercant/me/position     '{"latitude":34.6714,"longitude":3.2630}' "$COMMERCANT_TOKEN")"
  echo "$out" | est_erreur && fail "Pose de la position refusée"     "$(echo "$out" | jq -c '{code,message}')"
  sleep "$PACE"
  pass "Position posée (34.6714, 3.2630)"
fi

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
  REGISTRE_KEY="$(envoyer_photo "$COMMERCANT_TOKEN" registre)"
  [ -n "$REGISTRE_KEY" ] || fail "Envoi de la photo du registre impossible" \
    "le décor refuse d'annoncer un registre dont le fichier n'existe pas"
  out="$(api POST /commercant/me/registre \
    "$(jq -n --arg k "$REGISTRE_KEY" '{registreKey:$k}')" "$COMMERCANT_TOKEN")"
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
# ⚠️ **Le filtre de MODÉRATION est aussi nécessaire que celui de cycle de vie**
# (2026-08-13). Cette requête ne sélectionnait que sur `lifecycleStatus ==
# "publiee"`, alors que la vérification d'état finale — et tous les bancs qui
# consomment `PROMO_ID` — exigent une promo **visible du client**. Or
# `VISIBLE_MODERATION_STATUSES` ne contient que `normale` et `verifiee_ok` :
# une promo **signalée** est publiée ET invisible.
#
# Le décor rechargeait donc la promo laissée signalée par le parcours de
# signalement, puis échouait sur « Promo du décor non publiée » — un diagnostic
# faux qui accuse la publication alors que le sujet est la modération. Deux
# passages complets ont été perdus dessus.
#
# C'est la règle #30 : le décor recopiait la moitié d'un invariant qui vit
# ailleurs. Il applique désormais les deux conditions que sa propre assertion
# réclame.
PROMO_ID="$(api GET "/promo/me/all?limit=100" '' "$COMMERCANT_TOKEN" \
  | jq -r --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '[.items[]? | select(.lifecycleStatus == "publiee" and .dateFin > $now
         and (.moderationStatus == "normale"
              or .moderationStatus == "verifiee_ok"))][0].id // empty')"

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
      code_pub="$(echo "$pub" | jq -r '.code // empty')"
      # ⚠️ **Le commentaire ci-dessus n'est vrai que d'un brouillon JAMAIS
      # publié** (2026-08-13). Un brouillon peut aussi être une promo arrêtée
      # puis remise en brouillon : elle porte alors un `publishedAt`, et le
      # cooldown de republication s'applique. Le décor échouait durement
      # dessus, en annonçant « publication refusée » là où il n'avait qu'à
      # créer une promo neuve — la voie de repli existait déjà, dix lignes
      # plus bas, et n'était simplement pas atteignable.
      #
      # Ce refus-ci, et lui seul, est une raison de passer à la création. Tout
      # autre reste une panne de décor : élargir ce filtre le rendrait aveugle.
      if [ "$code_pub" = "PROMO_REPUBLISH_TOO_SOON" ]; then
        # ⚠️ **Deuxième essai, par l'AGENT** (2026-08-13). Le repli « on créera »
        # ci-dessous suppose qu'une création reste possible — or les deux voies
        # se ferment ensemble : un brouillon en cooldown ET un plafond de
        # 5 créations/24 h atteint, et le décor n'a plus rien. C'est arrivé au
        # rejeu d'ensemble du 2026-08-13, et il faut alors attendre le
        # lendemain : un décor qui n'est rejouable qu'une fois par jour n'est
        # pas un décor.
        #
        # L'agent est exempté des deux limites (`trustedActor`), et c'est
        # cohérent avec le produit depuis ce même jour : un agent agit pour
        # n'importe quel commerçant. On republie donc le MÊME brouillon plutôt
        # que d'en créer un de plus — la voie du commerçant reste la voie
        # normale, celle-ci n'est qu'une issue de secours nommée.
        info "Brouillon en cooldown — republication par l'agent (exempté)"
        pub="$(api POST "/promo/$BROUILLON_ID/publish" '{}' "$AGENT_TOKEN")"
        if echo "$pub" | est_erreur; then
          info "L'agent non plus — on créera ($(echo "$pub" | jq -r '.code // "?"'))"
          BROUILLON_ID=""
        fi
      else
        fail "Publication du brouillon du décor refusée" \
          "$(echo "$pub" | jq -c '{code,message}')"
      fi
    fi
    [ -n "$BROUILLON_ID" ] && PROMO_ID="$BROUILLON_ID"
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
  PROMO_PHOTO_KEY="$(envoyer_photo "$COMMERCANT_TOKEN" promo)"
  [ -n "$PROMO_PHOTO_KEY" ] || fail "Envoi de la photo de promo impossible" \
    "le décor refuse d'annoncer une photo dont le fichier n'existe pas"
  corps_promo="$(jq -n --arg k "$PROMO_PHOTO_KEY" \
    '{description:"Promo du décor", prixAvant:1000, prixApres:700,
      categorie:"alimentation", photoKeys:[$k], dureeJours:5}')"
  out="$(api POST /promo "$corps_promo" "$COMMERCANT_TOKEN")"
  # ⚠️ **Le plafond de 5 créations/24 h ferme cette voie pour la journée**, et
  # c'est la dernière du commerçant. On repasse alors par l'agent, exempté
  # (`trustedActor`) — même issue de secours que pour la republication ci-dessus,
  # et pour la même raison : un décor qui n'est rejouable qu'une fois par jour
  # n'est pas un décor. Ce code d'erreur, et lui seul : élargir le filtre
  # rendrait le décor aveugle à une vraie panne de création.
  if [ "$(echo "$out" | jq -r '.code // empty')" = "PROMO_DAILY_CREATION_CAP_REACHED" ]; then
    info "Plafond quotidien du commerçant atteint — création par l'agent"
    # La clé S3 doit appartenir à l'ACTEUR : l'agent renvoie donc sa propre
    # photo. `createByAgent` passe `actorId: agent`, et `assertPhotoKeysOwned`
    # accepte alors une clé au préfixe de l'agent (voir le commentaire de
    # `PromoController.createByAgent`).
    PROMO_PHOTO_KEY="$(envoyer_photo "$AGENT_TOKEN" promo)"
    [ -n "$PROMO_PHOTO_KEY" ] || fail "Envoi de la photo de promo (agent) impossible"
    corps_promo="$(jq -n --arg k "$PROMO_PHOTO_KEY" \
      '{description:"Promo du décor", prixAvant:1000, prixApres:700,
        categorie:"alimentation", photoKeys:[$k], dureeJours:5}')"
    out="$(api POST "/promo/agent/$CID" "$corps_promo" "$AGENT_TOKEN")"
  fi
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
step "6. Le commerçant du décor est bien SUR la carte"
# ⚠️ Contrôle, pas commentaire. Le décor a longtemps posé un commerçant SANS
# coordonnées : tout passait au vert ici, et c'est le parcours « carte » qui
# s'arrêtait plus tard — loin de la cause. Le seul moyen de savoir que le point
# est posé, c'est de demander au serveur ce qu'il en fait, pas de vérifier
# qu'on l'a envoyé.
#
# ⚠️ Ce contrôle interrogeait `GET /promo/map/center`, retirée le 2026-08-12
# avec la sélection de communes. Le remplaçant est **plus fort, pas
# équivalent** : il demande la carte elle-même, dans un cadre serré autour du
# décor, et exige d'y trouver CE commerçant. L'ancien se contentait d'un
# barycentre de commune — il pouvait être non nul sans que celui-ci y soit.
bbox="north=34.72&south=34.62&east=3.32&west=3.21"
# ⚠️ `.id` et non `.commercant.id` : la projection de `/promo/map` est PLATE —
# le commerçant EST l'item, ses promos sont imbriquées dessous. Écrit à
# l'aveugle la première fois, ce contrôle a rendu ❌ sur un décor parfaitement
# posé (2026-08-12). Il a échoué franchement au lieu de rendre 0 en silence,
# ce qui est la seule raison pour laquelle on l'a vu.
sur_la_carte="$(api GET "/promo/map?$bbox" | jq -r --arg id "$CID"   '[.items[]? | select(.id == $id)] | length')"
[ "${sur_la_carte:-0}" -ge 1 ] || fail "Le commerçant du décor n'est pas sur la carte"   "pas de coordonnées, ou aucune promo visible — le parcours « carte » ne pourra pas partir"
pass "Commerçant présent dans le cadre du décor"

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

⚠️ Ce script vient de consommer six connexions sur un plafond de 50/min.
   La marge est confortable depuis le 2026-08-13 ; elle ne l'est plus si l'on
   enchaîne sur test-auth-login.sh, dont c'est l'objet même de vider le seau.
   Un 429 se déguise toujours en « identifiants incorrects ».
   (Pas d'accents graves dans ce bloc : le heredoc n'est pas quoté, ils
   seraient exécutés comme une commande — défaut introduit puis corrigé le
   2026-08-13, il affichait « command not found » au milieu du décor.)

EOF
