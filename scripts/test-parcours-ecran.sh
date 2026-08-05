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
#   premier-lancement  splash → choix du rôle → localisation → accueil, et ce
#                      qui en reste dans le magasin natif. Aucun décor : il ne
#                      touche pas au serveur.
#   plafond            le compteur d'emplacements affiche le plafond DU SERVEUR.
#   creation           publier une promo de bout en bout — formulaire, photo,
#                      upload, création, retour, compteur incrémenté.
#   admin              l'espace admin, atteint par SA porte : l'écran de
#                      connexion commerçant bascule en mode admin dès qu'on y
#                      saisit un e-mail. Ses cinq compteurs valent ceux du
#                      serveur.
#   agent              le même écran, avec le périmètre de l'agent — ses
#                      compteurs ne sont PAS ceux de l'admin.
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
  tous|premier-lancement|plafond|creation|admin|agent) ;;
  *) echo "❌ Parcours inconnu : « $CHOIX »."
     echo "   Attendu : premier-lancement | plafond | creation | admin | agent"
     echo "             (rien = tous)"
     exit 2 ;;
esac

# Chaque parcours a besoin d'un décor DIFFÉRENT, et le dire évite de poser un
# décor pour rien — ou pire, d'en poser un qui consomme des connexions sur un
# plafond de 5/min avant un parcours qui n'en avait pas besoin.
BESOIN_COMMERCANT=non
case "$CHOIX" in tous|plafond|creation) BESOIN_COMMERCANT=oui ;; esac
BESOIN_PRO=non
case "$CHOIX" in tous|admin|agent) BESOIN_PRO=oui ;; esac

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
  echo "      de consommer plusieurs connexions sur un plafond de 5/min."
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

jouer() { # FICHIER LIBELLE [defines…]
  local fichier="$1" libelle="$2"; shift 2
  echo "── $libelle ──"
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
  jouer parcours_premier_lancement_test.dart "premier lancement"
  noter "premier lancement" $?
  echo
fi

if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "plafond" ]; then
  jouer parcours_plafond_commercant_test.dart "compteur d'emplacements" \
    --dart-define=TEST_COMMERCANT_TEL="$TEL" \
    --dart-define=TEST_COMMERCANT_PIN="$PIN" \
    --dart-define=TEST_PLAFOND="$PLAFOND" \
    --dart-define=TEST_EN_LIGNE="$EN_LIGNE"
  noter "compteur d'emplacements ($EN_LIGNE / $PLAFOND)" $?
  echo
fi

if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "creation" ]; then
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
  jouer parcours_espace_pro_test.dart "espace pro — admin"     --dart-define=TEST_PRO_ROLE=admin     --dart-define=TEST_PRO_EMAIL="$ADMIN_EMAIL"     --dart-define=TEST_PRO_PASSWORD="$ADMIN_PASSWORD"     --dart-define=TEST_PRO_STATS="$STATS_ADMIN"
  noter "espace pro — admin ($STATS_ADMIN)" $?
  echo
fi

if [ "$CHOIX" = "tous" ] || [ "$CHOIX" = "agent" ]; then
  jouer parcours_espace_pro_test.dart "espace pro — agent"     --dart-define=TEST_PRO_ROLE=agent     --dart-define=TEST_PRO_EMAIL="$AGENT_EMAIL"     --dart-define=TEST_PRO_PASSWORD="$AGENT_PASSWORD"     --dart-define=TEST_PRO_STATS="$STATS_AGENT"
  noter "espace pro — agent ($STATS_AGENT)" $?
  echo
fi

echo "════════════════════════════════════════════════════════════════"
echo "  Parcours écran — résultat$RESUME"
echo "════════════════════════════════════════════════════════════════"
if [ -n "$ECHECS" ]; then
  exit 1
fi
exit 0
