#!/usr/bin/env sh
# C4 — Vulnérabilités connues des IMAGES de conteneur (trivy).
#
# ⚠️ C'est la plus grande surface non auditée d'un projet, et elle n'est pas
# faite de ton code. La couche C3 couvre les paquets applicatifs, le SAST couvre
# ce que tu écris — restent les quelques centaines de paquets système des images
# de base, que personne n'a choisis, que personne ne met à jour, et qui tournent
# en production.
#
# Usage :
#   sh scripts/audit-image.sh              # audite les images du compose
#   sh scripts/audit-image.sh --self-test  # vérifie que l'audit sait REFUSER
#
# Nécessite Docker et le réseau (base de vulnérabilités + images). Hors du
# lanceur de bancs, pour que ceux-ci restent jouables hors ligne.

cd "$(dirname "$0")/.." || exit 2
. scripts/lib/audit.sh

# `latest` est ici DÉLIBÉRÉ, contrairement à `audit-secrets.sh` qui épingle son
# outil. Ce n'est pas une incohérence : la valeur de trivy est dans sa base de
# vulnérabilités, qu'il retélécharge à chaque exécution quelle que soit la
# version du binaire. Épingler le binaire ne figerait donc pas le verdict — ça
# ne ferait que rater les nouveaux formats de paquets.
TRIVY_IMG="${AUDIT_TRIVY_IMG:-aquasec/trivy:latest}"

# Fichier d'exceptions — voir `trivyignore.yaml.modele`.
EXCEPTIONS="${AUDIT_TRIVY_IGNORE:-.trivyignore.yaml}"

# Les composes sont DÉCOUVERTS, pas écrits en dur, et on les prend TOUS.
#
# ⚠️ N'en prendre qu'un était un défaut. Un projet a couramment un compose de
# développement et un compose de production ; celui qui compte pour la sécurité
# est le second, et un script qui en choisit un en silence audite peut-être le
# mauvais sans que rien ne le dise. Renseigner AUDIT_COMPOSE pour forcer.
COMPOSES="${AUDIT_COMPOSE:-$(composes_trouves)}"

_REP="${TMPDIR:-/tmp}/audit-trivy.$$.json"
_ERR="${TMPDIR:-/tmp}/audit-trivy-err.$$"
trap 'rm -f "$_REP" "$_ERR"' EXIT

# trivy_json <image> [--sans-exceptions] — rapport JSON sur stdout.
#
# Le fichier d'exceptions est monté depuis le dépôt. `--sans-exceptions` le
# remplace par un fichier vide : c'est ce que joue l'auto-test pour vérifier que
# les vulnérabilités masquées sont bien encore VUES, et seulement TUES.
# ⚠️ LE SOCKET DU DÉMON EST INDISPENSABLE POUR LES IMAGES CONSTRUITES LOCALEMENT.
# Trivy tourne lui-même dans un conteneur : sans le socket, il ne voit que le
# registre distant. Une image tirée (`postgres:16-alpine`) se scanne donc très
# bien, et une image que TU as construite échoue sur :
#   « unable to find the specified image … in [docker containerd podman remote] »
# suivi d'un `UNAUTHORIZED` sur Docker Hub — c'est-à-dire précisément l'image la
# plus importante à auditer. Mesuré.
_SOCK=""
docker_sh "test -S /var/run/docker.sock" >/dev/null 2>&1 &&
  _SOCK="-v /var/run/docker.sock:/var/run/docker.sock"

trivy_json() {
  _ign="-v $(chemin_depot)/$EXCEPTIONS:/exceptions.yaml:ro"
  [ -f "$EXCEPTIONS" ] || _ign="-v /dev/null:/exceptions.yaml:ro"
  [ "$2" = "--sans-exceptions" ] && _ign="-v /dev/null:/exceptions.yaml:ro"
  docker_sh "docker run --rm -v audit-trivy-cache:/root/.cache/trivy $_SOCK $_ign $TRIVY_IMG \
    image --quiet --format json --scanners vuln --ignorefile /exceptions.yaml $1" 2>"$_ERR"
}

# resume <json> — « graves_corrigeables total_corrigeables total os detail exemples ».
# Sort en ERREUR si le rapport est inexploitable — un audit qui ne sait pas s'il
# a scanné quoi que ce soit doit se taire, pas rassurer.
#
# ⚠️ LE SEUIL D'ÉCHEC EST « CRITICAL/HIGH AVEC UN CORRECTIF PUBLIÉ », et c'est
# une DÉCISION, pas une évidence. Une image de base porte en permanence des CVE
# sans correctif amont : échouer dessus rendrait ce script rouge pour toujours,
# donc ignoré — ce qui revient à ne pas l'avoir. Une CVE corrigée en amont, elle,
# est une ACTION : reconstruire ou remonter l'image.
#
# Les non-corrigeables ne sont pas TUES pour autant : elles sont comptées et
# affichées. Un seuil qui ferait disparaître ce qu'il n'exige pas de traiter
# serait un repli qui détruit l'information d'absence.
resume() {
  "$PY" - "$1" <<'PYEOF'
import io, json, sys
try:
    d = json.load(io.open(sys.argv[1], encoding="utf-8"))
except Exception as exc:
    sys.stderr.write("rapport trivy illisible : %s\n" % exc)
    sys.exit(2)
# ⚠️ Le marqueur de validité est `ArtifactName`, PAS `Results`. Trivy omet
# purement et simplement `Results` quand il n'a rien trouvé — c'est le cas de
# l'image témoin `hello-world`, qui n'a aucun gestionnaire de paquets. Exiger
# `Results` confondait « rien trouvé » et « rapport illisible », et faisait
# rendre INCOMPLET sur un scan parfaitement réussi.
if not isinstance(d, dict) or "ArtifactName" not in d:
    sys.stderr.write("rapport trivy inattendu (pas de cle ArtifactName)\n")
    sys.exit(2)

graves = {"CRITICAL", "HIGH"}
total = corrigeables = graves_corrigeables = 0
par_gravite, exemples, fichiers = {}, [], {}
for res in d.get("Results") or []:
    for v in res.get("Vulnerabilities") or []:
        sev = v.get("Severity", "UNKNOWN")
        par_gravite[sev] = par_gravite.get(sev, 0) + 1
        total += 1
        if v.get("FixedVersion"):
            corrigeables += 1
            if sev in graves:
                graves_corrigeables += 1
                # « Dans quel fichier ? » est la PREMIÈRE question à poser :
                # quinze CVE dans quinze paquets et quinze CVE dans un seul
                # binaire ne posent pas la même question d'atteignabilité.
                ou = res.get("Target", "?")
                fichiers[ou] = fichiers.get(ou, 0) + 1
                if len(exemples) < 5:
                    # ASCII pur : la sortie standard de Python sous Windows est
                    # en cp1252, qui ne sait pas encoder « → » et lève une
                    # UnicodeEncodeError au milieu du rapport.
                    exemples.append("%s %s %s->%s (%s)" % (
                        sev, v.get("VulnerabilityID", "?"), v.get("InstalledVersion", "?"),
                        v.get("FixedVersion", "?"), v.get("PkgName", "?")))

os_info = (d.get("Metadata") or {}).get("OS") or {}
print("%d\t%d\t%d\t%s\t%s\t%s\t%s" % (
    graves_corrigeables, corrigeables, total,
    "%s %s" % (os_info.get("Family", "?"), os_info.get("Name", "?")),
    " ".join("%s=%d" % (k, par_gravite[k]) for k in
             ("CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN") if k in par_gravite),
    " | ".join(exemples),
    " ; ".join("%s x%d" % (k, n) for k, n in sorted(fichiers.items(), key=lambda x: -x[1])[:3])))
PYEOF
}

# --- Auto-test : cet audit sait-il REFUSER ? ----------------------------------
# TROIS témoins, pas deux.
if [ "$1" = "--self-test" ]; then
  titre "Auto-test — l'audit d'image sait-il signaler une image vulnérable ?"
  verifie_docker "SC-IMG.0"
  autotest_socle || exit "$RC_ECHEC"

  # (1) Une image qui DOIT crier. `alpine:3.10` est en fin de vie depuis 2021 :
  # elle porte forcément des CVE. Épinglée à dessein — un témoin dont le
  # résultat change tout seul ne prouve rien de stable. ~3 Mo.
  printf '  %salpine:3.10 (fin de vie) — doit crier…%s\n' "$C_DIM" "$C_OFF"
  trivy_json alpine:3.10 > "$_REP"
  if ! _r=$(resume "$_REP"); then
    skip "SC-IMG.1" "rapport trivy exploitable — sortie illisible"
    cat "$_ERR" >&2; bilan; exit $?
  fi
  # On mesure le champ qui DÉCIDE (CRITICAL/HIGH corrigeables), pas le total.
  # Un total non nul prouverait seulement que du JSON est revenu ; c'est le
  # calcul du seuil qui rend le verdict de l'audit réel, donc c'est lui qu'il
  # faut voir se déclencher.
  attend_au_moins "SC-IMG.1" "une image obsolète franchit le seuil" "1" \
    "$(printf '%s' "$_r" | cut -f1)"

  # (2) Une image qui DOIT se taire. `hello-world` n'a ni système de fichiers ni
  # gestionnaire de paquets : un scanner honnête n'y trouve rien. Sans ce second
  # témoin, « trouve toujours quelque chose » satisferait le premier.
  printf '  %shello-world (sans paquets) — doit se taire…%s\n' "$C_DIM" "$C_OFF"
  trivy_json hello-world > "$_REP"
  if ! _r=$(resume "$_REP"); then
    skip "SC-IMG.2" "rapport trivy exploitable — sortie illisible"
    cat "$_ERR" >&2; bilan; exit $?
  fi
  attend_egal "SC-IMG.2" "une image sans paquets ne déclenche rien" "0" \
    "$(printf '%s' "$_r" | cut -f3)"

  # (3) Le fichier d'exceptions TAIT-il, ou AVEUGLE-t-il ? La différence est
  # toute sa valeur. On rejoue une image RÉELLE DU PROJET avec les exceptions
  # neutralisées, et on exige que ce qu'elles masquent réapparaisse.
  #
  # Sans ce scénario, une exception trop large — un `id` sans `paths`, un chemin
  # élargi par mégarde — rendrait l'audit vert sur une image réellement
  # vulnérable, et rien ne le dirait. L'audit réel ne peut pas le voir : son
  # résultat attendu EST le silence.
  _NB_EXC=0
  [ -f "$EXCEPTIONS" ] && _NB_EXC=$(grep -c '^  - id:' "$EXCEPTIONS" 2>/dev/null || echo 0)
  if [ "${_NB_EXC:-0}" -eq 0 ]; then
    # Absence ÉTABLIE : sans exception déclarée, rien ne peut être masqué.
    sans_objet "SC-IMG.4" "les exceptions taisent sans aveugler — aucune exception déclarée, rien ne peut être masqué"
  elif [ -z "$COMPOSES" ]; then
    skip "SC-IMG.4" "les exceptions taisent sans aveugler — aucune image du projet à rejouer"
  else
    _img1=$(for _c in $COMPOSES; do images_du_compose "$_c"; done | head -1)
    printf '  %s%s sans exceptions (%s déclarées) — doit crier…%s\n' \
      "$C_DIM" "$_img1" "$_NB_EXC" "$C_OFF"
    trivy_json "$_img1" --sans-exceptions > "$_REP"
    if ! _r=$(resume "$_REP"); then
      skip "SC-IMG.4" "rapport trivy exploitable — sortie illisible"
      cat "$_ERR" >&2; bilan; exit $?
    fi
    attend_au_moins "SC-IMG.4" "les exceptions taisent sans aveugler" "1" \
      "$(printf '%s' "$_r" | cut -f1)"
  fi

  bilan; exit $?
fi

# --- Audit réel ---------------------------------------------------------------
titre "Images de conteneur — vulnérabilités connues (trivy)"
verifie_docker "SC-IMG.0"

if [ -z "$COMPOSES" ]; then
  skip "SC-IMG.3" "fichier de composition lisible — aucun trouvé (définir AUDIT_COMPOSE)"
  bilan; exit $?
fi
printf '  %scomposes audités : %s%s\n' \
  "$C_DIM" "$(printf '%s' "$COMPOSES" | tr '\n' ' ')" "$C_OFF"
[ -f "$EXCEPTIONS" ] || printf '  %saucun %s — aucune vulnérabilité n'\''est acceptée%s\n' \
  "$C_DIM" "$EXCEPTIONS" "$C_OFF"

# image_locale_du_service <service> — les images construites localement qui
# correspondent à ce service. `docker compose` les nomme `<projet>-<service>`.
image_locale_du_service() {
  docker_sh "docker images --format '{{.Repository}}:{{.Tag}}'" 2>/dev/null | sans_cr |
    grep -E "(^|[-_/])$1:" | grep -v ':<none>$' | sort -u
}

_ECHECS=0

# audite <référence> <libellé de provenance>
audite() {
  _ref="$1"; _prov="$2"
  trivy_json "$_ref" > "$_REP"
  if ! _r=$(resume "$_REP"); then
    skip "SC-IMG.3" "$_ref — rapport trivy illisible"
    cat "$_ERR" >&2
    return
  fi
  _graves=$(printf '%s' "$_r" | cut -f1)
  _corr=$(printf   '%s' "$_r" | cut -f2)
  _total=$(printf  '%s' "$_r" | cut -f3)
  _os=$(printf     '%s' "$_r" | cut -f4)
  _detail=$(printf '%s' "$_r" | cut -f5)
  _exemples=$(printf '%s' "$_r" | cut -f6)
  _ou=$(printf     '%s' "$_r" | cut -f7)

  printf '  %s%s [%s] — %s — %s (%s corrigeables sur %s)%s\n' \
    "$C_DIM" "$_ref" "$_prov" "$_os" "$_detail" "$_corr" "$_total" "$C_OFF"

  if [ "${_graves:-0}" -gt 0 ]; then
    ko "SC-IMG.3" "$_ref — $_graves CRITICAL/HIGH avec un correctif publié" \
      "0 grave corrigeable" "$_graves"
    [ -n "$_exemples" ] && printf '        %s\n' "$_exemples"
    [ -n "$_ou" ] && printf '        concentrées dans : %s\n' "$_ou"
    _ECHECS=$((_ECHECS + 1))
  else
    ok "SC-IMG.3" "$_ref — aucune CRITICAL/HIGH corrigeable"
  fi
}

# La liste des services passe par un FICHIER, pas par un tube : un `while` de
# pipeline tourne dans un sous-shell et y perdrait `_ECHECS` et les compteurs de
# verdict — le script afficherait des FAIL en annonçant « 0 échec ».
_SVC="${TMPDIR:-/tmp}/audit-svc.$$"
: > "$_SVC"
for _c in $COMPOSES; do
  services_du_compose "$_c" | sed "s|^|$_c\t|" >> "$_SVC"
done

if [ ! -s "$_SVC" ]; then
  skip "SC-IMG.3" "services extraits des composes — aucun trouvé, la lecture a échoué"
  rm -f "$_SVC"; bilan; exit $?
fi

_VUES=""
while IFS="$(printf '\t')" read -r _cmp _type _svc _a _b; do
  case "$_type" in
    image)
      # Dédoublonnage : la même image apparaît souvent dans plusieurs composes.
      case " $_VUES " in *" $_a "*) continue ;; esac
      _VUES="$_VUES $_a"
      audite "$_a" "$_cmp/$_svc"
      ;;
    build)
      # ⚠️ LE SERVICE CONSTRUIT EST CELUI QU'ON OUBLIE, ET C'EST LE TIEN.
      # Il porte ton code, tes dépendances de production et ton image de base.
      # Une version antérieure de ce script ne lisait que les clés `image:` et
      # taisait purement et simplement ce service — en imprimant la liste des
      # autres comme « images déclarées », ce qui se lit comme une couverture
      # complète.
      # Surcharge explicite : AUDIT_IMAGE_<service>, les caractères non
      # alphanumériques du nom de service devenant `_`.
      _var="AUDIT_IMAGE_$(printf '%s' "$_svc" | tr -c 'A-Za-z0-9' '_')"
      _locales=$(eval "printf '%s' \"\${$_var:-}\"")
      [ -n "$_locales" ] || _locales=$(image_locale_du_service "$_svc")
      _nb=$(printf '%s' "$_locales" | grep -c . || true)
      if [ "${_nb:-0}" -eq 1 ]; then
        case " $_VUES " in *" $_locales "*) continue ;; esac
        _VUES="$_VUES $_locales"
        audite "$_locales" "$_cmp/$_svc construit"
      elif [ "${_nb:-0}" -gt 1 ]; then
        # L'ambiguïté ne se tranche PAS en silence : choisir une étiquette au
        # hasard auditerait peut-être une image qui n'est plus celle qui tourne.
        skip "SC-IMG.5:$_svc" "image construite identifiée — $_nb candidates : $(printf '%s' "$_locales" | tr '\n' ' ')"
        printf '        Forcer avec : AUDIT_IMAGE_%s=<référence>\n' "$_svc"
      else
        # Repli : auditer les images de BASE du Dockerfile. C'est déjà le socle
        # système — mais ça ne couvre PAS les paquets que le Dockerfile
        # installe, et il faut donc le dire, pas le taire.
        _df="$_a/${_b:-Dockerfile}"
        [ -f "$_df" ] || _df="$_a"
        _bases=$(bases_du_dockerfile "$_df" 2>/dev/null)
        if [ -z "$_bases" ]; then
          skip "SC-IMG.5:$_svc" "image du service construit — ni image locale, ni Dockerfile lisible ($_df)"
        else
          skip "SC-IMG.5:$_svc" "image construite auditée — absente localement, seules ses BASES le sont"
          printf '        La construire (`docker compose build %s`) pour couvrir\n' "$_svc"
          printf '        les paquets installés par le Dockerfile, qui échappent ici.\n'
          for _base in $_bases; do
            case " $_VUES " in *" $_base "*) continue ;; esac
            _VUES="$_VUES $_base"
            audite "$_base" "$_cmp/$_svc base"
          done
        fi
      fi
      ;;
  esac
done < "$_SVC"
rm -f "$_SVC"

if [ "$_ECHECS" -gt 0 ]; then
  printf '\n  %sDes images embarquent des failles graves déjà corrigées en amont.%s\n' "$C_KO" "$C_OFF"
  printf '  ⚠️ AVANT D'\''AGIR, deux mesures — la conclusion évidente est souvent fausse :\n'
  printf '    1. le correctif est-il LIVRÉ par une image ? Comparer les étiquettes et\n'
  printf '       les variantes. « Corrigeable » veut dire « le correctif existe en amont »,\n'
  printf '       pas « une image que tu peux utiliser le porte ».\n'
  printf '    2. le code est-il ATTEINT ? Regarder la colonne « concentrées dans » :\n'
  printf '       un lot entier dans un seul binaire auxiliaire ne pose pas la même\n'
  printf '       question que le même lot réparti sur quinze paquets.\n'
  printf '  Puis, dans l'\''ordre : remonter l'\''étiquette ; dériver l'\''image ; ou\n'
  printf '  ACCEPTER dans %s — borné à un chemin, justifié, et DATÉ.\n' "$EXCEPTIONS"
fi

bilan
exit $?
