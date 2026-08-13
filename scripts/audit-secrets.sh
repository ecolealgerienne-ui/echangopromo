#!/usr/bin/env sh
# C5 — Recherche de secrets dans l'ARBRE et dans l'HISTOIRE git.
#
# ⚠️ L'HISTORIQUE est l'objet du contrôle, pas l'arbre. Retirer un secret d'un
# fichier ne le retire pas du dépôt : `git log -S` le rend en une commande, et
# toute copie clonée le porte. La seule remédiation réelle est la RÉVOCATION ; la
# réécriture d'historique est une décision séparée. Et quand le secret n'est pas
# révocable (un identifiant métier), la remédiation est de NE JAMAIS CRÉER ce
# couple en production — et ça doit être écrit.
#
# ⚠️ ET LE JEU DE RÈGLES PAR DÉFAUT NE TROUVE PEUT-ÊTRE RIEN CHEZ TOI. Les ~170
# règles livrées cherchent des jetons à SIGNATURE (`AKIA…`, `ghp_…`, clés PEM) :
# des chaînes que leur seule apparence trahit. Un identifiant métier — un PIN à
# 6 chiffres, un numéro de téléphone, un mot de passe qui est un mot du
# dictionnaire — n'a AUCUNE forme reconnaissable. Les règles qui les voient sont
# dans `.gitleaks.toml`, à écrire pour CE dépôt (voir `gitleaks.toml.modele`).
#
# ⚠️ DEUX MOTEURS, ET CE N'EST PAS DE LA CEINTURE-BRETELLES. Mesuré sur un même
# fichier portant trois faux secrets : gitleaks 2/3, semgrep 1/3, ensemble 3/3.
# Chacun rate exactement ce que l'autre voit. Un audit à un seul moteur laisse
# passer une famille entière EN RENDANT DU VERT. C'est une mesure qui a décidé,
# pas un principe de précaution — et SC-SEC.45 la rejoue à chaque auto-test.
#
# Usage :
#   sh scripts/audit-secrets.sh              # arbre + historique
#   sh scripts/audit-secrets.sh --self-test  # vérifie que l'audit sait REFUSER
#
# Nécessite Docker (images officielles, rien à installer) et, la première fois,
# le réseau.

cd "$(dirname "$0")/.." || exit 2
. scripts/lib/audit.sh

# Image ÉPINGLÉE, contrairement à trivy : un audit dont le jeu de règles change
# tout seul rend des verdicts non comparables d'une semaine à l'autre. À relever
# délibérément — les nouvelles règles ne servent à rien tant que personne n'a
# décidé de les faire entrer.
GITLEAKS_IMG="${AUDIT_GITLEAKS_IMG:-zricethezav/gitleaks:v8.30.1}"
SEMGREP_IMG="${AUDIT_SEMGREP_IMG:-semgrep/semgrep:latest}"

CONF="${AUDIT_GITLEAKS_CONF:-.gitleaks.toml}"

# ─── CALIBRATION — à renseigner au premier passage sur un projet ──────────────
#
# Le témoin le plus fort d'un audit de secrets est une fuite RÉELLE de ce dépôt :
# connue, datée, et dont la remédiation par réécriture a été écartée. Rejouée
# avec le fichier d'exceptions neutralisé, elle fait travailler TOUTE la chaîne —
# montage du volume, lecture de l'historique git, chargement de la configuration,
# déclenchement des règles maison. Un volume mal monté rend un dossier vide, donc
# 0 constat, donc du VERT : ce scénario est le seul à pouvoir le dire.
#
#   TEMOIN_CONF   : configuration utilisée UNIQUEMENT par le témoin (facultatif ;
#                   à défaut, la configuration réelle)
#   TEMOIN_REGLES : expression régulière sur les identifiants de règles attendus
#   TEMOIN_COMPTE : nombre EXACT de constats attendus  (fuite figée)
#   TEMOIN_MIN    : nombre MINIMAL de constats attendus (témoin qui peut croître)
#
# ═══ ET SI LE DÉPÔT N'A AUCUNE FUITE ? ═══════════════════════════════════════
#
# C'est un bon résultat, et ça ne doit pas laisser ce scénario en « n'a rien
# mesuré » à vie — un contrôle perpétuellement incomplet finit ignoré, ce qui
# revient à ne pas l'avoir.
#
# La parade : un **témoin de chaîne**. Une règle jetable, dans un fichier de
# configuration à part (TEMOIN_CONF), qui vise une chaîne dont on SAIT qu'elle
# est dans l'historique — typiquement un identifiant de DÉCOR de banc, qui n'est
# pas un secret et n'a donc rien à faire dans l'audit réel.
#
# Elle prouve exactement ce qu'on veut prouver : le volume est monté, l'historique
# est lu, la configuration est chargée, une règle maison se déclenche. Elle ne
# prouve pas qu'une vraie fuite serait vue — pour ça il faudrait une vraie fuite.
# La distinction doit être écrite dans le rapport.
#
# ⚠️ Un témoin de décor CROÎT avec les commits : utiliser TEMOIN_MIN, jamais
# TEMOIN_COMPTE. Un compte exact ferait rougir l'audit au prochain commit, sur un
# outil parfaitement correct.
#
# ⚠️ Laissés tous vides, SC-SEC.40 rend « n'a rien mesuré » — c'est voulu.
# ── CALIBRÉ POUR echango Promo le 2026-08-13 ────────────────────────────────
# Ce dépôt n'a AUCUNE fuite réelle : les couples téléphone/PIN de l'historique
# sont du décor de banc (voir `.gitleaks.toml`). Le témoin est donc un témoin de
# CHAÎNE — il prouve que le volume est monté, que l'historique est parcouru,
# qu'une configuration est chargée et qu'une règle maison se déclenche. Il ne
# prouve pas qu'une vraie fuite serait vue : pour ça il faudrait une vraie fuite,
# et c'est écrit dans le rapport.
TEMOIN_CONF="${AUDIT_TEMOIN_CONF:-scripts/temoin-secrets.toml}"
TEMOIN_REGLES="${AUDIT_TEMOIN_REGLES:-promo-temoin-chaine}"
TEMOIN_COMPTE="${AUDIT_TEMOIN_COMPTE:-}"
# MIN et non COMPTE : le décor croît avec les commits. Un compte exact ferait
# rougir l'audit au prochain commit, sur un outil parfaitement correct.
TEMOIN_MIN="${AUDIT_TEMOIN_MIN:-1}"

# Plancher de fichiers analysés par le second moteur. En dessous, c'est que le
# montage ou les exclusions ont échoué, et « 0 constat » ne veut plus rien dire.
SEMGREP_PLANCHER="${AUDIT_SEMGREP_PLANCHER:-20}"

_REP="${TMPDIR:-/tmp}/audit-gl.$$.json"
_REP2="${TMPDIR:-/tmp}/audit-gl2.$$.json"
_ERR="${TMPDIR:-/tmp}/audit-gl-err.$$"
trap 'rm -f "$_REP" "$_REP2" "$_ERR"' EXIT

# gitleaks <sous-commande> [montages supplémentaires] — rapport JSON sur stdout.
#
# Le dépôt est monté en LECTURE SEULE : un audit n'écrit pas dans ce qu'il audite.
#
# `--redact` n'est pas un confort : sans lui, le rapport imprime les secrets EN
# CLAIR — le résultat de l'audit devient alors lui-même un secret, dans un
# terminal, un fichier de CI ou un ticket.
#
# ⚠️ Il n'y a PAS de drapeau pour désactiver `.gitleaksignore` : `-i` accepte un
# autre chemin, mais gitleaks relit de toute façon celui qui se trouve à la
# racine de la source (mesuré — `-i /tmp` et `-i /nulle-part` rendent tous deux
# 0 constat, comme si tout était accepté). D'où le second montage utilisé par
# l'auto-test, qui superpose `/dev/null` au fichier d'exceptions.
gitleaks_json() {
  _sous_cmd="$1"; shift
  _conf=""
  [ -f "${_CONF_UTILISEE:-$CONF}" ] && _conf="-c /repo/${_CONF_UTILISEE:-$CONF}"
  docker_sh "docker run --rm -v $(chemin_depot):/repo:ro $* $GITLEAKS_IMG $_sous_cmd ${_CIBLE:-/repo} \
    $_conf --report-format json --report-path - --exit-code 0 --no-banner --redact \
    --log-level error" 2>"$_ERR"
}

# constats <json> — « <règle> <fichier> <commit> » par constat. Sort en ERREUR si
# le JSON est inexploitable : un audit qui ne sait pas s'il a scanné quoi que ce
# soit doit se taire, pas rassurer.
constats() {
  "$PY" - "$1" <<'PYEOF'
import io, json, sys
try:
    donnees = json.load(io.open(sys.argv[1], encoding="utf-8"))
except Exception as exc:
    sys.stderr.write("rapport gitleaks illisible : %s\n" % exc)
    sys.exit(2)
if not isinstance(donnees, list):
    sys.stderr.write("rapport gitleaks inattendu (%s)\n" % type(donnees).__name__)
    sys.exit(2)
for x in donnees:
    print("%s\t%s\t%s" % (x.get("RuleID", "?"), x.get("File", "?"), (x.get("Commit") or "-")[:8]))
PYEOF
}

semgrep_json() {
  docker_sh "docker run --rm -v $(chemin_depot):/repo:ro -w /repo $SEMGREP_IMG \
    semgrep scan --config=p/secrets --metrics=off --json --quiet $1" 2>"$_ERR"
}

# resume_semgrep <json> — « <analysés> <constats> » puis une ligne par constat.
resume_semgrep() {
  "$PY" - "$1" <<'PYEOF'
import io, json, sys
try:
    d = json.load(io.open(sys.argv[1], encoding="utf-8"))
except Exception as exc:
    sys.stderr.write("rapport semgrep illisible : %s\n" % exc)
    sys.exit(2)
if not isinstance(d, dict) or "results" not in d:
    sys.stderr.write("rapport semgrep inattendu (pas de cle results)\n")
    sys.exit(2)
res = d.get("results") or []
print("%d\t%d" % (len((d.get("paths") or {}).get("scanned") or []), len(res)))
for r in res:
    print("%s\t%s:%s" % (r.get("check_id", "?").split(".")[-1],
                         r.get("path", "?"), (r.get("start") or {}).get("line", "?")))
PYEOF
}

# --- Auto-test : cet audit sait-il REFUSER ? ----------------------------------
# Ici le principe mord plus fort qu'ailleurs : le résultat NORMAL de cet audit
# est « rien à signaler », exactement le même affichage qu'un audit qui aurait
# scanné un dossier vide, perdu ses règles ou mal monté son volume. Trois façons
# de rendre un vert mensonger, AUCUNE ne produit d'erreur.
if [ "$1" = "--self-test" ]; then
  titre "Auto-test — l'audit de secrets sait-il signaler une fuite ?"
  verifie_docker "SC-SEC.40"
  autotest_socle || exit "$RC_ECHEC"

  # (1) La chaîne complète travaille-t-elle, et une règle maison se déclenche-t-elle ?
  if [ -z "$TEMOIN_REGLES" ] || { [ -z "$TEMOIN_COMPTE" ] && [ -z "$TEMOIN_MIN" ]; }; then
    skip "SC-SEC.40" "la chaîne de mesure travaille — AUCUN TÉMOIN CALIBRÉ"
    printf '  %sRenseigner TEMOIN_REGLES + (TEMOIN_COMPTE ou TEMOIN_MIN) en tête.%s\n' "$C_DIM" "$C_OFF"
    printf '  %sSans témoin, rien ne prouve que le volume est monté, que l'\''historique%s\n' "$C_DIM" "$C_OFF"
    printf '  %sest lu, ni qu'\''une règle maison se déclenche — et « 0 constat » ne%s\n' "$C_DIM" "$C_OFF"
    printf '  %sveut alors rien dire. Voir « ET SI LE DÉPÔT N'\''A AUCUNE FUITE ? ».%s\n' "$C_DIM" "$C_OFF"
  elif ! git rev-parse --git-dir >/dev/null 2>&1; then
    skip "SC-SEC.40" "témoin de chaîne — pas un dépôt git, aucun historique à lire"
  else
    # On rejoue l'historique avec le fichier d'exceptions NEUTRALISÉ — sinon on
    # ne testerait que le fichier d'exceptions.
    _CONF_UTILISEE="${TEMOIN_CONF:-$CONF}"
    # ⚠️ Le montage de neutralisation n'est posé QUE si le fichier existe.
    # Le dépôt est monté en lecture seule : superposer `/dev/null` sur un chemin
    # ABSENT fait échouer la création du conteneur —
    #   « make mountpoint ".gitleaksignore": read-only file system »
    # — donc l'audit entier, sur un projet qui n'a simplement rien à excepter.
    # Mesuré sur un dépôt sans `.gitleaksignore`. S'il n'existe pas, il n'y a
    # rien à neutraliser : le scan est déjà non filtré.
    _neutralise=""
    if [ -f .gitleaksignore ]; then
      _neutralise="-v /dev/null:/repo/.gitleaksignore:ro"
      printf '  %sscan de l'\''historique avec %s, .gitleaksignore neutralisé…%s\n' \
        "$C_DIM" "$_CONF_UTILISEE" "$C_OFF"
    else
      printf '  %sscan de l'\''historique avec %s (aucun .gitleaksignore à neutraliser)…%s\n' \
        "$C_DIM" "$_CONF_UTILISEE" "$C_OFF"
    fi
    gitleaks_json git "$_neutralise" > "$_REP"
    if ! _c=$(constats "$_REP"); then
      skip "SC-SEC.40" "rapport gitleaks exploitable — sortie illisible"
      cat "$_ERR" >&2; _CONF_UTILISEE=""; bilan; exit $?
    fi
    _vus=$(printf '%s\n' "$_c" | grep -cE "$TEMOIN_REGLES")
    if [ -n "$TEMOIN_COMPTE" ]; then
      attend_egal "SC-SEC.40" "le témoin de l'historique est retrouvé" "$TEMOIN_COMPTE" "$_vus"
    else
      attend_au_moins "SC-SEC.40" "le témoin de l'historique est retrouvé (chaîne complète)" \
        "$TEMOIN_MIN" "$_vus"
    fi

    # (2) Le fichier d'exceptions est-il bien APPLIQUÉ ? Sans ce contrôle, un
    # `.gitleaksignore` cassé rendrait l'audit rouge en permanence — et un
    # contrôle toujours rouge finit ignoré, ce qui revient à ne pas l'avoir.
    #
    # ⚠️ N'a de sens QUE si le témoin est censé être tu par les exceptions —
    # c'est-à-dire une vraie fuite acceptée. Un témoin de DÉCOR, lui, n'est vu
    # que par la configuration jetable : le rejouer avec la configuration réelle
    # rendrait 0 pour une raison qui n'a rien à voir avec les exceptions.
    if [ ! -f .gitleaksignore ]; then
      # Absence ÉTABLIE, pas inconnue : sans fichier d'exceptions, aucune
      # exception ne peut masquer quoi que ce soit. Un `skip` ici rendrait
      # l'auto-test incomplet pour toujours, et un contrôle perpétuellement
      # incomplet finit ignoré.
      sans_objet "SC-SEC.41" "les exceptions taisent sans aveugler — aucun .gitleaksignore, rien ne peut être masqué"
    else
      # ⚠️ ÉPROUVÉ AVEC LA CONFIGURATION RÉELLE, ET PAR COMPARAISON — pas avec
      # le témoin. Une première version ne savait tester ce scénario qu'avec un
      # témoin de fuite réelle : dès qu'on utilisait un témoin de décor, elle
      # rendait « n'a rien mesuré » à chaque exécution, donc pour toujours.
      #
      # La question n'est pas « le témoin est-il tu ? » mais « le fichier
      # d'exceptions TAIT-il quelque chose, ou AVEUGLE-t-il ? ». Elle se répond
      # en rejouant le MÊME scan sans lui : ce qui réapparaît est ce qu'il
      # masque. S'il ne masque rien, il est inutile — et probablement périmé.
      _CONF_UTILISEE=""
      gitleaks_json git > "$_REP2"
      _avec=$(constats "$_REP2" 2>/dev/null | grep -c . || true)
      gitleaks_json git "-v /dev/null:/repo/.gitleaksignore:ro" > "$_REP"
      _sans=$(constats "$_REP" 2>/dev/null | grep -c . || true)
      if [ "${_sans:-0}" -gt "${_avec:-0}" ]; then
        ok "SC-SEC.41" "les exceptions taisent sans aveugler ($_avec avec, $_sans sans)"
      else
        ko "SC-SEC.41" "les exceptions taisent sans aveugler" \
          "plus de constats sans le fichier d'exceptions" \
          "$_sans sans, $_avec avec — il ne masque rien, ou il masque tout"
      fi
    fi
    _CONF_UTILISEE=""
  fi

  # (3) Les ~170 règles PAR DÉFAUT sont-elles toujours actives ? `useDefault` est
  # UNE ligne de `.gitleaks.toml` : la retirer ne casse rien, ne dit rien, et ne
  # se verrait que le jour où une vraie clé passerait inaperçue.
  #
  # ⚠️ Le témoin n'est PAS la clé d'exemple d'une documentation officielle :
  # mesuré, gitleaks l'écarte lui-même (les valeurs contenant `EXAMPLE` sont dans
  # sa liste de mots vides). Un témoin que l'outil refuse par principe ferait
  # échouer ce scénario en permanence, sur un outil correct.
  #
  # Le jeton ci-dessous est un faux, assemblé en DEUX MORCEAUX à dessein : écrit
  # d'un seul tenant, il serait détecté dans ce fichier même, et l'audit se
  # signalerait lui-même à chaque exécution.
  _faux_jeton="ghp_016C8c1eF9ba3De4Ac""2b7D5fA0e9B8c7D6E5"
  # `docker_sh_stdin` et non `docker_sh` : ce conteneur DOIT lire le témoin sur
  # son entrée standard. C'est le seul appel du skill dans ce cas.
  _def=$(printf 'jeton=%s\n' "$_faux_jeton" | docker_sh_stdin \
    "docker run --rm -i $GITLEAKS_IMG stdin --report-format json --report-path - \
     --exit-code 0 --no-banner --redact --log-level error" 2>/dev/null)
  attend_egal "SC-SEC.42" "les règles par défaut sont actives (faux jeton GitHub vu)" "1" \
    "$(printf '%s' "$_def" | "$PY" -c 'import json,sys
try: print(len(json.load(sys.stdin)))
except Exception: print(0)')"

  # (3 bis) LA CONFIGURATION RÉELLE EST-ELLE SEULEMENT CHARGEABLE ?
  #
  # ⚠️ SCÉNARIO AJOUTÉ APRÈS UN TROU MESURÉ DANS CET AUTO-TEST. Avec un témoin
  # de chaîne (TEMOIN_CONF), les scénarios précédents chargent la configuration
  # JETABLE — la vraie n'est jamais lue. Un auto-test entièrement vert a donc
  # cohabité avec un `.gitleaks.toml` que gitleaks ne pouvait pas compiler, et
  # le défaut n'est apparu qu'à l'audit réel.
  #
  # Le piège précis : gitleaks compile avec RE2 (Go), qui ne connaît PAS les
  # lookaheads `(?!…)`. Et il ne rend pas une erreur de configuration — il
  # **panique**. Le rapport devient illisible, l'audit rend « n'a rien mesuré »,
  # et rien ne dit que la cause est une seule expression régulière.
  #
  # On charge donc la vraie configuration en la faisant scanner ELLE-MÊME :
  # un fichier, instantané, et toutes ses règles compilées.
  if [ ! -f "$CONF" ]; then
    sans_objet "SC-SEC.46" "la configuration réelle est chargeable — aucun $CONF, seules les règles par défaut tournent"
  else
    _CONF_UTILISEE=""; _CIBLE="/repo/$CONF"
    gitleaks_json dir > "$_REP"
    if constats "$_REP" >/dev/null 2>&1; then
      ok "SC-SEC.46" "la configuration réelle ($CONF) compile et se charge"
    else
      ko "SC-SEC.46" "la configuration réelle ($CONF) compile et se charge" \
        "un rapport exploitable" "gitleaks n'a rien rendu (voir ci-dessous)"
      sed -n '1,3p' "$_ERR" >&2
    fi
    _CIBLE=""
  fi

  # (4) Le SECOND moteur voit-il ce que le premier RATE ? C'est toute la
  # justification de sa présence : sans ce scénario, on aurait deux outils dont
  # on CROIT qu'ils se complètent.
  #
  # Le témoin est une clé AWS — mesuré, gitleaks ne la signale pas et semgrep si.
  # Assemblée en deux morceaux, comme celui de SC-SEC.42.
  _faux_aws="AKIA2E0A8F3B""244C9986"
  printf '  %ssecond moteur sur un témoin que le premier rate…%s\n' "$C_DIM" "$C_OFF"
  docker_sh "docker run --rm $SEMGREP_IMG sh -c \"printf 'const k = \\\"$_faux_aws\\\";' > /tmp/t.js && \
    semgrep scan --config=p/secrets --metrics=off --json --quiet /tmp/t.js\"" > "$_REP" 2>"$_ERR"
  if ! _rs=$(resume_semgrep "$_REP"); then
    skip "SC-SEC.45" "rapport semgrep exploitable — sortie illisible"
    cat "$_ERR" >&2; bilan; exit $?
  fi
  attend_egal "SC-SEC.45" "le 2e moteur voit la clé AWS que le 1er rate" "1" \
    "$(printf '%s' "$_rs" | head -1 | cut -f2)"

  bilan; exit $?
fi

# --- Audit réel ---------------------------------------------------------------
titre "Secrets — arbre de travail et historique git"
verifie_docker "SC-SEC.43"

printf '  %s%s, dépôt monté en lecture seule, secrets masqués%s\n' "$C_DIM" "$GITLEAKS_IMG" "$C_OFF"
[ -f "$CONF" ] || printf '  %s⚠️ aucun %s — SEULES les règles par défaut tournent, et elles ne%s\n' \
  "$C_SKIP" "$CONF" "$C_OFF"
[ -f "$CONF" ] || printf '  %s   voient que les secrets qui ont une FORME. Voir gitleaks.toml.modele.%s\n' \
  "$C_SKIP" "$C_OFF"

_TOTAL=0
for _cible in git dir; do
  case "$_cible" in
    git) _libelle="historique complet"; _id="SC-SEC.43"
         git rev-parse --git-dir >/dev/null 2>&1 || {
           skip "$_id" "$_libelle — pas un dépôt git, la moitié la plus utile de cette couche est absente"
           continue; } ;;
    dir) _libelle="arbre de travail";   _id="SC-SEC.44" ;;
  esac
  gitleaks_json "$_cible" > "$_REP"
  if ! _c=$(constats "$_REP"); then
    skip "$_id" "scan « $_libelle » exploitable — rapport illisible"
    cat "$_ERR" >&2
    continue
  fi
  _n=$(printf '%s' "$_c" | grep -c . || true)
  if [ "$_n" -gt 0 ]; then
    printf '%s\n' "$_c" | while IFS="$(printf '\t')" read -r _regle _fic _com; do
      ko "$_id" "$_libelle — $_regle dans $_fic ($_com)" "aucun secret" "$_regle"
    done
    _TOTAL=$((_TOTAL + _n))
  else
    ok "$_id" "$_libelle — aucun secret non accepté"
  fi
done

# --- Second moteur ------------------------------------------------------------
printf '  %s%s — second moteur (couvre ce que le premier rate)%s\n' "$C_DIM" "$SEMGREP_IMG" "$C_OFF"
semgrep_json . > "$_REP"
if ! _rs=$(resume_semgrep "$_REP"); then
  skip "SC-SEC.45" "scan semgrep exploitable — rapport illisible"
  cat "$_ERR" >&2
else
  _scannes=$(printf '%s' "$_rs" | head -1 | cut -f1)
  _trouves=$(printf '%s' "$_rs" | head -1 | cut -f2)
  if [ "${_scannes:-0}" -lt "$SEMGREP_PLANCHER" ]; then
    skip "SC-SEC.45" "fichiers analysés — seulement $_scannes (plancher $SEMGREP_PLANCHER) — la lecture a échoué"
  elif [ "${_trouves:-0}" -gt 0 ]; then
    printf '%s\n' "$_rs" | tail -n +2 | while IFS="$(printf '\t')" read -r _regle _ou; do
      ko "SC-SEC.45" "semgrep — $_regle dans $_ou" "aucun secret" "$_regle"
    done
    _TOTAL=$((_TOTAL + _trouves))
  else
    ok "SC-SEC.45" "second moteur — aucun secret sur $_scannes fichiers"
  fi
fi

if [ "$_TOTAL" -gt 0 ]; then
  # `while` tourne dans un sous-shell : ses compteurs sont perdus, l'échec est
  # donc rendu explicitement plutôt que confié à `bilan`.
  printf '\n  %sDes secrets non acceptés sont présents.%s\n' "$C_KO" "$C_OFF"
  printf '  Deux issues, et une seule est une correction :\n'
  printf '    • le retirer ET LE RÉVOQUER — sortir un secret de l'\''arbre ne le sort\n'
  printf '      pas de l'\''historique, il reste dans toute copie clonée ;\n'
  printf '    • si le secret n'\''est pas révocable (un identifiant métier), la seule\n'
  printf '      remédiation est de NE JAMAIS créer cette valeur en production ;\n'
  printf '    • l'\''accepter dans .gitleaksignore, AVEC SA RAISON ÉCRITE.\n'
  exit "$RC_ECHEC"
fi

printf '\n  %sCe vert ne couvre que ce que les règles savent voir.%s\n' "$C_DIM" "$C_OFF"
printf '  %sÉnumérer ici les fuites connues et acceptées : elles ne sont pas%s\n' "$C_DIM" "$C_OFF"
printf '  %scorrigées, elles sont CONNUES. Un rapport qui les tait ment par omission.%s\n' "$C_DIM" "$C_OFF"

bilan
exit $?
