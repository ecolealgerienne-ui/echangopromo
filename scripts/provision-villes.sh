#!/usr/bin/env bash
#
# Décor à TROIS VILLES — Djelfa, Hassi Bahbah, Alger.
#
# ── Pourquoi trois villes ────────────────────────────────────────────────────
#
# Depuis la suppression du découpage administratif, le seul repère géographique
# du client est **son point**, et le rayon de recherche autour. Tout le parc de
# décor tenait jusqu'ici dans un rayon de quelques kilomètres autour de Djelfa :
# **aucun banc ne pouvait donc distinguer « la liste suit le point » de « la
# liste sert tout ce qui existe »**. Les deux rendent le même résultat quand il
# n'y a qu'une ville.
#
# Trois villes à des distances très différentes rendent la question falsifiable :
#
#   Djelfa        34.6714, 3.2630   référence
#   Hassi Bahbah  35.0774, 3.0281   ~50 km  — au-delà du rayon, mais atteignable
#                                             en faisant glisser la carte
#   Alger         36.7538, 3.0588   ~232 km — hors de portée de tout geste
#
# ── ⚠️ TROIS commerçants par ville, et ce n'est pas du remplissage ───────────
#
# Une ville à un seul commerce ne distingue pas « la liste montre les commerces
# proches » de « la liste montre LE commerce ». Il faut au moins deux voisins
# pour qu'un tri, un regroupement de carte ou un rayon aient un sens — et trois
# pour qu'une grappe puisse se scinder en autre chose qu'un point unique.
#
# Ils sont espacés de 600 à 900 m à l'intérieur de chaque ville : assez pour se
# séparer sur la carte à un zoom urbain, assez peu pour rester tous dans le
# rayon de recherche d'un client posé au centre. Des positions identiques
# formeraient une grappe que rien ne scinde — le défaut qui a rendu le parcours
# carte inexploitable pendant une journée.
#
# ⚠️ **Les distances comptent plus que les noms.** Hassi Bahbah est choisie
# parce qu'elle est assez loin pour sortir du rayon (5 km servis par
# `/promo/config`) et assez près pour qu'un client puisse l'atteindre en
# explorant. Alger est choisie parce qu'elle ne peut PAS être atteinte par
# accident : une promo d'Alger qui apparaît dans la liste d'un client de Djelfa
# est un défaut, jamais un hasard.
#
# ── Ce que ce script ne fait pas ─────────────────────────────────────────────
#
# Il ne teste rien. Il appelle `provision-decor.sh` trois fois — une par ville —
# avec un numéro et une position propres à chacune. Réécrire ici la création
# d'un commerçant complet (inscription, registre déposé, registre validé, promo
# publiée) ferait deux implémentations du même décor, dont une seule serait
# corrigée le jour où le produit changera (règle 30).
#
# ── Idempotent ───────────────────────────────────────────────────────────────
#
# Les numéros sont **stables et distincts par ville** : rejouer ne crée rien de
# neuf, il retrouve les trois comptes. C'est aussi ce qui garantit que les trois
# commerces ne s'empilent pas — voir l'en-tête de `provision-decor.sh`, où dix
# décors superposés au même point ont rendu le parcours carte inexploitable.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-villes.sh
#
# Il imprime le bloc `export` des trois villes, à coller avant un banc.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
API_URL="${API_URL:-http://localhost:3000}"
# Le même PIN que le décor pour les trois : ce décor n'éprouve pas
# l'authentification, il pose des lieux.
D_PIN="${D_COMMERCANT_PIN:-654321}"

# ── ⚠️ Deux phases, parce qu'aucune machine ne peut faire les deux ───────────
#
# Sur ce poste, `jq` et le backend vivent sous **WSL** ; `flutter` et
# l'émulateur vivent sous **Windows**. Poser un compte exige le premier, créer
# une promo par l'écran exige le second. Un script monolithique échouerait à la
# première ville sur l'une ou l'autre machine — et laisserait un décor à moitié
# posé, ce qui est pire qu'un décor absent.
#
#   ./scripts/provision-villes.sh comptes   # WSL : les trois comptes
#   ./scripts/provision-villes.sh promos    # Windows : les trois promos, à l'écran
#   ./scripts/provision-villes.sh           # les deux, si la machine a tout
#
# La phase `promos` n'invente rien : elle relit les comptes auprès du serveur.
PHASE="${1:-tout}"
case "$PHASE" in
  comptes|promos|tout) ;;
  *) echo "❌ Phase inconnue : « $PHASE ». Attendu : comptes | promos | (rien)"
     exit 2 ;;
esac

# ⚠️ Coordonnées **approximatives des centres-villes**, et c'est assumé : ce
# décor a besoin de trois lieux à des distances connues les unes des autres, pas
# d'un référentiel géographique. Les recopier depuis un cadastre ne rendrait pas
# les bancs plus justes — c'est l'écart entre elles qui est éprouvé.
# nom-court | téléphone | latitude | longitude | nom du commerce | adresse
#
# ⚠️ **Les numéros commencent par `+213555 9`, et ce n'est pas esthétique.**
# Plusieurs bancs fabriquent leurs numéros à partir de l'HEURE
# (`+213555HHMMSS` — `client_rayon.py`, `registre.py`) : tout numéro de la forme
# `+213555` suivi d'un horodatage plausible finit par entrer en collision, et
# l'inscription est alors refusée en `COMMERCANT_PHONE_TAKEN`. C'est arrivé au
# premier essai : `+213555000201` est 00:02:01.
#
# `9` en tête de la position des heures rend l'horodatage impossible — aucun
# banc ne peut produire « 90:02:01 ». Djelfa garde son numéro historique, déjà
# posé et lu par d'autres bancs.
#
# ⚠️ **Nom et adresse distincts par ville, et c'est nécessaire.** Depuis la
# suppression du découpage administratif, un commerçant se déclare par
# **nom + adresse en texte libre + position**. Trois commerces homonymes à la
# même adresse dans trois villes ne ressemblent à aucune déclaration réelle, et
# rendent inéprouvables deux choses : la recherche admin (qui porte sur
# nom/téléphone/**adresse** depuis le 2026-08-13) et toute assertion d'écran qui
# doit distinguer un commerce d'un autre.
VILLES="
djelfa|+213555000101|34.6714|3.2630|Commerce~Décor|Rue~du~Décor,~Djelfa
djelfa|+213555900102|34.6772|3.2688|Boulangerie~El~Amir|Avenue~de~l'Indépendance,~Djelfa
djelfa|+213555900103|34.6661|3.2561|Boucherie~Es-Salam|Rue~des~Frères~Bouadjadj,~Djelfa
hassi-bahbah|+213555900201|35.0774|3.0281|Épicerie~Hassi~Bahbah|Route~de~Djelfa,~Hassi~Bahbah
hassi-bahbah|+213555900202|35.0831|3.0339|Café~Ennour|Place~du~Marché,~Hassi~Bahbah
hassi-bahbah|+213555900203|35.0718|3.0214|Quincaillerie~El~Fath|Rue~de~la~Gare,~Hassi~Bahbah
alger|+213555900301|36.7538|3.0588|Supérette~Alger~Centre|Rue~Didouche~Mourad,~Alger
alger|+213555900302|36.7601|3.0644|Librairie~du~Port|Boulevard~Zighoud~Youcef,~Alger
alger|+213555900303|36.7472|3.0521|Pâtisserie~La~Casbah|Rue~Ahmed~Bouzrina,~Alger
"

# ⚠️ `python3` n'existe PAS dans Git Bash sous Windows — seulement `python`.
# Ce script vit à cheval sur les deux machines (comptes sous WSL, promos sous
# Windows), donc il doit trouver l'un ou l'autre. Codé en dur, il rendait
# « identifiant du commerçant illisible » : un diagnostic qui accuse le serveur
# alors que c'est l'interpréteur qui manque. `test-parcours-ecran.sh` faisait
# déjà ce choix ; ne pas le reprendre était l'erreur.
command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
  echo "❌ python3 ou python requis (lecture du JSON)."; exit 2; }
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

echo "════════════════════════════════════════════════════════════════"
echo "  Décor à trois villes — $API_URL"
echo "════════════════════════════════════════════════════════════════"

RESUME=""
VILLE_COURANTE=""
RANG=0
for ligne in $VILLES; do
  nom="${ligne%%|*}"; reste="${ligne#*|}"
  # Le rang repart à 1 à chaque ville : `VILLE_DJELFA_1`, `_2`, `_3`.
  if [ "$nom" != "$VILLE_COURANTE" ]; then
    VILLE_COURANTE="$nom"
    RANG=0
  fi
  tel="${reste%%|*}"; reste="${reste#*|}"
  lat="${reste%%|*}"; reste="${reste#*|}"
  lng="${reste%%|*}"; reste="${reste#*|}"
  # ⚠️ `~` et non `·` : `tr` travaille sur des OCTETS, et `·` (U+00B7) en fait
  # deux en UTF-8 — il les remplaçait donc par DEUX espaces, et le décor posait
  # « Commerce  Décor ». Un séparateur ASCII n'a pas ce problème.
  #
  # Il en faut un parce qu'une boucle `for` se coupe sur les espaces ; bricoler
  # un `IFS` pour trois libellés coûterait plus cher à lire que cette
  # substitution, faite ici une fois.
  commerce="$(printf '%s' "${reste%%|*}" | tr '~' ' ')"
  adresse="$(printf '%s' "${reste#*|}" | tr '~' ' ')"

  echo
  echo "── $nom — « $commerce », $adresse ($lat, $lng) ──"
  if [ "$PHASE" != "promos" ]; then
    sortie="$(D_COMMERCANT_TEL="$tel" D_COMMERCANT_LAT="$lat" D_COMMERCANT_LNG="$lng" \
      D_COMMERCANT_NOM="$commerce" D_COMMERCANT_ADRESSE="$adresse" \
      D_SANS_PROMO=oui "$HERE/provision-decor.sh" 2>&1)"
    code=$?
    if [ $code -ne 0 ]; then
      echo "$sortie" | tail -12
      echo "❌ $nom : le décor n'a pas pu être posé."
      exit 2
    fi
    cid="$(printf '%s' "$sortie" | grep -oE "COMMERCANT_ID='[^']*'" | head -1 | cut -d"'" -f2)"
  else
    # Phase « promos » seule : le compte existe déjà. On relit son identifiant
    # auprès du serveur — le supposer, c'est écrire un décor qui décrit ce qu'on
    # croit avoir posé plutôt que ce qui est là.
    jeton="$(curl -s -X POST "$API_URL/commercant/login" \
      -H 'Content-Type: application/json' -H "X-Device-Id: provision-villes" \
      -d "{\"telephone\":\"$tel\",\"pin\":\"$D_PIN\"}" | lire_champ accessToken)"
    cid=""
    [ -n "$jeton" ] && cid="$(curl -s "$API_URL/commercant/me" \
      -H "Authorization: Bearer $jeton" -H "X-Device-Id: provision-villes" \
      | lire_champ id)"
  fi

  # ⚠️ Pas de repli : un identifiant vide ferait écrire un bloc `export` qui a
  # l'air complet et que le banc suivant lirait comme une chaîne vide (règle 29).
  [ -n "$cid" ] || {
    echo "❌ $nom : identifiant du commerçant illisible."
    echo "   La phase « comptes » a-t-elle été jouée ? Sur ce poste, depuis WSL :"
    echo "     ./scripts/provision-villes.sh comptes"
    exit 2; }
  echo "   compte prêt — commerçant ${cid:0:8}"

  if [ "$PHASE" = "comptes" ]; then
    cle="$(printf '%s' "$nom" | tr 'a-z-' 'A-Z_')"
    RANG=$((RANG + 1))
    RESUME="$RESUME
export VILLE_${cle}_${RANG}_TEL='$tel'  VILLE_${cle}_${RANG}_CID='$cid'  # $commerce"
    echo "   promo à créer par l'écran — phase « promos », depuis la machine Flutter"
    continue
  fi

  # ── La promo naît de l'ÉCRAN, pas d'un curl ────────────────────────────────
  #
  # ⚠️ Un décor fabriqué par un chemin que le produit n'emprunte pas ne prouve
  # rien sur ce chemin. Les promos de ces trois villes passent donc par le
  # formulaire commerçant (`parcours_creation_promo_test.dart`) : photo,
  # téléversement, création, retour, compteur. Si l'écran de création casse, le
  # décor casse — et c'est exactement ce qu'on veut savoir.
  #
  # ⚠️ Cela demande Flutter et un émulateur, donc **la machine Windows** sur ce
  # poste : le décor, lui, tourne sous WSL. Quand `flutter` n'est pas là, on le
  # DIT et on sort — un décor à moitié posé qui se tait est pire qu'un décor
  # absent (règle 29).
  command -v flutter >/dev/null 2>&1 || {
    echo "❌ $nom : flutter introuvable."
    echo "   Les promos de ce décor se créent par l'écran commerçant, ce qui"
    echo "   exige Flutter et un émulateur. Relancer depuis la machine qui les"
    echo "   porte, ou poser les comptes ici puis y lancer :"
    echo "     TEST_COMMERCANT_TEL=$tel TEST_COMMERCANT_PIN=$D_PIN \\"
    echo "       ./scripts/test-parcours-ecran.sh creation"
    exit 2; }

  # ── ⚠️ Idempotence : ne pas recréer ce qui existe ──────────────────────────
  #
  # Tout le décor repose sur ce principe (voir `provision-decor.sh`), et cette
  # phase l'avait oublié. Elle a échoué au premier passage sur Djelfa avec, en
  # toutes lettres à l'écran : **« Plafond de 5 créations de promo par 24h
  # atteint pour ce commerçant »**. Le commerçant de Djelfa est celui que tous
  # les bancs de la journée avaient déjà fait publier.
  #
  # Créer une promo de plus n'apporte rien quand le commerçant en a déjà une en
  # ligne — et le plafond quotidien fait que « rien » devient « impossible pour
  # 24 h ». On regarde donc d'abord ce que le serveur sert.
  deja="$(curl -s "$API_URL/promo/map?north=$(awk -v v=$lat 'BEGIN{print v+0.05}')&south=$(awk -v v=$lat 'BEGIN{print v-0.05}')&east=$(awk -v v=$lng 'BEGIN{print v+0.05}')&west=$(awk -v v=$lng 'BEGIN{print v-0.05}')"     -H "X-Device-Id: provision-villes"     | CID="$cid" "$PY" -c "import sys,json,os
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for c in d.get('items', []):
    if c.get('id') == os.environ['CID']:
        for p in c.get('promos') or []:
            print(p.get('id')); sys.exit(0)")"
  if [ -n "$deja" ]; then
    echo "   promo déjà en ligne (${deja:0:8}) — rien à créer"
    pid="$deja"
    cle="$(printf '%s' "$nom" | tr 'a-z-' 'A-Z_')"
    RANG=$((RANG + 1))
    RESUME="$RESUME
export VILLE_${cle}_${RANG}_TEL='$tel'  VILLE_${cle}_${RANG}_CID='$cid'  VILLE_${cle}_${RANG}_PID='$pid'  # $commerce"
    continue
  fi

  echo "   création de la promo par l'écran commerçant…"
  if ! TEST_COMMERCANT_TEL="$tel" TEST_COMMERCANT_PIN="$D_PIN"        "$HERE/test-parcours-ecran.sh" creation >/tmp/villes-$nom.log 2>&1; then
    # ⚠️ `tail` garderait la PILE et jetterait le MOTIF, qui vient AVANT.
    # C'est ce qui s'est passé au premier échec : la sortie montrait cinq
    # cadres de pile et pas la phrase « Plafond de 5 créations… ».
    grep -A 8 "The following TestFailure" "/tmp/villes-$nom.log" | head -14
    echo "❌ $nom : la création de promo par l'écran a échoué (voir /tmp/villes-$nom.log)."
    exit 2
  fi

  # L'état est CONSTATÉ auprès du serveur, pas déduit du code de sortie du
  # parcours : « l'écran n'a pas planté » et « la promo est en ligne » sont deux
  # choses différentes.
  pid="$(curl -s "$API_URL/promo/map?north=$(awk -v v=$lat 'BEGIN{print v+0.05}')&south=$(awk -v v=$lat 'BEGIN{print v-0.05}')&east=$(awk -v v=$lng 'BEGIN{print v+0.05}')&west=$(awk -v v=$lng 'BEGIN{print v-0.05}')"     -H "X-Device-Id: provision-villes"     | CID="$cid" "$PY" -c "import sys,json,os
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for c in d.get('items', []):
    if c.get('id') == os.environ['CID']:
        for p in c.get('promos') or []:
            print(p.get('id')); sys.exit(0)")"
  [ -n "$pid" ] || {
    echo "❌ $nom : aucune promo servie sur la carte pour ce commerçant après"
    echo "   la création par l'écran. Le parcours a fini sans erreur, mais le"
    echo "   serveur ne sert rien — c'est le décor qui est faux, pas le banc."
    exit 2; }
  echo "✅ $nom — commerçant ${cid:0:8}, promo ${pid:0:8} (créée à l'écran)"

  cle="$(printf '%s' "$nom" | tr 'a-z-' 'A-Z_')"
  RANG=$((RANG + 1))
  RESUME="$RESUME
export VILLE_${cle}_${RANG}_TEL='$tel'  VILLE_${cle}_${RANG}_CID='$cid'  VILLE_${cle}_${RANG}_PID='$pid'  # $commerce"
done

echo
echo "════════════════════════════════════════════════════════════════"
echo "  Trois villes posées. Bloc à exporter :"
echo "════════════════════════════════════════════════════════════════"
printf '%s\n' "$RESUME"
echo
echo "⚠️  Le PIN est celui du décor (654321) pour les trois."
echo "⚠️  Ce script a consommé jusqu'à 3 inscriptions sur un plafond de 5/min :"
echo "    attendre une minute avant d'en lancer un autre qui inscrit."
