#!/usr/bin/env sh
# Socle commun des scripts d'audit et des bancs.
#
# À copier dans `scripts/lib/audit.sh` du projet audité, puis à sourcer :
#
#     cd "$(dirname "$0")/.." || exit 2
#     . scripts/lib/audit.sh
#
# Ce fichier est GÉNÉRIQUE : il ne connaît ni l'architecture, ni les routes, ni
# les modèles du projet. Tout ce qui est propre au projet (comment appeler le
# service, comment poser le décor) va dans un second fichier, à côté.
#
# Conçu pour tourner AUSSI BIEN depuis Windows (Git Bash) que depuis WSL ou
# Linux — voir la section « Accès à Docker », qui est la partie la plus piégeuse.

# --- Interpréteur Python ------------------------------------------------------
# Requis pour lire du JSON sans dépendance. Un audit qui ne peut pas lire ses
# rapports doit s'arrêter, pas continuer en supposant.
PY=$(command -v python3 || command -v python)
if [ -z "$PY" ]; then
  echo "python introuvable — requis pour lire les rapports JSON." >&2
  exit 2
fi

# --- Verdicts -----------------------------------------------------------------
# TROIS verdicts, pas deux. Un contrôle qui n'a pas pu jouer ses scénarios n'est
# ni vert ni rouge : il n'a rien mesuré.
#
# Séparer 1 et 3 n'est pas cosmétique. Un décor incomplet qui sort en 1 fait
# accuser le PRODUIT d'un défaut qui est celui de l'ENVIRONNEMENT ; un décor
# incomplet qui sort en 0 fait imprimer « tout est au vert » sur un banc arrêté
# au sixième scénario sur trente-six. Les deux sont arrivés.
RC_OK=0
RC_ECHEC=1      # le produit s'est comporté autrement que spécifié
RC_INCOMPLET=3  # le décor ou l'environnement n'a pas permis de mesurer

# --- Compteurs et rendu -------------------------------------------------------
BANC_OK=0
BANC_KO=0
BANC_SKIP=0
BANC_FAILED_IDS=""
BANC_SKIPPED_IDS=""

if [ -t 1 ]; then
  C_OK=$(printf '\033[32m'); C_KO=$(printf '\033[31m')
  C_SKIP=$(printf '\033[33m'); C_DIM=$(printf '\033[2m'); C_OFF=$(printf '\033[0m')
else
  C_OK=; C_KO=; C_SKIP=; C_DIM=; C_OFF=
fi

titre() { printf '\n%s== %s ==%s\n' "$C_DIM" "$1" "$C_OFF"; }

# ok <id> <libellé>
ok() { BANC_OK=$((BANC_OK + 1)); printf '%s  PASS%s %-14s %s\n' "$C_OK" "$C_OFF" "$1" "$2"; }

# ko <id> <libellé> <attendu> <obtenu>
ko() {
  BANC_KO=$((BANC_KO + 1))
  BANC_FAILED_IDS="$BANC_FAILED_IDS $1"
  printf '%s  FAIL%s %-14s %s\n' "$C_KO" "$C_OFF" "$1" "$2"
  printf '        attendu : %s\n        obtenu  : %s\n' "$3" "$4"
}

# skip <id> <libellé> — « n'a rien mesuré ». JAMAIS pour un produit fautif.
skip() {
  BANC_SKIP=$((BANC_SKIP + 1))
  BANC_SKIPPED_IDS="$BANC_SKIPPED_IDS $1"
  printf '%s  SKIP%s %-14s %s\n' "$C_SKIP" "$C_OFF" "$1" "$2"
}

# sans_objet <id> <libellé> — l'objet du contrôle N'EXISTE PAS, et on l'a établi.
#
# ⚠️ CE N'EST PAS UN `skip`, ET LA DIFFÉRENCE EST TOUTE LA VALEUR DE CETTE
# FONCTION. `skip` dit « je voulais mesurer et je n'ai pas pu » — l'absence est
# INCONNUE, et le verdict d'ensemble doit rester incomplet. `sans_objet` dit
# « il n'y a rien à mesurer, et je l'ai constaté » — l'absence est ÉTABLIE.
#
# Exemple qui a fait ajouter cette fonction : le scénario « les exceptions
# taisent sans aveugler ». Sur un projet SANS fichier d'exceptions, aucune
# exception ne peut rien masquer — c'est démontré par l'absence du fichier, pas
# supposé. Le traiter en `skip` rendait l'auto-test INCOMPLET à chaque
# exécution, pour toujours. Et un contrôle perpétuellement incomplet finit
# ignoré, ce qui revient exactement à ne pas l'avoir.
#
# ⚠️ N'utiliser QUE lorsque l'absence est prouvée par une observation. « Le
# fichier n'existe pas » en est une ; « je n'ai pas trouvé comment tester » n'en
# est pas une — c'est un `skip`.
BANC_SANS_OBJET=0
BANC_SANS_OBJET_IDS=""
sans_objet() {
  BANC_SANS_OBJET=$((BANC_SANS_OBJET + 1))
  BANC_SANS_OBJET_IDS="$BANC_SANS_OBJET_IDS $1"
  printf '%s  S/O %s %-14s %s\n' "$C_DIM" "$C_OFF" "$1" "$2"
}

# Code de sortie non nul dès qu'un scénario échoue OU n'a pas pu être joué —
# c'est ce qui rend le script utilisable comme BARRIÈRE, pas seulement comme
# rapport à lire. Un ignoré compte : la question posée est « le produit est-il
# conforme ? », et « je n'ai pas regardé » n'y répond pas.
bilan() {
  printf '\n  %d réussi(s), %d échec(s), %d ignoré(s)' "$BANC_OK" "$BANC_KO" "$BANC_SKIP"
  # Les « sans objet » sont COMPTÉS ET NOMMÉS, jamais tus : un contrôle qui n'a
  # pas d'objet aujourd'hui en aura un le jour où le fichier apparaîtra, et le
  # lecteur doit savoir ce que ce vert ne couvre pas.
  [ "${BANC_SANS_OBJET:-0}" -gt 0 ] && printf ', %d sans objet :%s' \
    "$BANC_SANS_OBJET" "$BANC_SANS_OBJET_IDS"
  printf '\n'
  if [ "$BANC_KO" -gt 0 ]; then
    printf '  échecs :%s\n' "$BANC_FAILED_IDS"
    [ "$BANC_SKIP" -eq 0 ] || printf '  ignorés :%s\n' "$BANC_SKIPPED_IDS"
    return "$RC_ECHEC"
  fi
  if [ "$BANC_SKIP" -gt 0 ]; then
    printf '%s  INCOMPLET — %d scénario(s) non joué(s) :%s%s\n' \
      "$C_SKIP" "$BANC_SKIP" "$BANC_SKIPPED_IDS" "$C_OFF"
    printf '  Rien n'\''est prouvé sur ces scénarios. Corriger le décor, pas le produit.\n'
    return "$RC_INCOMPLET"
  fi
  return "$RC_OK"
}

# abandon <raison> — arrête le script en cours de route.
#
# À utiliser plutôt que `bilan; exit $?` quand le décor manque : le script
# s'arrête AVANT d'avoir joué le reste, et ce reste n'apparaît alors dans aucun
# compteur. Le chiffre « n ignorés » sous-estime donc toujours ce qui manque —
# cette ligne-ci est la seule à le dire.
abandon() {
  printf '\n%s  INTERROMPU — %s%s\n' "$C_KO" "$1" "$C_OFF"
  printf '  Les scénarios suivants n'\''ont pas été atteints : rien n'\''est prouvé\n'
  printf '  au-delà de ce point, quel que soit le nombre de PASS ci-dessus.\n'
  bilan
  exit "$RC_INCOMPLET"
}

# autotest_socle — prouve que le socle de verdict lui-même sait refuser.
#
# À appeler depuis le `--self-test` de chaque script. Sans lui, « un ignoré doit
# faire échouer » est une règle qu'aucune exécution ne contrôle — donc
# indiscernable d'une règle absente le jour où quelqu'un rebranchera `bilan` sur
# le seul `BANC_KO`.
autotest_socle() {
  # ⚠️ Les compteurs sont remis à plat dans CHAQUE sous-shell. Ils sont hérités,
  # pas repartis de zéro : appelé après un auto-test qui vient de produire des
  # échecs volontaires, le cas « ignoré » et le cas « propre » verraient tous
  # deux BANC_KO > 0 et sortiraient en 1. La première version de ce contrôle a
  # échoué exactement là-dessus.
  _neutre='BANC_OK=0; BANC_KO=0; BANC_SKIP=0; BANC_FAILED_IDS=; BANC_SKIPPED_IDS='
  _rc_ko=$(   (eval "$_neutre"; BANC_KO=1;   BANC_FAILED_IDS=" X";  bilan >/dev/null 2>&1; echo $?) )
  _rc_skip=$( (eval "$_neutre"; BANC_SKIP=1; BANC_SKIPPED_IDS=" X"; bilan >/dev/null 2>&1; echo $?) )
  _rc_vert=$( (eval "$_neutre";                                     bilan >/dev/null 2>&1; echo $?) )
  _socle=0
  [ "$_rc_ko"   = "$RC_ECHEC" ]     || { printf '  %sun échec ne fait pas sortir en %s (obtenu %s)%s\n'   "$C_KO" "$RC_ECHEC"     "$_rc_ko"   "$C_OFF"; _socle=1; }
  [ "$_rc_skip" = "$RC_INCOMPLET" ] || { printf '  %sun ignoré ne fait pas sortir en %s (obtenu %s)%s\n'  "$C_KO" "$RC_INCOMPLET" "$_rc_skip" "$C_OFF"; _socle=1; }
  [ "$_rc_vert" = "$RC_OK" ]        || { printf '  %sun contrôle propre ne sort pas en 0 (obtenu %s)%s\n' "$C_KO" "$_rc_vert"                  "$C_OFF"; _socle=1; }
  if [ "$_socle" -eq 0 ]; then
    printf '  %ssocle : échec → %s, ignoré → %s, propre → 0.%s\n' "$C_OK" "$RC_ECHEC" "$RC_INCOMPLET" "$C_OFF"
  fi
  return "$_socle"
}

# --- Assertions ---------------------------------------------------------------
# attend_egal <id> <libellé> <attendu> <obtenu>
attend_egal() {
  if [ "$3" = "$4" ]; then ok "$1" "$2"; else ko "$1" "$2" "$3" "${4:-<vide>}"; fi
}

# attend_non_vide <id> <libellé> <valeur>
attend_non_vide() {
  if [ -n "$3" ]; then ok "$1" "$2"; else ko "$1" "$2" "une valeur non vide" "<vide>"; fi
}

# attend_au_moins <id> <libellé> <minimum> <obtenu>
attend_au_moins() {
  if [ "${4:-0}" -ge "$3" ] 2>/dev/null; then ok "$1" "$2"
  else ko "$1" "$2" "au moins $3" "${4:-<vide>}"; fi
}

# --- Utilitaires --------------------------------------------------------------
# py_lit <valeur> — rend un littéral Python correctement échappé.
#
# Sert à injecter une valeur shell dans un script Python généré SANS laisser le
# shell interpréter le corps du script (heredoc `<<'PYEOF'`, délimiteur QUOTÉ).
# Un délimiteur non quoté fait relire tout le Python par le shell : `$` et les
# backticks y sont substitués, et une erreur de syntaxe peut SUPPRIMER des lignes
# du script généré — en silence si ce ne sont que des commentaires.
py_lit() { printf '%s' "$1" | "$PY" -c 'import sys; print(repr(sys.stdin.read()))'; }

# jget <json> <chemin pointé> — lit une valeur. Chaîne vide si absente.
#   jget "$reponse" result.error
#   jget "$reponse" addresses.0.id
jget() {
  printf '%s' "$1" | "$PY" -c '
import json, sys
try:
    cur = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for part in (sys.argv[1].split(".") if sys.argv[1] else []):
    if isinstance(cur, list):
        try: cur = cur[int(part)]
        except Exception: sys.exit(0)
    elif isinstance(cur, dict):
        if part not in cur: sys.exit(0)
        cur = cur[part]
    else:
        sys.exit(0)
if isinstance(cur, bool): print("true" if cur else "false")
elif cur is None: print("")
elif isinstance(cur, (dict, list)): print(json.dumps(cur, ensure_ascii=False))
else: print(cur)
' "$2"
}

# --- Accès à Docker -----------------------------------------------------------
# ⚠️ On teste l'ACCÈS À UN DÉMON, jamais la présence du binaire. Sur un poste
# Windows, `docker.exe` peut être dans le PATH alors que son démon est arrêté,
# les conteneurs tournant en réalité dans le Docker Engine de la distro WSL. Un
# test de présence répond « oui » et l'audit échoue ensuite sans message utile.
#
# ⚠️ La détection est faite UNE FOIS, hors de toute substitution de commande, et
# ce n'est pas une optimisation. Écrite en `$(_docker_via)`, la mémoïsation ne
# survit pas au sous-shell : la sonde est relancée à chaque appel, et
# `docker info` CONSOMME LE STDIN DE L'APPELANT. Mesuré — un témoin envoyé par un
# tube arrivait vide, le scanner rendait 0 constat sans erreur, et le scénario
# accusait la configuration. `</dev/null` verrouille la propriété plutôt que de
# la confier à l'ordre des appels.
_DOCKER_VIA=""
if   docker info </dev/null >/dev/null 2>&1;                   then _DOCKER_VIA="direct"
elif wsl -e bash -lc 'docker info' </dev/null >/dev/null 2>&1; then _DOCKER_VIA="wsl"
else _DOCKER_VIA="aucun"; fi

# ⚠️⚠️ `</dev/null` N'EST PAS UNE PRÉCAUTION, C'EST LA CORRECTION D'UN DÉFAUT
# MESURÉ. `wsl` (comme `docker run` sans `-i`) CONSOMME LE STDIN DE L'APPELANT.
# Appelé depuis une boucle `while read`, il avale le reste de l'entrée et la
# boucle s'arrête après le PREMIER tour — sans erreur, sans message.
#
# Constaté sur un projet réel : l'audit d'image n'auditait que le premier
# service des composes, puis imprimait un bilan propre. Un audit partiel qui
# annonce un succès complet est exactement le vert mensonger que ce socle existe
# pour supprimer.
#
# Le défaut par défaut est donc l'ISOLATION du stdin ; les rares appels qui ont
# besoin de le laisser passer utilisent `docker_sh_stdin`, et doivent le dire.
docker_sh() {
  case "$_DOCKER_VIA" in
    direct) sh -c "$1" </dev/null ;;
    wsl)    wsl -e bash -lc "$1" </dev/null ;;
    *)      return 127 ;;
  esac
}

# docker_sh_stdin — variante qui LAISSE PASSER stdin, pour les conteneurs qui
# doivent lire un flux (`docker run -i`). À n'utiliser jamais dans une boucle
# qui lit elle-même une entrée.
docker_sh_stdin() {
  case "$_DOCKER_VIA" in
    direct) sh -c "$1" ;;
    wsl)    wsl -e bash -lc "$1" ;;
    *)      return 127 ;;
  esac
}

# verifie_docker <id du scénario> — rend INCOMPLET si aucun démon n'est joignable.
verifie_docker() {
  if [ "$_DOCKER_VIA" = "aucun" ]; then
    skip "${1:-SC-ENV.0}" "Docker joignable — aucun démon atteint (ni direct, ni via WSL)"
    printf '  Démarrer Docker, ou installer l'\''outil localement et adapter ce script.\n'
    bilan; exit $?
  fi
}

# chemin_depot — le chemin du dépôt TEL QUE LE DÉMON LE VOIT.
#
# ⚠️ Depuis Git Bash, `pwd` rend `/c/Users/…` ; le démon vit dans WSL, où le même
# dossier est `/mnt/c/Users/…`. Sans cette conversion, `docker run -v` crée un
# volume VIDE du nom du chemin, et l'outil scanne un dossier vide — en rendant
# 0 constat, donc en VERT.
chemin_depot() {
  _p="$(pwd)"
  if [ "$_DOCKER_VIA" = "wsl" ]; then
    case "$_p" in
      /[a-zA-Z]/*) printf '/mnt%s' "$_p"; return ;;
    esac
  fi
  printf '%s' "$_p"
}

# sans_cr — filtre à intercaler derrière toute valeur lue d'un sous-processus et
# réinjectée dans une ligne de commande.
#
# ⚠️ Un interpréteur Python sous Windows écrit des fins de ligne CRLF. Le `\r`
# survit au découpage en mots du shell, part dans la commande, et l'outil refuse
# une référence qui paraît pourtant parfaitement correcte à l'affichage — le
# caractère fautif étant invisible. Mesuré, pas supposé.
sans_cr() { tr -d '\r'; }

# --- Découverte des cibles ----------------------------------------------------
# ⚠️ Ne JAMAIS recopier une liste d'images dans un script. Le jour où quelqu'un
# ajoute un service, l'audit continuerait de rendre du vert sur les images
# d'hier sans qu'aucun message ne le dise.

# services_du_compose <fichier> — une ligne par service :
#     image<TAB><service><TAB><référence d'image>
#     build<TAB><service><TAB><contexte><TAB><dockerfile>
#
# ⚠️ LES SERVICES `build:` SONT LA MOITIÉ QU'ON OUBLIE, ET C'EST LA PLUS
# IMPORTANTE. Une première version de cette fonction ne lisait que les clés
# `image:`. Sur un projet réel (NestJS + Postgres + MinIO), elle rendait
# « postgres:16-alpine minio/minio:latest minio/mc:latest » — c'est-à-dire tout
# SAUF l'image du backend, celle qui porte le code applicatif, ses dépendances
# de production et son image de base. Et l'audit imprimait cette liste comme
# « images déclarées », ce qui se lit comme une couverture complète.
#
# Un audit qui tait la seule image que TU produis n'est pas un audit partiel,
# c'est un audit qui regarde à côté.
services_du_compose() {
  "$PY" - "$1" <<'PYEOF' | tr -d '\r'
import io, re, sys

lignes = io.open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
service, indent_svc, dans_services = None, None, False
build_ctx, build_file, image = {}, {}, {}
dans_build, indent_build = None, None

def creux(l):
    return len(l) - len(l.lstrip(" "))

for ligne in lignes:
    if not ligne.strip() or ligne.lstrip().startswith("#"):
        continue
    ind = creux(ligne)
    nu = ligne.strip()

    if ind == 0:
        dans_services = nu.startswith("services:")
        service = dans_build = None
        continue
    if not dans_services:
        continue

    # Un service est une clé au premier niveau sous `services:`.
    if indent_svc is None or ind == indent_svc:
        m = re.match(r"^([A-Za-z0-9_.-]+):\s*$", nu)
        if m and (indent_svc is None or ind == indent_svc):
            indent_svc, service, dans_build = ind, m.group(1), None
            continue
    if service is None:
        continue
    if ind <= indent_svc:
        continue

    if dans_build is not None and ind > indent_build:
        m = re.match(r"^context:\s*(.+)$", nu)
        if m: build_ctx[service] = m.group(1).strip().strip("'\"")
        m = re.match(r"^dockerfile:\s*(.+)$", nu)
        if m: build_file[service] = m.group(1).strip().strip("'\"")
        continue
    dans_build = None

    m = re.match(r"^image:\s*([^\s#]+)", nu)
    if m:
        image[service] = m.group(1).strip("'\"")
        continue
    m = re.match(r"^build:\s*(.*)$", nu)
    if m:
        valeur = m.group(1).strip().strip("'\"")
        if valeur:                      # forme courte : `build: ./apps/backend`
            build_ctx[service] = valeur
        else:                           # forme longue : bloc `build:` indenté
            dans_build, indent_build = service, ind

for svc in sorted(set(list(image) + list(build_ctx))):
    # Un service peut avoir LES DEUX : `build:` + `image:` (nom de l'image
    # construite). Dans ce cas l'image nommée est la cible réelle — on la
    # signale comme image ET on garde la trace du build.
    if svc in image:
        print("image\t%s\t%s" % (svc, image[svc]))
    if svc in build_ctx:
        print("build\t%s\t%s\t%s" % (svc, build_ctx[svc], build_file.get(svc, "Dockerfile")))
PYEOF
}

# images_du_compose <fichier> — seulement les images TIRÉES (compatibilité).
images_du_compose() {
  services_du_compose "$1" | awk -F'\t' '$1=="image" {print $3}'
}

# bases_du_dockerfile <chemin du Dockerfile> — les `FROM` non locaux.
#
# Repli quand l'image construite n'existe pas localement : auditer ses images de
# BASE dit déjà l'essentiel du socle système. ⚠️ Ça ne couvre PAS les paquets
# installés par le Dockerfile lui-même — et il faut donc le dire.
bases_du_dockerfile() {
  [ -f "$1" ] || return 1
  "$PY" - "$1" <<'PYEOF' | tr -d '\r'
import io, re, sys
alias, bases = set(), []
for ligne in io.open(sys.argv[1], encoding="utf-8", errors="replace"):
    m = re.match(r"(?i)^\s*FROM\s+(\S+)(?:\s+AS\s+(\S+))?", ligne)
    if not m:
        continue
    ref, nom = m.group(1), m.group(2)
    if ref not in alias and not ref.startswith("$") and ref not in bases:
        bases.append(ref)
    if nom:
        alias.add(nom)
print("\n".join(bases))
PYEOF
}

# composes_trouves — TOUS les fichiers de composition, un par ligne.
#
# ⚠️ Rendre le PREMIER trouvé était un défaut : un projet a couramment un compose
# de développement et un compose de production, et c'est le second qui compte
# (« scanner l'image de production, qui n'est pas forcément celle de dev »). Un
# script qui en choisit un en silence audite peut-être le mauvais, et rien ne le
# dit. On les rend tous ; l'appelant les nomme.
composes_trouves() {
  for _c in docker-compose*.yml docker-compose*.yaml compose*.yml compose*.yaml \
            backend/docker-compose*.yml deploy/docker-compose*.yml \
            infra/docker-compose*.yml apps/*/docker-compose*.yml; do
    [ -f "$_c" ] && printf '%s\n' "$_c"
  done 2>/dev/null | sort -u
}

# compat : le premier trouvé (à n'utiliser que si un seul compose est attendu).
compose_trouve() { composes_trouves | head -1; }
