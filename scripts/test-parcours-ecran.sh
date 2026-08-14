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
# ── Les cinq parcours ────────────────────────────────────────────────────────
#
#   premier-lancement  splash → choix du rôle → localisation → carte, et ce
#                      qui en reste dans le magasin natif. Aucun décor : il ne
#                      touche pas au serveur. ⚠️ Pré-accorde la permission de
#                      localisation par `adb shell pm grant` — l'écran n'a plus
#                      qu'une issue, et elle passe par la boîte système.
#   plafond            le compteur d'emplacements affiche le plafond DU SERVEUR.
#   creation           publier une promo de bout en bout — formulaire, photo,
#                      upload, création, retour, compteur incrémenté.
#   admin              l'espace admin, atteint par SA porte : l'écran de
#                      connexion commerçant bascule en mode admin dès qu'on y
#                      saisit un e-mail. Ses cinq compteurs valent ceux du
#                      serveur.
#   agent              le même écran, avec le jeton de l'agent. ⚠️ « ses
#                      compteurs ne sont PAS ceux de l'admin » disait cette
#                      ligne — c'est faux depuis le 2026-08-13 : l'agent est
#                      global, les cinq compteurs sont identiques. Ce que le
#                      parcours éprouve n'a pas changé (l'écran affiche ce que
#                      le serveur sert POUR CE RÔLE, mesuré avec SON jeton) ;
#                      c'est la raison qui a changé, et une raison périmée fait
#                      conclure.
#   inscription        un commerçant s'inscrit DEPUIS L'APP : formulaire,
#                      photo du registre, conditions — puis le script vérifie
#                      que le compte existe et que son registre est en attente.
#   client             l'accueil et la fiche : une promo fabriquée pour ce
#                      passage est retrouvée par la recherche, ouverte, et son
#                      COMPTEUR DE VUES monte côté serveur.
#   agent-creation     l'agent crée un commerçant AVEC SA POSITION : le compte
#                      se connecte ensuite, et il porte bien son point.
#   carte              la carte affiche le commerce et sa meilleure remise.
#                      ⚠️ Pose des COORDONNÉES au commerçant : sans elles, la
#                      carte est vide — aucun commerçant de la base n'en avait.
#   signalement        un client signale une promo : elle SORT du public
#                      (404) et entre dans la file de modération. ⚠️ MODIFIE le
#                      décor — passe avant `moderation`, qui s'en nourrit.
#   moderation         masquer une promo signalée depuis la file admin, et
#                      vérifier qu'elle disparaît AUSSI de ce que le public
#                      reçoit. ⚠️ MODIFIE le décor — passe en dernier.
#
# ⚠️ **L'ordre n'est pas cosmétique.** `creation` publie une promo et change
# donc `enLigne` ; il passe en dernier, après `plafond` qui compare à la mesure
# d'avant. Les inverser ferait échouer `plafond` sur un chiffre périmé — et
# l'échec accuserait l'écran.
#
# ⚠️ **Un `flutter drive` par parcours, et c'est nécessaire**, pas une
# commodité : `splashShownThisLaunch` est une variable de PROCESSUS
# (`lib/app/launch_state.dart`). Deux parcours dans le même lancement d'app et
# le second ne reverrait jamais le splash.
#
# ── Prérequis ────────────────────────────────────────────────────────────────
#
#   · le backend tourne (voir docs/status_v0.1.md — § Environnement)
#   · un émulateur ou un appareil est branché (`flutter devices`)
#
# ── Usage ────────────────────────────────────────────────────────────────────
#
#   ./scripts/test-parcours-ecran.sh                    # les trois
#   ./scripts/test-parcours-ecran.sh creation           # un seul
#   API_URL=http://10.0.2.2:3000 ./scripts/test-parcours-ecran.sh
set -u

RACINE="$(cd "$(dirname "$0")/.." && pwd)"
API_URL="${API_URL:-http://localhost:3000}"
# ⚠️ Ce que l'APP appelle, vu depuis l'émulateur — pas la même chose que ce que
# ce script appelle depuis la machine. Même piège que S3_ENDPOINT (P9).
API_URL_APP="${API_URL_APP:-http://10.0.2.2:3000}"
DEVICE_ID="parcours-ecran-0001"

CHOIX="${1:-tous}"
case "$CHOIX" in
  tous|premier-lancement|plafond|creation|admin|agent|moderation|client|inscription|agent-creation|signalement|carte) ;;
  decor-promos|decor-retouche|ville) ;;
  *) echo "❌ Parcours inconnu : « $CHOIX »."
     echo "   Attendu : premier-lancement | plafond | creation | admin | agent"
     echo "             | moderation | client | inscription | agent-creation"
     echo "             | signalement | carte"
     echo "             (rien = tous)"
     exit 2 ;;
esac

# Chaque parcours a besoin d'un décor DIFFÉRENT, et le dire évite de poser un
# décor pour rien — ou pire, d'en poser un qui consomme une inscription sur un
# plafond de 5/min avant un parcours qui n'en avait pas besoin. (Les connexions,
# elles, sont à 50/min depuis le 2026-08-13 et ne serrent plus.)
BESOIN_COMMERCANT=non
# `inscription` a besoin du décor UNIQUEMENT pour mesurer le plafond auprès du
# serveur — le compte qu'il crée, lui, est neuf.
case "$CHOIX" in tous|plafond|creation|client|inscription|signalement|carte) BESOIN_COMMERCANT=oui ;; esac
# `decor-promos` n'est pas un parcours de vérification : c'est un PRODUCTEUR de
# décor qui emprunte le formulaire commerçant. Il apporte sa propre liste de
# comptes (`TEST_COMMERCANTS`) et n'a donc besoin d'aucun décor préalable.
BESOIN_PRO=non
case "$CHOIX" in tous|admin|agent|moderation|agent-creation) BESOIN_PRO=oui ;; esac

echo "════════════════════════════════════════════════════════════════"
echo "  Parcours écran ($CHOIX) — décor, mesure, puis flutter drive"
echo "════════════════════════════════════════════════════════════════"
echo

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
  echo "❌ python3 requis (lecture du JSON)."; exit 2; }
PY=$(command -v python3 || command -v python)

lire_champ() { # CHAMP — lit un champ de l'objet JSON reçu sur stdin
  "$PY" -c "import sys,json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
v = d.get('$1')
print('' if v is None else v)"
}

if [ "$BESOIN_COMMERCANT" = "oui" ]; then
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
connexion() { # → jeton du commerçant du décor, vide si refus
  curl -s -X POST "$API_URL/commercant/login" \
    -H 'Content-Type: application/json' -H "X-Device-Id: $DEVICE_ID" \
    -d "{\"telephone\":\"$TEL\",\"pin\":\"$PIN\"}" | lire_champ accessToken
}

JETON="$(connexion)"
if [ -z "$JETON" ]; then
  echo "❌ Connexion du commerçant du décor impossible."
  echo "   ⚠️ Un 429 se déguise en « identifiants incorrects » : le décor vient"
  echo "      de consommer plusieurs connexions sur un plafond de 50/min."
  exit 2
fi

lire_slots() { # → "enLigne plafond", vide si la réponse est illisible
  local reponse enligne plafond
  reponse="$(curl -s "$API_URL/promo/me/slots" \
    -H "Authorization: Bearer $JETON" -H "X-Device-Id: $DEVICE_ID")"
  plafond="$(echo "$reponse" | lire_champ plafond)"
  enligne="$(echo "$reponse" | lire_champ enLigne)"
  # ⚠️ Chaîne vide et non « 0 » quand le champ manque : une réponse illisible
  # doit s'arrêter là, pas produire un zéro qui ferait échouer le parcours en
  # accusant l'écran (règle #29).
  if [ -z "$plafond" ] || [ -z "$enligne" ]; then
    echo "ILLISIBLE $(echo "$reponse" | head -c 200)"
    return 1
  fi
  echo "$enligne $plafond"
}

MESURE="$(lire_slots)" || { echo "❌ /promo/me/slots — $MESURE"; exit 2; }
EN_LIGNE="${MESURE% *}"
PLAFOND="${MESURE#* }"
echo "✅ enLigne=$EN_LIGNE  plafond=$PLAFOND"

# ⚠️ Ce contrôle-ci n'est pas une précaution, c'est le seul moyen de ne pas
# accuser le mauvais coupable : au plafond, le bouton de création est
# DÉSACTIVÉ. Le parcours `creation` attendrait alors un formulaire qui ne
# s'ouvre pas, et son message parlerait du formulaire.
if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "creation" ]; then
  if [ "$EN_LIGNE" -ge "$PLAFOND" ]; then
    echo "❌ Le commerçant du décor est au plafond ($EN_LIGNE/$PLAFOND)."
    echo "   Le parcours « creation » n'a pas de place pour publier — il n'y a"
    echo "   rien à éprouver, et son échec parlerait du formulaire."
    exit 2
  fi
fi
fi  # BESOIN_COMMERCANT
if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "carte" ]; then
# ── 2 sexies. Le commerce que la carte devra montrer ───────────────────────
#
# ⚠️ **Les paramètres de la carte sont `north/south/east/west`**, pas
# `minLat/maxLat`. Une première mesure avec les mauvais noms a rendu « 0
# commerce » et m'a fait conclure que la carte était vide — elle porte huit
# commerces géolocalisés, posés par `seed-demo.sh`. Une requête fausse ne
# prouve rien, elle en a juste l'air (règle #38).
#
# ⚠️ **La remise du marqueur est calculée par l'APP** (`MapShop
# .bestDiscountPercent`), à partir des promos que le serveur envoie. Le script
# la recalcule donc de son côté : c'est le rôle d'un oracle de test, et c'est
# la seule façon de vérifier un affichage dérivé. Le jour où la formule change
# d'un côté seulement, ce parcours le dira.
echo
echo "── 2 sexies. Carte ──"
# ⚠️ Le cadre se dérive désormais des coordonnées DU COMMERÇANT, plus d'un
# barycentre de commune : `GET /promo/map/center` a été retirée le 2026-08-12
# avec la sélection de communes. C'est plus direct — on cadre sur le commerce
# qu'on va chercher, au lieu de cadrer sur la moyenne d'une commune en espérant
# qu'il s'y trouve.
CARTE_POS="$(curl -s "$API_URL/commercant/me"   -H "Authorization: Bearer $JETON" -H "X-Device-Id: $DEVICE_ID" | "$PY" -c "import sys,json
try:
    d = json.load(sys.stdin)
except Exception:
    print('ILLISIBLE reponse non JSON'); sys.exit(0)
if d.get('latitude') is None or d.get('longitude') is None:
    print('ILLISIBLE commercant sans position'); sys.exit(0)
print('%s %s' % (d['latitude'], d['longitude']))")"
case "$CARTE_POS" in ILLISIBLE*) echo "❌ position du commerçant — $CARTE_POS"; exit 2 ;; esac
CARTE_LAT="${CARTE_POS% *}"
CARTE_LNG="${CARTE_POS#* }"
CARTE_CID="$(curl -s "$API_URL/commercant/me"   -H "Authorization: Bearer $JETON" -H "X-Device-Id: $DEVICE_ID" | lire_champ id)"
[ -n "$CARTE_CID" ] || { echo "❌ carte — identifiant du commerçant du décor illisible"; exit 2; }
# La promo EN LIGNE de ce commerçant — c'est elle qui porte la remise affichée
# sur le marqueur, et c'est elle qu'on ajustera si sa valeur est déjà prise.
PROMO_CARTE_ID="$(curl -s "$API_URL/promo/me/all?limit=100"   -H "Authorization: Bearer $JETON" -H "X-Device-Id: $DEVICE_ID" | "$PY" -c "import sys,json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for p in d.get('items', []):
    if p.get('lifecycleStatus') == 'publiee':
        print(p['id']); break")"
[ -n "$PROMO_CARTE_ID" ] || { echo "❌ carte — aucune promo publiée chez le commerçant du décor"; exit 2; }

BBOX="$(CLAT="$CARTE_LAT" CLNG="$CARTE_LNG" "$PY" -c "import os
la = float(os.environ['CLAT']); ln = float(os.environ['CLNG'])
print('north=%s&south=%s&east=%s&west=%s' % (la + 0.2, la - 0.2, ln + 0.2, ln - 0.2))")"

# On choisit un commerce dont la remise est UNIQUE dans la zone : le marqueur
# n'affiche que « −XX% », donc deux commerces à la même remise rendraient la
# désignation ambiguë — et le parcours taperait sur l'un ou l'autre en silence.
# ⚠️ **La cible est NOTRE commerce, pas « celui qui a la meilleure remise ».**
# La version d'origine prenait le commerce à la remise unique la plus élevée
# dans un cadre de ±0,2° — et supposait, sans le dire, que son marqueur pouvait
# apparaître SEUL. Deux prémisses fausses derrière cette supposition :
#
#   1. **des points confondus ne se séparent à aucun zoom.** La base portait
#      DIX « Commerce Décor » aux coordonnées identiques (décors empilés, voir
#      `provision-decor.sh`) : la grappe affichait « 10 », le parcours la tapait
#      six fois sans rien détacher, puis mourait sur une course
#      (`Bad state: No element`, 2026-08-13). Le produit n'avait rien ;
#   2. **on ne contrôle pas le commerce qu'on n'a pas posé.** Viser celui du
#      décor, dont on connaît la position et les promos, rend l'échec lisible :
#      s'il n'apparaît pas, c'est la carte, pas le choix de la cible.
#
# Les deux prémisses sont désormais VÉRIFIÉES, et le script refuse plutôt que
# de choisir mal — un parcours qui échoue sur une cible inatteignable accuse le
# produit (règle 38).
CARTE_CHOIX="$(curl -s "$API_URL/promo/map?$BBOX" -H "X-Device-Id: $DEVICE_ID"   | CID="$CARTE_CID" "$PY" -c "import sys,json,os,collections
try:
    d = json.load(sys.stdin)
except Exception:
    print('ILLISIBLE reponse non JSON'); sys.exit(0)
items = d.get('items')
if items is None:
    print('ILLISIBLE champ items absent'); sys.exit(0)
def meilleure(promos):
    best = None
    for p in promos or []:
        av, ap = p.get('prixAvant'), p.get('prixApres')
        try:
            av = float(av); ap = float(ap)
        except (TypeError, ValueError):
            continue
        if av <= 0 or ap >= av:
            continue
        pct = int(round((av - ap) / av * 100))
        if best is None or pct > best:
            best = pct
    return best
cid = os.environ['CID']
notre = next((c for c in items if c.get('id') == cid), None)
if notre is None:
    print('ILLISIBLE le commerce du decor n est pas sur la carte'); sys.exit(0)
remise = meilleure(notre.get('promos'))
if remise is None:
    print('ILLISIBLE le commerce du decor n a aucune promo a remise'); sys.exit(0)
# Premisse 1 : personne d autre a ses coordonnees, sinon la grappe ne se scinde
# jamais et le marqueur individuel n existe a aucun zoom.
pos = (round(notre['latitude'], 6), round(notre['longitude'], 6))
empiles = [c.get('nom') for c in items
           if c.get('id') != cid
           and (round(c['latitude'], 6), round(c['longitude'], 6)) == pos]
if empiles:
    print('ILLISIBLE %d commerce(s) a la position exacte du decor (%s) : la '
          'grappe ne se scindera a aucun zoom' % (len(empiles), ', '.join(sorted(set(empiles)))))
    sys.exit(0)
# Premisse 2 : la remise doit etre unique dans la zone, sinon le marqueur
# « -XX% » designe plusieurs commerces et le parcours tape l un ou l autre en
# silence. On ne l ESPERE pas : on choisit une valeur libre et on l imposera a
# la promo du decor. Un parcours qui se contente d esperer refuse un jour sur
# deux pour une raison qui n a rien a voir avec ce qu il eprouve.
prises = {meilleure(c.get('promos')) for c in items if c.get('id') != cid}
libre = next((p for p in range(75, 14, -1) if p not in prises), None)
if libre is None:
    print('ILLISIBLE aucune remise libre entre 15%% et 75%% dans la zone')
    sys.exit(0)
print('%d|%d|%s' % (libre, remise, notre.get('nom')))")"
case "$CARTE_CHOIX" in
  ILLISIBLE*) echo "❌ carte — $CARTE_CHOIX"; exit 2 ;;
esac
CARTE_PCT="${CARTE_CHOIX%%|*}"
_reste="${CARTE_CHOIX#*|}"
CARTE_PCT_ACTUEL="${_reste%%|*}"
CARTE_NOM="${_reste#*|}"
CARTE_REMISE="−${CARTE_PCT}%"

# ⚠️ **On IMPOSE la remise, on ne la subit pas.** La promo du décor vaut
# 1000 → 700, soit −30 % — une valeur que plusieurs commerces du parc portent
# aussi. Le marqueur « −30 % » désignerait alors plusieurs points et le parcours
# taperait l'un ou l'autre en silence.
#
# `prixAvant` reste à 1000 pour que le calcul soit exact des deux côtés :
# l'app arrondit `(avant − après) / avant × 100`, et un prix rond rend un
# pourcentage entier sans ambiguïté d'arrondi.
if [ "$CARTE_PCT" != "$CARTE_PCT_ACTUEL" ]; then
  CARTE_APRES="$(awk -v p="$CARTE_PCT" 'BEGIN{printf "%d", 1000 - p*10}')"
  maj="$(curl -s -X PATCH "$API_URL/promo/$PROMO_CARTE_ID"     -H "Content-Type: application/json" -H "Authorization: Bearer $JETON"     -H "X-Device-Id: $DEVICE_ID"     -d "{\"prixAvant\":1000,\"prixApres\":$CARTE_APRES}")"
  if [ -z "$(echo "$maj" | lire_champ id)" ]; then
    echo "❌ carte — impossible d'imposer la remise $CARTE_REMISE : $maj"; exit 2
  fi
  echo "   remise du décor portée de −$CARTE_PCT_ACTUEL% à $CARTE_REMISE (valeur libre dans la zone)"
fi
echo "✅ « $CARTE_NOM » · marqueur attendu : $CARTE_REMISE (seul à sa position, remise unique)"
fi
if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "signalement" ]; then
# ── 2 quinquies. Une promo à signaler, et son état de départ ───────────────
echo
echo "── 2 quinquies. Signalement ──"
SIG_CID="$(curl -s "$API_URL/commercant/me"   -H "Authorization: Bearer $JETON" -H "X-Device-Id: $DEVICE_ID" | lire_champ id)"
[ -n "$SIG_CID" ] || { echo "❌ /commercant/me illisible."; exit 2; }

SIG_DESC="Parcours signalement $(date +%H%M%S)"
SIG_CREEE="$(curl -s -X POST "$API_URL/promo"   -H 'Content-Type: application/json' -H "X-Device-Id: $DEVICE_ID"   -H "Authorization: Bearer $JETON"   -d "{\"description\":\"$SIG_DESC\",\"prixAvant\":900,\"prixApres\":600,      \"categorie\":\"alimentation\",\"photoKeys\":[\"promo-photos/$SIG_CID/parcours.jpg\"],      \"dureeJours\":5}")"
SIG_PROMO="$(echo "$SIG_CREEE" | lire_champ id)"
if [ -z "$SIG_PROMO" ]; then
  echo "❌ création de la promo à signaler refusée : $(echo "$SIG_CREEE" | head -c 200)"
  echo "   ⚠️ PROMO_ACTIVE_CAP_REACHED / PROMO_DAILY_CAP_REACHED : reposer le décor."
  exit 2
fi

# ⚠️ **L'état de DÉPART se mesure, il ne se suppose pas** (règle #38) : si la
# promo n'était pas publique avant, l'assertion « elle devient 404 » ne
# prouverait rien. On exige donc 200 ici.
SIG_AVANT="$(curl -s -o /dev/null -w '%{http_code}' "$API_URL/promo/$SIG_PROMO"   -H "X-Device-Id: $DEVICE_ID")"
if [ "$SIG_AVANT" != "200" ]; then
  echo "❌ la promo à signaler n'est pas publique au départ (HTTP $SIG_AVANT) :"
  echo "   son passage en 404 ne prouverait rien."
  exit 2
fi

JETON_ADMIN_SIG="$(curl -s -X POST "$API_URL/admin/login"   -H 'Content-Type: application/json' -H "X-Device-Id: $DEVICE_ID"   -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}"   | lire_champ accessToken)"
[ -n "$JETON_ADMIN_SIG" ] || { echo "❌ connexion admin refusée (429 déguisé ?)"; exit 2; }
SIG_FILE_AVANT="$(curl -s "$API_URL/admin/moderation/queue"   -H "Authorization: Bearer $JETON_ADMIN_SIG" -H "X-Device-Id: $DEVICE_ID"   | lire_champ total)"
[ -n "$SIG_FILE_AVANT" ] || { echo "❌ file de modération illisible."; exit 2; }
echo "✅ « $SIG_DESC » publique (200) · file de modération : $SIG_FILE_AVANT"
fi
# ⚠️ **Le parcours « choisir sa commune » a été supprimé le 2026-08-12** avec
# l'écran qu'il pilotait : le client cherche désormais autour d'un point qu'il
# enregistre, et il n'y a plus de commune à choisir. Le laisser ici aurait fait
# échouer le lot entier sur un fichier absent — l'échec aurait été franc, mais
# il aurait accusé le lancement au lieu de dire que la cible n'existe plus.
if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "client" ]; then
# ── 2 ter. Une promo À NOUS, pour que la recherche désigne UNE promo ────────
#
# ⚠️ Chercher « Promo du décor » ramènerait autant de résultats qu'il y a eu de
# décors : l'assertion « exactement une carte » deviendrait fausse pour une
# raison sans rapport avec l'écran. On fabrique donc une description horodatée,
# unique par construction.
echo
echo "── 2 ter. Promo du parcours client ──"
PROMO_DESC="Parcours client $(date +%H%M%S)"
# ⚠️ La clé photo doit APPARTENIR au compte : le serveur rend
# STORAGE_KEY_NOT_OWNED sur une clé inventée, et c'est l'id du commerçant dans
# le chemin qui fait la preuve (`promo-photos/<id>/…`, comme le décor). D'où ce
# détour par /commercant/me plutôt qu'un chemin fabriqué.
CID="$(curl -s "$API_URL/commercant/me"   -H "Authorization: Bearer $JETON" -H "X-Device-Id: $DEVICE_ID" | lire_champ id)"
[ -n "$CID" ] || { echo "❌ /commercant/me illisible — impossible de composer une clé photo valide."; exit 2; }
# ⚠️ La commune du commerçant était lue ici, avec ce motif : « sans elle,
# l'accueil client n'affiche AUCUNE promo — il montre "Choisissez vos
# communes" ». Cet écran n'existe plus depuis le 2026-08-12, et la lecture
# elle-même sortait en `exit 2` sur un `communeId` illisible : elle aurait
# empêché deux parcours de partir, en accusant le serveur.
CREEE="$(curl -s -X POST "$API_URL/promo"   -H 'Content-Type: application/json' -H "X-Device-Id: $DEVICE_ID"   -H "Authorization: Bearer $JETON"   -d "{\"description\":\"$PROMO_DESC\",\"prixAvant\":1000,\"prixApres\":700,      \"categorie\":\"alimentation\",\"photoKeys\":[\"promo-photos/$CID/parcours.jpg\"],      \"dureeJours\":5}")"
PROMO_CLIENT="$(echo "$CREEE" | lire_champ id)"
if [ -z "$PROMO_CLIENT" ]; then
  echo "❌ création de la promo du parcours refusée : $(echo "$CREEE" | head -c 200)"
  echo "   ⚠️ Lire le code : PROMO_DAILY_CAP_REACHED = 5 créations/24 h (reposer"
  echo "      le décor) ; STORAGE_KEY_NOT_OWNED = la clé photo n'appartient pas"
  echo "      à ce compte."
  exit 2
fi

lire_vues() { # ID — lit viewCount de CETTE promo dans GET /promo/me/all
  "$PY" -c "import sys,json
try:
    d = json.load(sys.stdin)
except Exception:
    print('ILLISIBLE reponse non JSON'); sys.exit(0)
for p in (d.get('items') or []):
    if p.get('id') == '$1':
        v = p.get('viewCount')
        print('ILLISIBLE viewCount absent' if v is None else v); sys.exit(0)
print('ILLISIBLE promo introuvable')"
}

VUES_AVANT="$(curl -s "$API_URL/promo/me/all"   -H "Authorization: Bearer $JETON" -H "X-Device-Id: $DEVICE_ID"   | lire_vues "$PROMO_CLIENT")"
case "$VUES_AVANT" in
  ILLISIBLE*) echo "❌ vues illisibles — $VUES_AVANT"; exit 2 ;;
esac
echo "✅ « $PROMO_DESC » créée · vues avant : $VUES_AVANT"
fi

if [ "$BESOIN_PRO" = "oui" ]; then
# ── 2 bis. Comptes pro, et les compteurs servis À CHAQUE RÔLE ───────────────
#
# ⚠️ La mesure se fait avec le jeton DU RÔLE JOUÉ, pas avec celui de l'admin
# pour les deux. `GET /admin/dashboard` est ouvert aux rôles `admin` ET
# `agent` (`@Roles('admin','agent')`) et rend des compteurs de périmètre
# différent. Mesurer les deux avec le même jeton ferait passer au vert
# exactement le défaut qu'on cherche : un agent à qui l'on servirait les
# chiffres globaux.
echo
echo "── 2 bis. Espace pro ──"
for var in ADMIN_EMAIL ADMIN_PASSWORD AGENT_EMAIL AGENT_PASSWORD; do
  eval "valeur=\${$var:-}"
  [ -n "$valeur" ] && continue
  echo "❌ $var absent de l'environnement."
  echo "   Ces comptes viennent du décor : lancer ./scripts/provision-decor.sh"
  echo "   et coller son bloc export avant de relancer ici."
  exit 2
done

mesurer_pro() { # ROLE EMAIL MDP → "a,b,c,d,e" ; ILLISIBLE… sinon
  local role="$1" email="$2" mdp="$3" jeton reponse
  jeton="$(curl -s -X POST "$API_URL/$role/login"     -H 'Content-Type: application/json' -H "X-Device-Id: $DEVICE_ID"     -d "{\"email\":\"$email\",\"password\":\"$mdp\"}" | lire_champ accessToken)"
  if [ -z "$jeton" ]; then
    echo "ILLISIBLE connexion $role refusée (un 429 se déguise en identifiants incorrects)"
    return 1
  fi
  reponse="$(curl -s "$API_URL/admin/dashboard"     -H "Authorization: Bearer $jeton" -H "X-Device-Id: $DEVICE_ID")"
  local vals=""
  for champ in commercesActifs promosPubliees signalementsEnAttente                registresEnAttente profilsEnAttente; do
    local v; v="$(echo "$reponse" | lire_champ "$champ")"
    # ⚠️ Pas de zéro par défaut : un champ absent doit arrêter la mesure, pas
    # produire un chiffre que le parcours irait chercher à l'écran (règle #29).
    if [ -z "$v" ]; then
      echo "ILLISIBLE champ $champ absent de /admin/dashboard : $(echo "$reponse" | head -c 160)"
      return 1
    fi
    vals="${vals:+$vals,}$v"
  done
  echo "$vals"
}

if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "admin" ]; then
  STATS_ADMIN="$(mesurer_pro admin "$ADMIN_EMAIL" "$ADMIN_PASSWORD")" || {
    echo "❌ mesure admin — $STATS_ADMIN"; exit 2; }
  echo "✅ admin ($ADMIN_EMAIL) → $STATS_ADMIN"
fi
if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "agent" ]; then
  STATS_AGENT="$(mesurer_pro agent "$AGENT_EMAIL" "$AGENT_PASSWORD")" || {
    echo "❌ mesure agent — $STATS_AGENT"; exit 2; }
  echo "✅ agent ($AGENT_EMAIL) → $STATS_AGENT"
fi
if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "moderation" ]; then
  # ⚠️ **Ne PAS mesurer le total public ici.** La première version de cette
  # contre-mesure exigeait qu'il baisse de un après un masquage, et rendait ❌
  # sur un produit correct : `VISIBLE_MODERATION_STATUSES` ne contient que
  # NORMALE et VERIFIEE_OK, donc une promo SIGNALÉE est déjà hors du public
  # avant toute décision admin. Masquer ne retire rien de visible — ça rend le
  # retrait définitif. Une contre-mesure fondée sur une prémisse fausse accuse
  # le produit, et c'est le pire des faux négatifs parce qu'il est crédible.
  #
  # Ce qu'on mesure donc : la file, et **l'identité** de la promo visée. Le
  # parcours masque la PREMIÈRE tuile ; l'écran affiche la file dans l'ordre
  # que ce même endpoint rend.
  JETON_ADMIN="$(curl -s -X POST "$API_URL/admin/login"     -H 'Content-Type: application/json' -H "X-Device-Id: $DEVICE_ID"     -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}"     | lire_champ accessToken)"
  [ -n "$JETON_ADMIN" ] || { echo "❌ connexion admin refusée (429 déguisé ?)"; exit 2; }

  lire_file() { # → "total id-du-premier" ; ILLISIBLE… sinon
    "$PY" -c "import sys,json
try:
    d = json.load(sys.stdin)
except Exception:
    print('ILLISIBLE reponse non JSON'); sys.exit(0)
items = d.get('items')
total = d.get('total')
if total is None or items is None:
    print('ILLISIBLE champs total/items absents'); sys.exit(0)
print(total, items[0]['id'] if items else '-')"
  }

  FILE_AVANT="$(curl -s "$API_URL/admin/moderation/queue"     -H "Authorization: Bearer $JETON_ADMIN" -H "X-Device-Id: $DEVICE_ID"     | lire_file)"
  case "$FILE_AVANT" in
    ILLISIBLE*) echo "❌ file de modération — $FILE_AVANT"; exit 2 ;;
  esac
  QUEUE_AVANT="${FILE_AVANT% *}"
  PROMO_CIBLE="${FILE_AVANT#* }"
  if [ "$QUEUE_AVANT" -eq 0 ]; then
    echo "❌ La file de modération est vide : le parcours « moderation » n'a"
    echo "   rien à masquer. Reposer le décor, qui crée les signalements."
    exit 2
  fi
  echo "✅ file de modération : $QUEUE_AVANT   ·   promo visée : $PROMO_CIBLE"
fi
if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "agent-creation" ]; then
  # ⚠️ **`lire_zone` a été retirée le 2026-08-13** avec le territoire de
  # l'agent. Elle lisait la première commune de `GET /agent/me` pour servir son
  # nom au formulaire — choisir la première venue aurait fait refuser la
  # création par le serveur, et l'échec aurait accusé le formulaire. Il n'y a
  # plus de commune à choisir, donc plus de piège à désamorcer.
  JETON_AGENT="$(curl -s -X POST "$API_URL/agent/login"     -H 'Content-Type: application/json' -H "X-Device-Id: $DEVICE_ID"     -d "{\"email\":\"$AGENT_EMAIL\",\"password\":\"$AGENT_PASSWORD\"}"     | lire_champ accessToken)"
  [ -n "$JETON_AGENT" ] || { echo "❌ connexion agent refusée (429 déguisé ?)"; exit 2; }
fi
fi  # BESOIN_PRO

# ── 3. Les parcours ─────────────────────────────────────────────────────────
echo
cd "$RACINE/apps/mobile" || exit 2

# ⚠️ **L'appareil se choisit, il ne se devine pas.** Ce poste voit quatre
# cibles (émulateur, Windows, Chrome, Edge) : sans `-d`, `flutter drive` peut
# partir sur le bureau ou le navigateur, où l'app se lance et où le parcours
# échoue sur des écrans qui n'ont rien à voir. On prend l'unique appareil
# Android s'il n'y en a qu'un, et **on refuse** au lieu d'en élire un.
APPAREIL="${PARCOURS_DEVICE:-}"
if [ -z "$APPAREIL" ]; then
  CANDIDATS="$(flutter devices 2>/dev/null \
    | awk -F'•' '/android-/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')"
  NB="$(echo "$CANDIDATS" | grep -c '[^[:space:]]')"
  if [ "$NB" -eq 0 ]; then
    echo "❌ Aucun appareil Android vu par flutter. Démarrer l'émulateur, ou"
    echo "   PARCOURS_DEVICE=<id> $0"
    exit 2
  fi
  if [ "$NB" -gt 1 ]; then
    echo "❌ Plusieurs appareils Android — lequel ?"
    echo "$CANDIDATS" | sed 's/^/     /'
    echo "   PARCOURS_DEVICE=<id> $0"
    exit 2
  fi
  APPAREIL="$CANDIDATS"
fi
echo "   appareil : $APPAREIL"
echo

# ⚠️ **La permission de localisation doit être accordée PENDANT l'installation.**
#
# `flutter drive` réinstalle l'application à chaque parcours, ce qui efface les
# permissions accordées : elles sont attachées au paquet, pas à l'appareil. Et
# un parcours ne peut pas taper la boîte de dialogue système d'Android — elle
# n'appartient pas à l'application.
#
# Sans ce sas, le parcours « agent crée un commerçant » attend 45 s puis échoue
# sur « la position n'a pas été captée », alors que le produit va parfaitement
# bien : c'est la permission qui manque. Constaté le 2026-08-13, après que la
# position est devenue obligatoire sur cet écran.
#
# On boucle donc en tâche de fond, en accordant dès que le paquet apparaît. La
# boucle est bornée : un « jusqu'à ce que ça marche » sans borne survivrait au
# parcours lui-même.
# ⚠️ Et une position SIMULÉE, sans quoi le GPS de l'émulateur ne rend rien : la
# permission accordée ne suffit pas si l'appareil n'a aucune position à donner.
# Les coordonnées sont celles du décor — un point ailleurs ferait sortir le
# commerce créé du rayon des parcours client qui suivent.
# ⚠️ **Une seule passe ne suffit pas, et le `|| true` cachait le problème.**
# `emu geo fix` pousse UN relevé ; l'émulateur revient ensuite à sa position par
# défaut (37.421998, −122.084 — Mountain View). Selon le moment où l'app
# interroge le GPS, elle recevait donc la Californie.
#
# Mesuré le 2026-08-13, sonde posée dans `MapScreen` : la carte ouvrait sur le
# point enregistré à zoom 13 et rendait **22 commerces**, puis recentrait sur
# `gps = LatLng(37.421998, -122.084)` à zoom 15 et rendait **0**. Le parcours
# concluait « ni marqueur ni grappe » — la carte allait parfaitement bien, elle
# regardait la Californie.
#
# ⚠️ Et `adb emu geo fix` rend **OK** dans ce cas : la commande réussit, le
# relevé n'atteint simplement pas l'application. Un `|| true` par-dessus une
# commande qui réussit déjà ne protégeait de rien — il empêchait juste de
# remarquer que sa réussite ne voulait rien dire (règle 29).
#
# On réémet donc en tâche de fond pendant toute la course, et le PREMIER envoi
# est vérifié : s'il échoue, l'appareil ne sait pas simuler de position et tout
# parcours qui en dépend accuserait l'écran.
POSITION_PID=""
poser_position_simulee() {
  adb -s "$APPAREIL" emu geo fix 3.2630 34.6714 >/dev/null 2>&1 || {
    echo "❌ « adb emu geo fix » a échoué : l'appareil ne sait pas simuler de"
    echo "   position. Les parcours qui lisent le GPS accuseraient l'écran."
    exit 2
  }
  ( while :; do
      adb -s "$APPAREIL" emu geo fix 3.2630 34.6714 >/dev/null 2>&1
      sleep 2
    done ) &
  POSITION_PID=$!
}

arreter_position_simulee() {
  [ -n "$POSITION_PID" ] && kill "$POSITION_PID" 2>/dev/null
  POSITION_PID=""
}

# Le miroir de la fonction ci-dessus : on RETIRE la permission dès que le paquet
# est là. `flutter drive` réinstalle l'app à chaque parcours, donc la permission
# repart de zéro — mais Android peut la ré-accorder si elle était déjà donnée
# pour ce paquet, d'où une révocation active plutôt qu'une simple abstention.
refuser_localisation_en_fond() {
  (
    for _ in $(seq 1 90); do
      if adb -s "$APPAREIL" shell pm revoke com.echango.promo            android.permission.ACCESS_FINE_LOCATION >/dev/null 2>&1; then
        adb -s "$APPAREIL" shell pm revoke com.echango.promo           android.permission.ACCESS_COARSE_LOCATION >/dev/null 2>&1
        break
      fi
      sleep 2
    done
  ) &
}

PERMISSION_PID=""
accorder_localisation_en_fond() {
  (
    for _ in $(seq 1 90); do
      if adb -s "$APPAREIL" shell pm grant com.echango.promo            android.permission.ACCESS_FINE_LOCATION >/dev/null 2>&1; then
        adb -s "$APPAREIL" shell pm grant com.echango.promo           android.permission.ACCESS_COARSE_LOCATION >/dev/null 2>&1
        break
      fi
      sleep 2
    done
  ) &
}

jouer() { # FICHIER LIBELLE [defines…]
  local fichier="$1" libelle="$2"; shift 2
  echo "── $libelle ──"
  poser_position_simulee
  accorder_localisation_en_fond
  flutter drive \
    -d "$APPAREIL" \
    --driver=test_driver/integration_test.dart \
    --target="integration_test/$fichier" \
    --dart-define=API_BASE_URL="$API_URL_APP" \
    "$@"
}

ECHECS=""
RESUME=""
noter() { # LIBELLE CODE
  if [ "$2" -eq 0 ]; then
    RESUME="$RESUME
  ✅ $1"
  else
    RESUME="$RESUME
  ❌ $1 (code $2)"
    ECHECS="$ECHECS $1"
  fi
}

if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "premier-lancement" ]; then
  # ── La permission de localisation se DÉCIDE avant de jouer ────────────────
  #
  # ⚠️ **Sinon ce parcours ne peut plus aboutir.** Depuis la mise en conformité
  # 5.1.1(iv) du 2026-08-08, l'écran de localisation n'a plus qu'un bouton, et
  # il mène TOUJOURS à la boîte de dialogue du système — qu'`integration_test`
  # ne peut pas toucher. Le parcours resterait bloqué là, puis échouerait au
  # bout de trente secondes en accusant l'écran, sur un produit correct
  # (règle #38 : une contre-mesure fondée sur une prémisse fausse accuse le
  # produit).
  #
  # On accorde donc la permission *avant*, avec `pm grant` : `checkPermission`
  # rend alors `whileInUse`, aucune boîte ne s'ouvre, et le parcours vérifie ce
  # qu'il doit vérifier — que l'onboarding se traverse et se retient. Le chemin
  # « refusé » relève d'un essai manuel, comme la boîte système elle-même.
  #
  # ⚠️ **Et on REFUSE de jouer si l'octroi échoue**, plutôt que de tenter sa
  # chance : le paquet n'est installé qu'à partir du premier `flutter drive`,
  # donc l'échec est attendu sur un émulateur neuf. Le dire coûte un rejeu ;
  # se taire coûte un faux rouge qu'on ira chercher dans le code de l'écran.
  PAQUET_APP="com.echango.promo"
  if ! command -v adb >/dev/null 2>&1; then
    echo "❌ adb introuvable — impossible de pré-accorder la localisation."
    echo "   Sans elle, « premier lancement » se bloque sur la boîte système."
    exit 2
  fi
  if ! adb -s "$APPAREIL" shell pm grant "$PAQUET_APP" \
         android.permission.ACCESS_FINE_LOCATION >/dev/null 2>&1; then
    echo "❌ pm grant a échoué sur $PAQUET_APP — l'app n'est sans doute pas"
    echo "   encore installée sur $APPAREIL. L'installer une fois, puis rejouer :"
    echo "     (cd apps/mobile && flutter install -d $APPAREIL)"
    exit 2
  fi
  echo "   localisation pré-accordée à $PAQUET_APP"

  jouer parcours_premier_lancement_test.dart "premier lancement"
  noter "premier lancement" $?
  echo
fi

if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "plafond" ]; then
  # ⚠️ **On REMESURE juste avant de jouer.** La mesure prise en section 2 date
  # d'avant les préparations des autres parcours — or « client » et
  # « signalement » créent chacun une promo pour ce même commerçant. Le rejeu
  # d'ensemble du 2026-08-05 a échoué là-dessus : l'écran affichait « 3 / 5 » et
  # le parcours attendait « 1 / 5 », mesuré vingt minutes plus tôt. **Une mesure
  # prise avant d'autres gestes mesure un état qui n'existe plus.**
  MESURE="$(lire_slots)" || { echo "❌ /promo/me/slots — $MESURE"; exit 2; }
  EN_LIGNE="${MESURE% *}"
  PLAFOND="${MESURE#* }"
  echo "   (remesuré : enLigne=$EN_LIGNE plafond=$PLAFOND)"
  jouer parcours_plafond_commercant_test.dart "compteur d'emplacements" \
    --dart-define=TEST_COMMERCANT_TEL="$TEL" \
    --dart-define=TEST_COMMERCANT_PIN="$PIN" \
    --dart-define=TEST_PLAFOND="$PLAFOND" \
    --dart-define=TEST_EN_LIGNE="$EN_LIGNE"
  noter "compteur d'emplacements ($EN_LIGNE / $PLAFOND)" $?
  echo
fi

if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "creation" ]; then
  # ⚠️ Remesure ici, et pas en section 2 : les parcours précédents ont créé
  # des promos et des signalements. **Une mesure prise avant d'autres gestes
  # mesure un état qui n'existe plus** (règle #38).
  MESURE="$(lire_slots)" || { echo "❌ /promo/me/slots — $MESURE"; exit 2; }
  EN_LIGNE="${MESURE% *}"
  PLAFOND="${MESURE#* }"
  if [ "$EN_LIGNE" -ge "$PLAFOND" ]; then
    echo "❌ le commerçant est au plafond ($EN_LIGNE/$PLAFOND) : plus de place."
    exit 2
  fi
  echo "   (remesuré : enLigne=$EN_LIGNE plafond=$PLAFOND)"
  jouer parcours_creation_promo_test.dart "création d'une promo" \
    --dart-define=TEST_COMMERCANT_TEL="$TEL" \
    --dart-define=TEST_COMMERCANT_PIN="$PIN" \
    --dart-define=TEST_PLAFOND="$PLAFOND" \
    --dart-define=TEST_EN_LIGNE="$EN_LIGNE"
  CODE_CREATION=$?
  noter "création d'une promo" $CODE_CREATION

  # ── Contre-mesure côté serveur ────────────────────────────────────────────
  #
  # Le parcours a vu l'ÉCRAN afficher n+1. Reste à savoir si le serveur est
  # d'accord : un écran qui incrémente son compteur localement sans que la
  # promo existe donnerait exactement le même vert. Deux témoins qui ne
  # regardent pas par la même fenêtre.
  if [ "$CODE_CREATION" -eq 0 ]; then
    echo
    echo "── contre-mesure : ce que le serveur compte maintenant ──"
    APRES="$(lire_slots)"
    if [ -z "${APRES##ILLISIBLE*}" ]; then
      echo "⚠️  /promo/me/slots illisible après coup — la contre-mesure n'a PAS"
      echo "    eu lieu. Ce n'est pas un échec du parcours, c'est une absence"
      echo "    de vérification : $APRES"
      noter "contre-mesure serveur (non concluante)" 1
    else
      EN_LIGNE_APRES="${APRES% *}"
      ATTENDU=$((EN_LIGNE + 1))
      if [ "$EN_LIGNE_APRES" -eq "$ATTENDU" ]; then
        echo "✅ le serveur compte $EN_LIGNE_APRES promo(s) en ligne (avant : $EN_LIGNE)"
        noter "contre-mesure serveur" 0
      else
        echo "❌ l'écran affichait $ATTENDU, le serveur en compte $EN_LIGNE_APRES."
        echo "   L'écran et la base ne disent pas la même chose."
        noter "contre-mesure serveur" 1
      fi
    fi
  fi
  echo
fi

if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "admin" ]; then
  # ⚠️ Remesure ici, et pas en section 2 : les parcours précédents ont créé
  # des promos et des signalements. **Une mesure prise avant d'autres gestes
  # mesure un état qui n'existe plus** (règle #38).
  STATS_ADMIN="$(mesurer_pro admin "$ADMIN_EMAIL" "$ADMIN_PASSWORD")" || {
    echo "❌ mesure admin — $STATS_ADMIN"; exit 2; }
  echo "   (remesuré : $STATS_ADMIN)"
  jouer parcours_espace_pro_test.dart "espace pro — admin"     --dart-define=TEST_PRO_ROLE=admin     --dart-define=TEST_PRO_EMAIL="$ADMIN_EMAIL"     --dart-define=TEST_PRO_PASSWORD="$ADMIN_PASSWORD"     --dart-define=TEST_PRO_STATS="$STATS_ADMIN"
  noter "espace pro — admin ($STATS_ADMIN)" $?
  echo
fi

if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "agent" ]; then
  # ⚠️ Remesure ici, et pas en section 2 : les parcours précédents ont créé
  # des promos et des signalements. **Une mesure prise avant d'autres gestes
  # mesure un état qui n'existe plus** (règle #38).
  STATS_AGENT="$(mesurer_pro agent "$AGENT_EMAIL" "$AGENT_PASSWORD")" || {
    echo "❌ mesure agent — $STATS_AGENT"; exit 2; }
  echo "   (remesuré : $STATS_AGENT)"
  jouer parcours_espace_pro_test.dart "espace pro — agent"     --dart-define=TEST_PRO_ROLE=agent     --dart-define=TEST_PRO_EMAIL="$AGENT_EMAIL"     --dart-define=TEST_PRO_PASSWORD="$AGENT_PASSWORD"     --dart-define=TEST_PRO_STATS="$STATS_AGENT"
  noter "espace pro — agent ($STATS_AGENT)" $?
  echo
fi

if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "agent-creation" ]; then
  AGENT_TEL="+213557$(date +%H%M%S)"
  AGENT_PIN="135792"
  echo "── agent : commerçant à créer $AGENT_TEL ──"
  jouer parcours_agent_creation_commercant_test.dart "agent — créer un commerçant"     --dart-define=TEST_PRO_EMAIL="$AGENT_EMAIL"     --dart-define=TEST_PRO_PASSWORD="$AGENT_PASSWORD"     --dart-define=TEST_COMMERCANT_TEL="$AGENT_TEL"     --dart-define=TEST_COMMERCANT_PIN="$AGENT_PIN"
  CODE_AGENT=$?
  noter "agent — créer un commerçant ($AGENT_TEL)" $CODE_AGENT

  # ── Contre-mesure : le compte existe-t-il, et PORTE-T-IL SA POSITION ? ───
  #
  # ⚠️ **La seconde question a changé le 2026-08-13.** Elle était « est-il dans
  # la bonne commune ? » — la frontière de zone, dont l'absence avait produit
  # l'IDOR agent → promo (P5). Cette frontière est supprimée par décision
  # produit ; la contre-mesure aurait rendu ❌ sur un produit correct.
  #
  # Elle porte désormais sur la **position**, et ce n'est pas un pis-aller :
  # c'est ce qui décide qu'un commerce existe pour un client. Une fiche sans
  # point n'apparaît sur aucune carte, ne sort d'aucune liste au rayon et ne
  # peut rien publier — 40 des 44 fiches invisibles mesurées le 2026-08-12
  # venaient de cette route. Une ligne affichée dans une liste ne prouve ni que
  # le compte existe, ni qu'il est utilisable.
  if [ "$CODE_AGENT" -eq 0 ]; then
    echo
    echo "── contre-mesure : le commerçant créé, vu du serveur ──"
    JETON_CREE="$(curl -s -X POST "$API_URL/commercant/login"       -H 'Content-Type: application/json' -H "X-Device-Id: $DEVICE_ID"       -d "{\"telephone\":\"$AGENT_TEL\",\"pin\":\"$AGENT_PIN\"}"       | lire_champ accessToken)"
    if [ -z "$JETON_CREE" ]; then
      echo "❌ connexion impossible avec le compte censé venir d'être créé."
      echo "   ⚠️ Un 429 se déguise en « identifiants incorrects »."
      noter "contre-mesure agent" 1
    else
      MOI_CREE="$(curl -s "$API_URL/commercant/me"         -H "Authorization: Bearer $JETON_CREE" -H "X-Device-Id: $DEVICE_ID")"
      LAT_CREE="$(echo "$MOI_CREE" | lire_champ latitude)"
      LNG_CREE="$(echo "$MOI_CREE" | lire_champ longitude)"
      if [ -z "$LAT_CREE" ] || [ -z "$LNG_CREE" ]; then
        echo "❌ le commerçant créé n'a AUCUNE position (lat='$LAT_CREE',"
        echo "   lng='$LNG_CREE') : il n'apparaîtra sur aucune carte et ne"
        echo "   pourra rien publier. L'écran a laissé passer une fiche vide."
        noter "contre-mesure agent" 1
      else
        echo "✅ compte créé, connecté, et positionné ($LAT_CREE / $LNG_CREE)"
        noter "contre-mesure agent" 0
      fi
    fi
  fi
  echo
fi

if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "inscription" ]; then
  # Un numéro NEUF : l'inscription refuse un téléphone déjà pris, et c'est
  # justement ce qu'on ne veut pas éprouver ici.
  NOUVEAU_TEL="+213556$(date +%H%M%S)"
  NOUVEAU_PIN="246813"
  echo "── inscription : compte à créer $NOUVEAU_TEL ──"
  jouer parcours_inscription_commercant_test.dart "inscription commerçant"     --dart-define=TEST_COMMERCANT_TEL="$NOUVEAU_TEL"     --dart-define=TEST_COMMERCANT_PIN="$NOUVEAU_PIN"     --dart-define=TEST_PLAFOND="$PLAFOND"
  CODE_INSCRIPTION=$?
  noter "inscription commerçant ($NOUVEAU_TEL)" $CODE_INSCRIPTION

  # ── Contre-mesure : le compte existe-t-il, et son registre est-il parti ? ─
  #
  # Deux choses qu'un écran ne peut pas prouver seul. La seconde est la plus
  # intéressante : `registreStatus` ne vaut « en attente » que si l'upload de
  # la photo a abouti ET que la demande de vérification a suivi. Un écran qui
  # atterrirait sur le tableau de bord en ayant sauté ces deux appels
  # afficherait exactement la même chose.
  if [ "$CODE_INSCRIPTION" -eq 0 ]; then
    echo
    echo "── contre-mesure : le compte créé, vu du serveur ──"
    JETON_NEUF="$(curl -s -X POST "$API_URL/commercant/login"       -H 'Content-Type: application/json' -H "X-Device-Id: $DEVICE_ID"       -d "{\"telephone\":\"$NOUVEAU_TEL\",\"pin\":\"$NOUVEAU_PIN\"}"       | lire_champ accessToken)"
    if [ -z "$JETON_NEUF" ]; then
      echo "❌ connexion impossible avec le compte censé venir d'être créé."
      echo "   ⚠️ Un 429 se déguise en « identifiants incorrects ». Depuis le"
      echo "      2026-08-13 register (5/min) et login (50/min) ont des seaux"
      echo "      SÉPARÉS : si ça bloque ici, c'est l'inscription, pas le login."
      noter "contre-mesure inscription" 1
    else
      ETAT_REGISTRE="$(curl -s "$API_URL/commercant/me"         -H "Authorization: Bearer $JETON_NEUF" -H "X-Device-Id: $DEVICE_ID"         | lire_champ registreStatus)"
      if [ -z "$ETAT_REGISTRE" ]; then
        echo "⚠️  registreStatus illisible — la contre-mesure n'a PAS eu lieu."
        noter "contre-mesure inscription (non concluante)" 1
      elif [ "$ETAT_REGISTRE" = "aucun" ] || [ "$ETAT_REGISTRE" = "null" ]; then
        echo "❌ le compte existe mais son registre n'a jamais été soumis"
        echo "   (registreStatus = $ETAT_REGISTRE) : la photo n'est pas partie."
        noter "contre-mesure inscription" 1
      else
        echo "✅ compte créé, registreStatus = $ETAT_REGISTRE"
        noter "contre-mesure inscription" 0
      fi
    fi
  fi
  echo
fi

if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "client" ]; then
  jouer parcours_client_liste_fiche_test.dart "client — liste et fiche"     --dart-define=TEST_PROMO_DESC="$PROMO_DESC"
  CODE_CLIENT=$?
  noter "client — liste et fiche" $CODE_CLIENT

  # ── Contre-mesure : la fiche a-t-elle VRAIMENT appelé le serveur ? ────────
  #
  # Un écran qui rendrait la fiche à partir de la carte déjà chargée en liste
  # afficherait la même chose — et le commerçant ne verrait jamais ses vues
  # monter. Le compteur est par appareil unique : l'app repart d'un identifiant
  # neuf à chaque passage (les préférences sont effacées), le script mesure
  # depuis un autre, qui ne compte qu'une fois.
  if [ "$CODE_CLIENT" -eq 0 ]; then
    echo
    echo "── contre-mesure : le compteur de vues de la promo ──"
    VUES_APRES="$(curl -s "$API_URL/promo/me/all"       -H "Authorization: Bearer $JETON" -H "X-Device-Id: $DEVICE_ID"       | lire_vues "$PROMO_CLIENT")"
    case "$VUES_APRES" in
      ILLISIBLE*)
        echo "⚠️  vues illisibles après coup — la contre-mesure n'a PAS eu lieu."
        echo "    Ce n'est pas un échec du parcours, c'est une absence de"
        echo "    vérification : $VUES_APRES"
        noter "contre-mesure vues (non concluante)" 1 ;;
      *)
        if [ "$VUES_APRES" -gt "$VUES_AVANT" ]; then
          echo "✅ vues $VUES_AVANT → $VUES_APRES : la fiche a bien appelé le serveur"
          noter "contre-mesure vues" 0
        else
          echo "❌ vues toujours à $VUES_APRES : la fiche s'est affichée sans"
          echo "   demander la promo au serveur."
          noter "contre-mesure vues" 1
        fi ;;
    esac
  fi
  echo
fi

if [ "$CHOIX" = "decor-promos" ]; then
  [ -n "${TEST_COMMERCANTS:-}" ] || {
    echo "❌ TEST_COMMERCANTS absent — liste « tel:pin,tel:pin,… » attendue."
    exit 2; }
  # ⚠️ Sans GPS : ce producteur n'a que faire de la position du téléphone, et
  # un GPS actif ferait voyager la carte au démarrage pour rien.
  SANS_GPS=oui jouer parcours_promos_serie_test.dart "décor — promos en série"     --dart-define=TEST_COMMERCANTS="$TEST_COMMERCANTS"     --dart-define=TEST_PROMOS_A_CREER="${TEST_PROMOS_A_CREER:-5}"
  noter "décor — promos en série" $?
fi
if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "ville" ]; then
# ── 2 septies. La ville par défaut et le geste qui la fixe ─────────────────
#
# ⚠️ **Les deux noms viennent du SERVEUR**, jamais d'une constante écrite ici :
# le décor peut changer de libellé, et un parcours qui recopierait « Épicerie
# Hassi Bahbah » échouerait en accusant la liste. On demande donc à la carte un
# commerce de la ville visée, et un commerce d'ailleurs — hors du rayon.
echo
echo "── 2 septies. Ville par défaut ──"
VILLE_LAT="${VILLE_LAT:-35.0774}"
VILLE_LNG="${VILLE_LNG:-3.0281}"
AILLEURS_LAT="${AILLEURS_LAT:-36.7538}"
AILLEURS_LNG="${AILLEURS_LNG:-3.0588}"
nom_dans_zone() { # LAT LNG
  curl -s "$API_URL/promo/map?north=$(awk -v v=$1 'BEGIN{print v+0.03}')&south=$(awk -v v=$1 'BEGIN{print v-0.03}')&east=$(awk -v v=$2 'BEGIN{print v+0.03}')&west=$(awk -v v=$2 'BEGIN{print v-0.03}')"     -H "X-Device-Id: $DEVICE_ID" | "$PY" -c "import sys,json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for c in d.get('items', []):
    if (c.get('promos') or []) and c.get('nom'):
        print(c['nom']); break"
}
VILLE_COMMERCE="$(nom_dans_zone "$VILLE_LAT" "$VILLE_LNG")"
VILLE_AILLEURS="$(nom_dans_zone "$AILLEURS_LAT" "$AILLEURS_LNG")"
[ -n "$VILLE_COMMERCE" ] || { echo "❌ aucun commerce avec promo autour de $VILLE_LAT,$VILLE_LNG"; exit 2; }
[ -n "$VILLE_AILLEURS" ] || { echo "❌ aucun commerce avec promo autour de $AILLEURS_LAT,$AILLEURS_LNG"; exit 2; }
# ⚠️ Les deux villes doivent être hors du rayon l'une de l'autre, sinon
# l'assertion d'absence serait fausse par construction et le parcours accuserait
# la liste (règle 38).
[ "$VILLE_COMMERCE" != "$VILLE_AILLEURS" ] || { echo "❌ même commerce des deux côtés — les deux points ne sont pas assez éloignés"; exit 2; }
echo "✅ ici « $VILLE_COMMERCE » · ailleurs « $VILLE_AILLEURS »"

  SANS_GPS=oui jouer parcours_ville_par_defaut_test.dart "client — ville par défaut"     --dart-define=TEST_VILLE_COMMERCE="$VILLE_COMMERCE"     --dart-define=TEST_VILLE_COMMERCE_AILLEURS="$VILLE_AILLEURS"     --dart-define=TEST_VILLE_LAT="$VILLE_LAT"     --dart-define=TEST_VILLE_LNG="$VILLE_LNG"
  noter "client — ville par défaut" $?

  # ⚠️ Un `flutter drive` SÉPARÉ, et ce n'est pas du confort : les préférences
  # sont un singleton de processus, et l'état d'un test déteint sur le suivant.
  # Groupés, le changement de ville voyait l'app démarrer sans point posé.
  SANS_GPS=oui jouer parcours_ville_changement_test.dart "client — changer de ville"     --dart-define=TEST_VILLE_COMMERCE="$VILLE_COMMERCE"     --dart-define=TEST_VILLE_LAT="$VILLE_LAT"     --dart-define=TEST_VILLE_LNG="$VILLE_LNG"
  noter "client — changer de ville" $?
fi
if [ "$CHOIX" = "decor-retouche" ]; then
  [ -n "${TEST_COMMERCANTS:-}" ] || {
    echo "❌ TEST_COMMERCANTS absent — liste « tel:pin,tel:pin,… » attendue,"
    echo "   dans le MÊME ordre qu'à la création : l'ordre fixe l'échelle de prix."
    exit 2; }
  SANS_GPS=oui jouer parcours_promos_retouche_test.dart "décor — retouche des prix"     --dart-define=TEST_COMMERCANTS="$TEST_COMMERCANTS"
  noter "décor — retouche des prix" $?
fi
if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "carte" ]; then
  SANS_GPS=oui jouer parcours_carte_test.dart "client — la carte"     --dart-define=TEST_REMISE="$CARTE_REMISE"     --dart-define=TEST_COMMERCE_NOM="$CARTE_NOM"
  noter "client — la carte ($CARTE_REMISE)" $?
  echo
fi

if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "signalement" ]; then
  jouer parcours_signalement_test.dart "client — signaler une promo"     --dart-define=TEST_PROMO_DESC="$SIG_DESC"
  CODE_SIG=$?
  noter "client — signaler une promo" $CODE_SIG

  # ── Contre-mesure : le signalement de l'APP a-t-il compté ? ─────────────
  #
  # ⚠️ Un signalement ne masque rien : il en faut TROIS, d'appareils distincts
  # (MODERATION_THRESHOLD, specs §5.4). On en envoie donc deux de plus, depuis
  # deux appareils qui ne sont pas celui de l'app. Deux ne suffisent pas — si
  # la promo sort du public, c'est que celui de l'app a été compté.
  #
  # La première version exigeait la sortie du public après le seul signalement
  # de l'app : elle accusait le produit sur une règle qu'elle avait inventée
  # (règle #38).
  if [ "$CODE_SIG" -eq 0 ]; then
    echo
    echo "── contre-mesure : deux signalements de plus, puis le seuil ──"
    # ⚠️ **On LIT la réponse.** La première version envoyait vers /dev/null :
    # les deux compléments étaient refusés en 400 (motif inventé — les motifs
    # valides sont perime/arnaque/photo_trompeuse/autre) et la contre-mesure
    # concluait « le signalement de l'app n'a pas compté » sur un produit
    # correct. Une contre-mesure qui jette la réponse du serveur ne peut pas
    # savoir qu'elle a échoué (règle #29).
    COMPLEMENTS_OK=oui
    for appareil in complement-0001 complement-0002; do
      reponse="$(curl -s -w '
%{http_code}' -X POST "$API_URL/report"         -H 'Content-Type: application/json' -H "X-Device-Id: $appareil"         -d "{\"promoId\":\"$SIG_PROMO\",\"reason\":\"arnaque\"}")"
      code="${reponse##*$'
'}"
      case "$code" in
        2*) ;;
        *) echo "⚠️  signalement complémentaire refusé (HTTP $code) : $(echo "$reponse" | head -1 | head -c 160)"
           COMPLEMENTS_OK=non ;;
      esac
    done
    if [ "$COMPLEMENTS_OK" = "non" ]; then
      echo "    Le seuil de 3 ne peut pas être atteint : la contre-mesure n'a"
      echo "    PAS eu lieu. Ce n'est pas un échec du parcours."
      noter "contre-mesure signalement (non concluante)" 1
    else
    SIG_APRES="$(curl -s -o /dev/null -w '%{http_code}' "$API_URL/promo/$SIG_PROMO"       -H "X-Device-Id: $DEVICE_ID")"
    SIG_FILE_APRES="$(curl -s "$API_URL/admin/moderation/queue"       -H "Authorization: Bearer $JETON_ADMIN_SIG" -H "X-Device-Id: $DEVICE_ID"       | lire_champ total)"
    if [ "$SIG_APRES" = "200" ]; then
      echo "❌ la promo répond toujours 200 après TROIS signalements : celui de"
      echo "   l'app n'a pas été compté (les deux du script ne suffisent pas)."
      noter "contre-mesure signalement" 1
    elif [ -z "$SIG_FILE_APRES" ]; then
      echo "⚠️  file illisible après coup — contre-mesure incomplète."
      noter "contre-mesure signalement (non concluante)" 1
    elif [ "$SIG_FILE_APRES" -ne $((SIG_FILE_AVANT + 1)) ]; then
      echo "❌ la promo est sortie du public (HTTP $SIG_APRES) mais la file de"
      echo "   modération compte $SIG_FILE_APRES au lieu de $((SIG_FILE_AVANT + 1))."
      noter "contre-mesure signalement" 1
    else
      echo "✅ public 200 → $SIG_APRES · file $SIG_FILE_AVANT → $SIG_FILE_APRES"
      echo "   (2 signalements du script + 1 de l'app = seuil de 3 atteint)"
      noter "contre-mesure signalement" 0
    fi
    fi
  fi
  echo
fi

if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "moderation" ]; then
  # ⚠️ Remesure ici, et pas en section 2 : les parcours précédents ont créé
  # des promos et des signalements. **Une mesure prise avant d'autres gestes
  # mesure un état qui n'existe plus** (règle #38).
  FILE_AVANT="$(curl -s "$API_URL/admin/moderation/queue" \
    -H "Authorization: Bearer $JETON_ADMIN" -H "X-Device-Id: $DEVICE_ID" \
    | lire_file)"
  case "$FILE_AVANT" in
    ILLISIBLE*) echo "❌ file de modération — $FILE_AVANT"; exit 2 ;;
  esac
  QUEUE_AVANT="${FILE_AVANT% *}"
  PROMO_CIBLE="${FILE_AVANT#* }"
  if [ "$QUEUE_AVANT" -eq 0 ]; then
    echo "❌ file de modération vide : rien à masquer."
    exit 2
  fi
  echo "   (remesuré : file de $QUEUE_AVANT, promo visée $PROMO_CIBLE)"
  jouer parcours_admin_moderation_test.dart "modération admin"     --dart-define=TEST_PRO_EMAIL="$ADMIN_EMAIL"     --dart-define=TEST_PRO_PASSWORD="$ADMIN_PASSWORD"     --dart-define=TEST_QUEUE="$QUEUE_AVANT"
  CODE_MODERATION=$?
  noter "modération admin (file de $QUEUE_AVANT)" $CODE_MODERATION

  # ── Contre-mesure : le serveur a-t-il bougé, et sur LA BONNE promo ? ─────
  #
  # L'écran a montré une tuile de moins. Un écran qui retirerait la tuile sans
  # que le serveur bouge donnerait le même vert — et un écran qui masquerait la
  # mauvaise promo aussi. D'où les deux vérifications : le compte, et
  # l'identité.
  if [ "$CODE_MODERATION" -eq 0 ]; then
    echo
    echo "── contre-mesure : la file, côté serveur ──"
    FILE_APRES="$(curl -s "$API_URL/admin/moderation/queue"       -H "Authorization: Bearer $JETON_ADMIN" -H "X-Device-Id: $DEVICE_ID"       | lire_file)"
    case "$FILE_APRES" in
      ILLISIBLE*)
        echo "⚠️  file illisible après coup — la contre-mesure n'a PAS eu lieu."
        echo "    Ce n'est pas un échec du parcours, c'est une absence de"
        echo "    vérification : $FILE_APRES"
        noter "contre-mesure serveur (non concluante)" 1 ;;
      *)
        QUEUE_APRES="${FILE_APRES% *}"
        TETE_APRES="${FILE_APRES#* }"
        if [ "$QUEUE_APRES" -ne $((QUEUE_AVANT - 1)) ]; then
          echo "❌ la file du serveur compte $QUEUE_APRES, attendu $((QUEUE_AVANT - 1))."
          echo "   La tuile a disparu de l'écran sans que le serveur bouge."
          noter "contre-mesure serveur" 1
        elif [ "$TETE_APRES" = "$PROMO_CIBLE" ]; then
          echo "❌ la promo visée ($PROMO_CIBLE) est TOUJOURS en tête de file."
          echo "   Le compte a baissé, mais c'est une autre promo qui est sortie."
          noter "contre-mesure serveur" 1
        else
          echo "✅ file $QUEUE_AVANT → $QUEUE_APRES, et $PROMO_CIBLE en est sortie"
          noter "contre-mesure serveur" 0
        fi ;;
    esac
  fi
  echo
fi

# ⚠️ **Un résumé vide n'est pas un succès.** Le bloc du parcours carte s'est
# retrouvé, un temps, AVANT la définition de `jouer` : le script rendait
# « command not found », un résumé vide et un code 0. Aucun parcours joué doit
# se voir (règle #28 : un contrôle qui ne peut pas refuser ne contrôle rien).
if [ -z "$RESUME" ]; then
  echo "❌ Aucun parcours n'a été joué pour « $CHOIX »."
  echo "   Le script s'est terminé sans rien exécuter — ce n'est pas un succès."
  exit 2
fi

echo "════════════════════════════════════════════════════════════════"
echo "  Parcours écran — résultat$RESUME"
echo "════════════════════════════════════════════════════════════════"
if [ -n "$ECHECS" ]; then
  exit 1
fi
exit 0
