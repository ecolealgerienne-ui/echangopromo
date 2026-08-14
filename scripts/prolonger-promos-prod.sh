#!/usr/bin/env bash
#
# Remet en ligne les promos EXPIRÉES en état de modération NORMAL, avec une
# nouvelle échéance — outil de lancement, à lancer SUR LE VPS.
#
# ── Ce qu'il touche, et ce qu'il ne touche pas ──────────────────────────────
#
#   lifecycleStatus = 'expiree'   ET   moderationStatus = 'normale'
#
# **Les promos signalées ou masquées sont laissées telles quelles.** Les
# remettre en ligne reconduirait un contenu qu'un modérateur a écarté, ou qui
# attend son examen — c'est la seule chose que ce script ne fera jamais, quels
# que soient les arguments.
#
# Les promos ARRÊTÉES ne sont pas concernées non plus : un arrêt est un geste
# volontaire du commerçant (rupture de stock, le plus souvent). Le défaire à sa
# place remettrait en vitrine ce qu'il a retiré.
#
# ── ⚠️ Pourquoi la base et non l'API ────────────────────────────────────────
#
# **Aucune route ne prolonge une promo existante** : `update-promo.dto.ts` ne
# porte ni `dureeJours` ni `dateFin`. Les clés `PROMO_*_DURATION_DAYS` ne valent
# que pour les publications À VENIR.
#
# Le chemin API le plus proche serait `POST /promo/:id/publish` avec un jeton
# d'agent — qui recalcule bien la date de fin, et échappe au cooldown de 24 h.
# Il reste possible et respecte toutes les règles du produit ; il est écarté ici
# parce qu'il faut une requête par promo, avec la cadence des seaux de débit
# (20 écritures/min), soit plusieurs minutes pour quelques dizaines de promos.
#
# ── ⚠️ Ce que ce script contourne, et qu'il faut assumer ────────────────────
#
# Il écrit en base sans passer par `PromoService`. Deux conséquences :
#
#   1. **Le plafond de promos actives n'est pas appliqué par le produit.** Ce
#      script le calcule donc lui-même, commerçant par commerçant, en lisant
#      `commercant."promoActiveCap"` (null = plafond global). Sans ça, un
#      commerçant se retrouverait à douze promos en ligne pour un plafond de
#      cinq, et `GET /promo/me/slots` lui afficherait « 12 / 5 » sans qu'aucune
#      erreur n'ait été levée.
#   2. **Aucune entrée n'est écrite au journal d'audit.** Ce qui est fait ici ne
#      laisse pas de trace côté produit — d'où la sortie détaillée, à conserver.
#
# ── Usage (sur le VPS) ──────────────────────────────────────────────────────
#
#   cd /opt/echangopromo
#   ./scripts/prolonger-promos-prod.sh 30              # SIMULATION
#   ./scripts/prolonger-promos-prod.sh 30 --appliquer
#
# Le nombre est une durée À PARTIR DE MAINTENANT : toutes les promos remises en
# ligne reçoivent la même échéance. C'est ce qu'on veut pour un lancement, et
# c'est dit parce que « prolonger de 30 jours » pourrait se comprendre comme un
# ajout à la date existante — laquelle est de toute façon passée.
set -uo pipefail

JOURS="${1:-}"
APPLIQUER=0
[ "${2:-}" = "--appliquer" ] && APPLIQUER=1

case "$JOURS" in
  ''|*[!0-9]*)
    echo "❌ Usage : $0 <jours> [--appliquer]"
    echo "   Exemple : $0 30 --appliquer"
    exit 2 ;;
esac
if [ "$JOURS" -lt 1 ] || [ "$JOURS" -gt 365 ]; then
  # ⚠️ Une borne, parce que ce script n'en a aucune autre : `PROMO_MAX_DURATION
  # _DAYS` ne s'applique pas ici. 365 n'est pas une règle métier, c'est un
  # garde-fou contre la faute de frappe.
  echo "❌ <jours> doit être entre 1 et 365 (reçu : $JOURS)"
  exit 2
fi

COMPOSE="docker compose --env-file .env.production -f docker-compose.promo.yml"

# ⚠️ Le conteneur Postgres de la prod ne porte pas le nom du dev local : on le
# CHERCHE plutôt que de le supposer (même précaution que la procédure de
# sauvegarde de `docs/DEPLOIEMENT_VPS.md`).
PG=$($COMPOSE ps -q postgres_promo 2>/dev/null | head -1)
if [ -z "$PG" ]; then
  echo "❌ conteneur postgres_promo introuvable. Vérifier : $COMPOSE ps"
  exit 2
fi

# ⚠️ Le plafond global vient du `.env` qui tourne, jamais d'un 5 écrit ici : le
# lire ailleurs ferait diverger ce script du produit le jour où il change
# (règle 32). Absent, on retombe sur le défaut du service, et on le DIT.
CAP_GLOBAL=$(grep -E '^PROMO_ACTIVE_CAP=' .env.production 2>/dev/null | cut -d= -f2)
if [ -z "$CAP_GLOBAL" ]; then
  CAP_GLOBAL=5
  echo "⚠️  PROMO_ACTIVE_CAP absent de .env.production — repli sur 5,"
  echo "    la même valeur que le service applique par défaut."
fi

sql() { docker exec -i "$PG" psql -U echango -d echango_promo -At -c "$1"; }

CIBLE="\"lifecycleStatus\" = 'expiree' AND \"moderationStatus\" = 'normale'"

# Les candidates, classées par commerçant, avec la place réellement disponible
# sous SON plafond. Une seule requête : « pas au cas par cas » ne veut pas dire
# « sans tenir compte du plafond », ça veut dire que la machine s'en charge.
SELECTION="
WITH plafonds AS (
  SELECT c.id AS cid,
         COALESCE(c.\"promoActiveCap\", $CAP_GLOBAL) AS cap,
         count(p.id) FILTER (WHERE p.\"lifecycleStatus\" = 'publiee') AS actives
  FROM commercant c
  LEFT JOIN promo p ON p.\"commercantId\" = c.id
  GROUP BY c.id, c.\"promoActiveCap\"
),
candidates AS (
  SELECT p.id,
         p.\"commercantId\" AS cid,
         GREATEST(pl.cap - pl.actives, 0) AS place,
         row_number() OVER (PARTITION BY p.\"commercantId\"
                            ORDER BY p.\"dateFin\" DESC NULLS LAST) AS rang
  FROM promo p
  JOIN plafonds pl ON pl.cid = p.\"commercantId\"
  WHERE $CIBLE
)"

echo "══════════════════════════════════════════════════════════════════════"
if [ "$APPLIQUER" = "1" ]; then
  echo "  ÉCRITURE RÉELLE — remise en ligne, échéance à +$JOURS jour(s)"
else
  echo "  SIMULATION — rien ne sera écrit (ajouter --appliquer pour agir)"
fi
echo "  plafond global retenu : $CAP_GLOBAL"
echo "══════════════════════════════════════════════════════════════════════"

echo
echo "── ce qui sera remis en ligne ──"
sql "$SELECTION
     SELECT count(*) FILTER (WHERE rang <= place) AS remises,
            count(*) FILTER (WHERE rang > place)  AS sans_place,
            count(DISTINCT cid)                   AS commercants
     FROM candidates;" \
  | awk -F'|' '{printf "  remises en ligne : %s\n  laissées faute de place : %s\n  commerçants concernés : %s\n", $1, $2, $3}'

# ⚠️ Ce qui n'est PAS touché, affiché plutôt que tu : sinon « 0 promo remise »
# se lit comme une panne alors que tout est signalé, masqué ou arrêté.
echo
echo "── laissées de côté, volontairement ──"
sql "SELECT
       count(*) FILTER (WHERE \"lifecycleStatus\" = 'expiree'
                        AND \"moderationStatus\" <> 'normale'),
       count(*) FILTER (WHERE \"lifecycleStatus\" = 'arretee'),
       count(*) FILTER (WHERE \"lifecycleStatus\" = 'publiee')
     FROM promo;" \
  | awk -F'|' '{printf "  expirées mais signalées/masquées : %s\n  arrêtées (geste du commerçant) : %s\n  déjà en ligne : %s\n", $1, $2, $3}'

if [ "$APPLIQUER" != "1" ]; then
  echo
  echo "  Rien n'a été écrit. Relancer avec --appliquer pour agir."
  exit 0
fi

echo
echo "── écriture ──"
# ⚠️ `publishedAt` n'est PAS réécrit : le faire remonterait ces promos en tête
# du tri « plus récentes d'abord » chez tous les clients, alors qu'elles sont
# anciennes. On remet en ligne, on ne réécrit pas l'histoire.
sql "$SELECTION
     UPDATE promo
     SET \"lifecycleStatus\" = 'publiee',
         \"dateFin\" = now() + interval '$JOURS days'
     WHERE id IN (SELECT id FROM candidates WHERE rang <= place);" | tail -1

echo
echo "── état après ──"
sql "SELECT count(*) FILTER (WHERE \"lifecycleStatus\" = 'publiee'),
            count(*) FILTER (WHERE $CIBLE),
            min(\"dateFin\") FILTER (WHERE \"lifecycleStatus\" = 'publiee'),
            max(\"dateFin\") FILTER (WHERE \"lifecycleStatus\" = 'publiee')
     FROM promo;" \
  | awk -F'|' '{printf "  en ligne : %s\n  encore expirées (normales) : %s\n  échéances : %s → %s\n", $1, $2, $3, $4}'

echo
echo "⚠️  Aucune entrée d'audit n'a été écrite : ce script court-circuite le"
echo "    produit. Conserver cette sortie — c'est la seule trace de ce qui a"
echo "    été fait."
