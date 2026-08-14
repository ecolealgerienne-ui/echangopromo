#!/usr/bin/env bash
#
# Supprime définitivement des commerçants et TOUT ce qui pend au bout —
# outil de nettoyage, à lancer SUR LE VPS.
#
# ⚠️⚠️ **IRRÉVERSIBLE.** Contrairement au produit, ce script efface vraiment.
# Faites une sauvegarde avant (`docs/DEPLOIEMENT_VPS.md`, § Sauvegardes) : c'est
# la seule chose qui vous permettra de revenir en arrière.
#
# ── Ce que fait le PRODUIT, et pourquoi ce script fait autre chose ──────────
#
# `DELETE /commercant/me` ne supprime rien : `CommercantService.deleteAccount`
# pose `deletedAt`, incrémente `tokenVersion`, et passe les promos en
# `SUPPRIMEE`. C'est une suppression DOUCE, faite pour un client qui part —
# elle garde l'historique et n'a aucun effet de bord.
#
# ⚠️ Elle ne convient pas à un nettoyage : le numéro de téléphone reste occupé.
# `assertPhoneAvailable` filtre sur `deletedAt`, mais `login` **ne le fait pas**
# (défaut P10, rule 30 de CLAUDE.md) — un numéro recyclé enferme son repreneur
# dehors. Un décor de test qu'on « supprime » en douce continue donc de bloquer
# ses propres numéros.
#
# D'où l'effacement réel ici. Et d'où le fait qu'il n'existe aucune route pour
# le faire : ce n'est pas un geste de produit.
#
# ── Ce qui part avec un commerçant ──────────────────────────────────────────
#
#   promo                 CASCADE en base — automatique
#   report                référence promoId SANS clé étrangère → à la main
#   promo_view            idem
#   notification          idem (recipientId ET promoId)
#   commercant_view       idem
#
# ⚠️ **Les cinq dernières n'ont aucune contrainte** : sans ce script elles
# resteraient en base à pointer vers des lignes disparues. Personne ne le
# verrait — jusqu'au jour où un décompte de signalements ou de vues sortirait
# faux, sans qu'on sache pourquoi.
#
# ── Ce qui NE part pas, délibérément ────────────────────────────────────────
#
#   audit_log     l'historique de ce que les agents et admins ont FAIT. Le
#                 supprimer effacerait la trace des décisions, pas les données
#                 du commerçant. On ne réécrit pas le journal.
#   highlight     la clé étrangère est en SET NULL : une diapositive curée qui
#                 visait une promo supprimée survit avec `promoId` à NULL.
#                 Le script le SIGNALE — à l'admin de la retirer ou de la
#                 repointer, c'est une décision éditoriale.
#
# ── Usage (sur le VPS) ──────────────────────────────────────────────────────
#
#   cd /opt/echangopromo
#   ./scripts/supprimer-commercants-prod.sh --telephone +213555      # SIMULATION
#   ./scripts/supprimer-commercants-prod.sh --telephone +213555 --appliquer
#   ./scripts/supprimer-commercants-prod.sh --id <uuid> --appliquer
#   ./scripts/supprimer-commercants-prod.sh --tous --appliquer       # confirme
#
# ⚠️ **Aucune portée par défaut.** Il faut la dire. Un script destructeur dont
# on peut oublier le filtre est un script qui vide la base un jour de fatigue.
set -uo pipefail

PORTEE=""
LIBELLE=""
APPLIQUER=0
while [ $# -gt 0 ]; do
  case "$1" in
    --telephone) PORTEE="c.telephone LIKE '$(printf '%s' "$2" | sed "s/'/''/g")%'"
                 LIBELLE="téléphone commençant par « $2 »"; shift 2 ;;
    --id)        PORTEE="c.id = '$(printf '%s' "$2" | sed "s/'/''/g")'"
                 LIBELLE="commerçant $2"; shift 2 ;;
    --tous)      PORTEE="TRUE"; LIBELLE="TOUS les commerçants"; shift ;;
    --appliquer) APPLIQUER=1; shift ;;
    *) echo "❌ argument inconnu : $1"; exit 2 ;;
  esac
done

if [ -z "$PORTEE" ]; then
  echo "❌ Portée obligatoire — aucune valeur par défaut."
  echo "   --telephone <préfixe>   les numéros commençant par ce préfixe"
  echo "   --id <uuid>             un commerçant précis"
  echo "   --tous                  tous, sans exception (demande confirmation)"
  exit 2
fi

COMPOSE="docker compose --env-file .env.production -f docker-compose.promo.yml"
PG=$($COMPOSE ps -q postgres_promo 2>/dev/null | head -1)
if [ -z "$PG" ]; then
  echo "❌ conteneur postgres_promo introuvable. Vérifier : $COMPOSE ps"
  exit 2
fi

# ⚠️ Toute requête échoue BRUYAMMENT. Un script destructeur qui survit à sa
# propre erreur est le pire des outils : il continue à effacer sur une
# sélection qui n'a pas abouti.
sql() {
  local sortie
  if ! sortie=$(docker exec -i "$PG" psql -U echango -d echango_promo \
                  -v ON_ERROR_STOP=1 -At -c "$1" 2>&1); then
    echo "❌ requête refusée par PostgreSQL :" >&2
    echo "$sortie" | sed 's/^/   /' >&2
    exit 3
  fi
  printf '%s\n' "$sortie"
}

CIBLES="SELECT c.id FROM commercant c WHERE $PORTEE"

echo "══════════════════════════════════════════════════════════════════════"
if [ "$APPLIQUER" = "1" ]; then
  echo "  ⚠️  SUPPRESSION DÉFINITIVE — $LIBELLE"
else
  echo "  SIMULATION — rien ne sera supprimé ($LIBELLE)"
fi
echo "══════════════════════════════════════════════════════════════════════"

echo
echo "── ce qui serait supprimé ──"
sql "WITH cibles AS ($CIBLES)
     SELECT (SELECT count(*) FROM cibles),
            (SELECT count(*) FROM promo WHERE \"commercantId\" IN (SELECT id FROM cibles)),
            (SELECT count(*) FROM report WHERE \"promoId\" IN
                (SELECT id FROM promo WHERE \"commercantId\" IN (SELECT id FROM cibles))),
            (SELECT count(*) FROM promo_view WHERE \"promoId\" IN
                (SELECT id::text FROM promo WHERE \"commercantId\" IN (SELECT id FROM cibles))),
            (SELECT count(*) FROM commercant_view WHERE \"commercantId\" IN (SELECT id::text FROM cibles)),
            (SELECT count(*) FROM notification WHERE \"recipientId\" IN (SELECT id FROM cibles)
                OR \"promoId\" IN (SELECT id FROM promo WHERE \"commercantId\" IN (SELECT id FROM cibles)));" \
  | awk -F'|' '{printf "  commerçants     : %s\n  promos          : %s\n  signalements    : %s\n  vues de promo   : %s\n  vues de fiche   : %s\n  notifications   : %s\n", $1,$2,$3,$4,$5,$6}'

echo
echo "── conservé, délibérément ──"
sql "WITH cibles AS ($CIBLES)
     SELECT (SELECT count(*) FROM audit_log),
            (SELECT count(*) FROM highlight WHERE \"promoId\" IN
                (SELECT id FROM promo WHERE \"commercantId\" IN (SELECT id FROM cibles)));" \
  | awk -F'|' '{printf "  entrees de journal gardees : %s\n  diapositives curees qui perdront leur promo : %s\n", $1, $2}'

NB=$(sql "SELECT count(*) FROM ($CIBLES) t;")
if [ "$NB" = "0" ]; then
  echo
  echo "  Aucun commerçant ne correspond — rien à faire."
  exit 0
fi

if [ "$APPLIQUER" != "1" ]; then
  echo
  echo "  Rien n'a été supprimé. Relancer avec --appliquer pour agir."
  exit 0
fi

# ⚠️ Une confirmation tapée à la main pour la portée totale. Les deux autres
# portées sont nommées et bornées ; « tous » ne l'est pas, et une faute de
# frappe dans un préfixe de téléphone ne doit jamais pouvoir devenir « tout ».
if [ "$LIBELLE" = "TOUS les commerçants" ]; then
  echo
  echo "⚠️  Vous allez supprimer $NB commerçant(s) — LA TOTALITÉ."
  printf "    Taper exactement SUPPRIMER TOUT pour confirmer : "
  read -r reponse
  if [ "$reponse" != "SUPPRIMER TOUT" ]; then
    echo "    Annulé."
    exit 0
  fi
fi

echo
echo "── suppression ──"
# ⚠️ **Une seule transaction.** Une suppression à moitié faite laisserait des
# signalements pointant vers des promos disparues — précisément l'état que ce
# script existe pour éviter. Tout passe, ou rien ne passe.
#
# L'ordre suit les dépendances : ce qui n'a pas de clé étrangère d'abord, le
# commerçant en dernier (sa CASCADE emporte alors les promos).
# ⚠️ `promo_view."promoId"` et `commercant_view."commercantId"` sont en
# **character varying**, pas en uuid — les seules colonnes de référence de cette
# base à ne pas suivre le type de leur cible. Sans `::text`, PostgreSQL refuse
# la comparaison (« operator does not exist: character varying = uuid ») et la
# transaction entière est annulée. Trouvé en rejouant la suppression contre une
# vraie base : aucune relecture ne montrait ça.
if ! docker exec -i "$PG" psql -U echango -d echango_promo -v ON_ERROR_STOP=1 <<SQL
BEGIN;
CREATE TEMP TABLE cibles AS $CIBLES;
CREATE TEMP TABLE cibles_promos AS
  SELECT id FROM promo WHERE "commercantId" IN (SELECT id FROM cibles);

DELETE FROM report          WHERE "promoId"       IN (SELECT id FROM cibles_promos);
DELETE FROM promo_view      WHERE "promoId"       IN (SELECT id::text FROM cibles_promos);
DELETE FROM notification    WHERE "promoId"       IN (SELECT id FROM cibles_promos)
                               OR "recipientId"   IN (SELECT id FROM cibles);
DELETE FROM commercant_view WHERE "commercantId"  IN (SELECT id::text FROM cibles);
DELETE FROM commercant      WHERE id              IN (SELECT id FROM cibles);
COMMIT;
SQL
then
  echo "❌ suppression interrompue — la transaction est annulée, rien n'a changé." >&2
  exit 3
fi

echo
echo "── état après ──"
sql "SELECT (SELECT count(*) FROM commercant), (SELECT count(*) FROM promo),
            (SELECT count(*) FROM report), (SELECT count(*) FROM notification);" \
  | awk -F'|' '{printf "  commerçants restants : %s\n  promos restantes : %s\n  signalements : %s\n  notifications : %s\n", $1,$2,$3,$4}'

echo
echo "⚠️  Aucune entrée d'audit n'a été écrite : ce script court-circuite le"
echo "    produit. Conserver cette sortie — c'est la seule trace."
echo "⚠️  Vérifier les diapositives curées (\`/admin/highlight\`) : celles qui"
echo "    visaient une promo supprimée ont maintenant \`promoId\` à NULL."
