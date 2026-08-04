#!/usr/bin/env bash
#
# Peuple la base locale d'un jeu de données réaliste — commerçants, promos,
# mises en avant, signalements.
#
# ── Ce script n'est ni un décor, ni un banc ─────────────────────────────────
#
# `provision-decor.sh` pose le strict minimum que les bancs exigent, et rien de
# plus. Celui-ci remplit l'application pour qu'on puisse la REGARDER : parcourir
# la liste client, voir la carte peuplée, ouvrir la file de modération.
#
# Les deux sont séparés parce qu'ils ont des durées de vie différentes : un banc
# doit pouvoir tourner sur un décor minimal et prévisible, sans être perturbé
# par vingt promos de démonstration.
#
# ── ⚠️ Pourquoi tout passe par l'AGENT ──────────────────────────────────────
#
# Trois plafonds rendraient l'inscription directe impraticable :
#   - connexion et inscription sont limitées à 5/min/IP ;
#   - un commerçant est limité à 5 créations de promo par 24 h ;
#   - un commerçant AUTO-INSCRIT ne peut publier qu'après validation de son
#     registre par un admin (deux gestes de plus par commerçant).
#
# Un commerçant créé par un agent est `confirme_agent` : il échappe à la garde
# du registre (`assertRegistreValidated`), et l'agent est un `trustedActor`
# exempté des plafonds anti-abus. Un seul jeu de connexions suffit donc.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh     # pose l'admin et l'agent
#   ./scripts/seed-demo.sh           # remplit
#
#   COMMERCES=8 PROMOS_PAR_COMMERCE=3 ./scripts/seed-demo.sh
#
# Idempotent : un commerçant dont le numéro existe déjà est ignoré.

set -uo pipefail

API_URL="${API_URL:-http://localhost:3000}"
COMMERCES="${COMMERCES:-8}"
PROMOS_PAR_COMMERCE="${PROMOS_PAR_COMMERCE:-3}"
PACE="${PACE_SECONDS:-0.3}"

ADMIN_EMAIL="${ADMIN_EMAIL:-decor-admin@echango.local}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-decor-admin-2026}"
AGENT_EMAIL="${AGENT_EMAIL:-decor-agent@echango.local}"
AGENT_PASSWORD="${AGENT_PASSWORD:-decor-agent-2026}"

command -v jq >/dev/null 2>&1 || { echo "❌ jq requis."; exit 2; }

pass() { echo "✅ $1"; }
info() { echo "   $1"; }
step() { echo; echo "── $1 ──"; }
fail() { echo "❌ $1" >&2; [ -n "${2:-}" ] && echo "   Réponse : $2" >&2; exit 2; }
est_erreur() { jq -e 'type == "object" and ((.statusCode | type) == "number")' >/dev/null 2>&1; }

api() { # METHODE CHEMIN [CORPS] [JETON] [ENTETE_SUP]
  local m="$1" p="$2" body="${3:-}" tok="${4:-}" sup="${5:-}"
  local args=(-sS -X "$m" "$API_URL$p" -H 'Content-Type: application/json')
  [ -n "$body" ] && args+=(-d "$body")
  [ -n "$tok" ] && args+=(-H "Authorization: Bearer $tok")
  [ -n "$sup" ] && args+=(-H "$sup")
  curl "${args[@]}"
}

# ── Le catalogue de démonstration ───────────────────────────────────────────
#
# Noms plausibles pour Djelfa, une catégorie chacun. L'ordre est stable : le
# commerce n°3 sera toujours le même, ce qui rend une capture d'écran
# comparable d'une exécution à l'autre.
NOMS=(
  "Alimentation El Baraka|alimentation|Rue des Frères Bouchama"
  "Rôtisserie Es-Salam|restauration|Avenue de l'ALN"
  "Boutique Nour Textile|vetements_textile|Rue Larbi Ben M'hidi"
  "Électro Djelfa|electromenager|Cité 5 Juillet"
  "Parfumerie El Yasmine|beaute_hygiene|Rue de Palestine"
  "Meubles Ouled Naïl|maison_ameublement|Route de Laghouat"
  "Supérette Ain Chouhada|alimentation|Centre-ville"
  "Café-Pâtisserie Zenith|restauration|Boulevard Emir Abdelkader"
  "Prêt-à-porter Amel|vetements_textile|Marché couvert"
  "Droguerie El Anwar|autre|Rue de l'Indépendance"
)

# Libellés de promo par catégorie — pour que la liste client ait l'air vraie.
libelle_promo() {
  case "$1" in
    alimentation)        echo "Huile 5L, sucre et semoule en lot" ;;
    restauration)        echo "Menu complet du midi, boisson incluse" ;;
    vetements_textile)   echo "Collection d'hiver, deuxième article offert" ;;
    electromenager)      echo "Réfrigérateur 300L, garantie 2 ans" ;;
    beaute_hygiene)      echo "Coffret soin visage et parfum" ;;
    maison_ameublement)  echo "Salon 3 places en tissu, livraison comprise" ;;
    *)                   echo "Déstockage sur une sélection d'articles" ;;
  esac
}

echo "════════════════════════════════════════════════════════════════"
echo "  Peuplement de démonstration — $API_URL"
echo "════════════════════════════════════════════════════════════════"

step "1. Sessions"
ADMIN_TOKEN="$(api POST /admin/login "$(jq -n --arg e "$ADMIN_EMAIL" --arg p "$ADMIN_PASSWORD" \
  '{email:$e, password:$p}')" | jq -r '.accessToken // empty')"
[ -n "$ADMIN_TOKEN" ] || fail "Connexion admin impossible" "lancer ./scripts/provision-decor.sh"
sleep 2
AGENT_TOKEN="$(api POST /agent/login "$(jq -n --arg e "$AGENT_EMAIL" --arg p "$AGENT_PASSWORD" \
  '{email:$e, password:$p}')" | jq -r '.accessToken // empty')"
[ -n "$AGENT_TOKEN" ] || fail "Connexion agent impossible" "plafond de 5/min ? réessayer dans une minute"
pass "Admin et agent connectés"

step "2. L'agent couvre plusieurs communes"
# Sans ça, tous les commerces tomberaient dans la même commune et la carte
# comme les filtres wilaya/commune n'auraient rien à montrer.
COMMUNES="$(api GET /commune | jq -c '[.items[] | {id, nom}]')"
NB_COMMUNES="$(echo "$COMMUNES" | jq 'length')"
[ "$NB_COMMUNES" -ge 3 ] || fail "Moins de 3 communes en base" "lancer npm run seed:communes"

AGENT_ID="$(api GET /admin/agent '' "$ADMIN_TOKEN" \
  | jq -r --arg e "$AGENT_EMAIL" '(.items // .)[] | select(.email==$e) | .id' | head -1)"
[ -n "$AGENT_ID" ] || fail "Agent introuvable côté admin"

CIBLES="$(echo "$COMMUNES" | jq -c '[.[0:4][].id]')"
out="$(api PATCH "/admin/agent/$AGENT_ID/communes" "$(jq -n --argjson c "$CIBLES" '{communeIds:$c}')" \
  "$ADMIN_TOKEN")"
echo "$out" | est_erreur && fail "Assignation des communes refusée" "$(echo "$out" | jq -c '{code,message}')"
pass "Agent rattaché à $(echo "$CIBLES" | jq 'length') communes"

step "3. Commerces"
CREES=0; EXISTANTS=0
IDS=()
for i in $(seq 0 $((COMMERCES - 1))); do
  [ "$i" -lt "${#NOMS[@]}" ] || break
  IFS='|' read -r nom cat adresse <<< "${NOMS[$i]}"
  tel="$(printf '+2135550002%02d' "$i")"
  cid_commune="$(echo "$CIBLES" | jq -r ".[$((i % 4))]")"
  # Position dispersée autour de Djelfa, pour que la carte ait du relief.
  lat="$(awk -v i="$i" 'BEGIN{printf "%.5f", 34.6714 + (i%4)*0.012 - 0.018}')"
  lng="$(awk -v i="$i" 'BEGIN{printf "%.5f", 3.2630 + (i%3)*0.015 - 0.015}')"

  out="$(api POST /agent/commercant "$(jq -n --arg t "$tel" --arg n "$nom" --arg a "$adresse" \
    --arg c "$cat" --arg u "$cid_commune" --argjson la "$lat" --argjson lo "$lng" \
    '{telephone:$t, nom:$n, pin:"246810", adresse:$a, categorie:$c, communeId:$u,
      latitude:$la, longitude:$lo}')" "$AGENT_TOKEN")"

  if echo "$out" | est_erreur; then
    code="$(echo "$out" | jq -r '.code')"
    if [ "$code" = "COMMERCANT_PHONE_TAKEN" ]; then
      EXISTANTS=$((EXISTANTS + 1))
    else
      fail "Création de « $nom » refusée" "$(echo "$out" | jq -c '{code,message}')"
    fi
  else
    CREES=$((CREES + 1))
  fi
  sleep "$PACE"
done

# On relit la liste : elle fait foi, qu'on vienne de créer ou non.
LISTE="$(api GET "/admin/commercant?limit=100" '' "$ADMIN_TOKEN")"
echo "$LISTE" | est_erreur && fail "Liste des commerçants refusée"
mapfile -t IDS < <(echo "$LISTE" | jq -r '.items[] | select(.telephone | startswith("+21355500020")) | .id')
pass "$CREES créé(s), $EXISTANTS déjà présent(s) — ${#IDS[@]} commerces de démonstration"

step "4. Promos"
FIN="$(date -u -d '+5 days' +%Y-%m-%dT%H:%M:%S.000Z)"
NB_PROMOS=0
PREMIERE_PROMO=""
for idx in "${!IDS[@]}"; do
  cid="${IDS[$idx]}"
  cat="$(echo "$LISTE" | jq -r --arg i "$cid" '.items[] | select(.id==$i) | .categorie')"
  base="$(libelle_promo "$cat")"
  for p in $(seq 1 "$PROMOS_PAR_COMMERCE"); do
    avant=$(( (RANDOM % 40 + 10) * 100 ))
    apres=$(( avant - (avant * (RANDOM % 30 + 15) / 100) ))
    out="$(api POST "/promo/agent/$cid" "$(jq -n --arg d "$base" --argjson a "$avant" \
      --argjson b "$apres" --arg c "$cat" --arg f "$FIN" \
      '{description:$d, prixAvant:$a, prixApres:$b, categorie:$c,
        photoKeys:["promo-photos/demo/photo.jpg"], dateFin:$f}')" "$AGENT_TOKEN")"
    if echo "$out" | est_erreur; then
      code="$(echo "$out" | jq -r '.code')"
      [ "$code" = "PROMO_ACTIVE_CAP_REACHED" ] && break   # plafond atteint : normal
      fail "Création de promo refusée" "$(echo "$out" | jq -c '{code,message}')"
    fi
    [ -z "$PREMIERE_PROMO" ] && PREMIERE_PROMO="$(echo "$out" | jq -r '.id')"
    NB_PROMOS=$((NB_PROMOS + 1))
    sleep "$PACE"
  done
done
pass "$NB_PROMOS promos publiées"

step "5. Bandeau « Top promos »"
DEJA="$(api GET /admin/highlight '' "$ADMIN_TOKEN" | jq -r '(.items // .) | length')"
if [ "${DEJA:-0}" -gt 0 ]; then
  info "$DEJA mise(s) en avant déjà présente(s) — inchangé"
else
  mapfile -t TOP < <(api GET "/promo?limit=3" | jq -r '.items[].id')
  for pid in "${TOP[@]}"; do
    out="$(api POST /admin/highlight "$(jq -n --arg p "$pid" '{promoId:$p}')" "$ADMIN_TOKEN")"
    echo "$out" | est_erreur && info "mise en avant refusée : $(echo "$out" | jq -r '.code')"
    sleep "$PACE"
  done
  pass "${#TOP[@]} mises en avant"
fi

step "6. Signalements — sous le seuil de masquage"
# ⚠️ Deux signalements seulement : le seuil de masquage est à 3. On peuple la
# file de modération SANS déclencher le masquage, pour que l'écran admin ait
# quelque chose à montrer et que la promo reste visible côté client.
if [ -n "$PREMIERE_PROMO" ]; then
  for d in 1 2; do
    out="$(api POST /report "$(jq -n --arg p "$PREMIERE_PROMO" '{promoId:$p, reason:"perime"}')" \
      '' "X-Device-Id: demo-appareil-$d")"
    echo "$out" | est_erreur && info "signalement $d : $(echo "$out" | jq -r '.code')"
    sleep 1
  done
  pass "2 signalements sur $PREMIERE_PROMO (seuil de masquage : 3)"
fi

echo
echo "════════════════════════════════════════════════════════════════"
api GET /admin/dashboard '' "$ADMIN_TOKEN" | jq -c '.' 2>/dev/null | head -c 400
echo
echo "════════════════════════════════════════════════════════════════"
