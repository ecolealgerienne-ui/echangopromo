#!/usr/bin/env bash
#
# Lanceur d'ensemble — enchaîne les bancs et rend UN tableau.
#
# ── Pourquoi il n'existait pas, et pourquoi il manquait ─────────────────────
#
# 45 bancs, et rien qui les enchaîne : personne ne pouvait dire « tout est vert »
# avant un déploiement. Chacun se lançait à la main, donc chacun se lançait
# quand on y pensait — et ce qu'on ne lance pas ne peut pas échouer.
#
# ── ⚠️ Ce qui est SAUTÉ est affiché, jamais tu ─────────────────────────────
#
# Un contrôle silencieusement sauté est le défaut fondateur de la règle 28 : le
# tableau final compte les sauts à part et les nomme un par un, avec leur
# raison. Un lot « tout vert » qui aurait discrètement omis six bancs vaudrait
# moins que pas de lot du tout.
#
# ── ⚠️ La pause entre bancs n'est pas du confort ───────────────────────────
#
# Les seaux de débit sont partagés par IP : 60/min global, 20/min sur les
# écritures, 5/min sur l'inscription et le signalement. Enchaînés sans pause,
# les bancs se refusent mutuellement — et un 429 se déguise en « identifiants
# incorrects » ou en refus métier. On paie donc 60 s entre chaque, et le lot
# dure environ trois quarts d'heure. C'est le prix d'un verdict qui veut dire
# quelque chose ; `PAUSE_SECONDS` permet de le régler en connaissance de cause.
#
# ── ⚠️ Ce lot peut révéler des interférences qu'un lancement isolé ne voit pas
#
# Les bancs écrivent dans le même décor. Certains créent des promos, d'autres
# suspendent des commerçants, un autre change un plafond puis le restaure. Une
# valeur de référence lue trop tôt décrivait un état disparu — c'est ce qui
# avait fait échouer six bancs le 2026-08-05. Si un banc échoue ici mais passe
# seul, ce n'est PAS un faux positif à écarter : c'est une mesure prise trop
# loin de son geste, et c'est un vrai défaut du banc.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh    # … coller le bloc export …
#   ATTENDU_LAT=34.6703 ATTENDU_LNG=3.2630 ./scripts/test-tout.sh
#
#   PAUSE_SECONDS=20 ./scripts/test-tout.sh      # plus rapide, plus risqué
#   SEULEMENT="client-* defaut-client" ./scripts/test-tout.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"
cd "$RACINE" || exit 2

PAUSE_SECONDS="${PAUSE_SECONDS:-60}"
API_URL="${API_URL:-http://localhost:3000}"
export API_URL

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
  echo "❌ python3 ou python requis — l'absence de verdict n'est pas un verdict."
  exit 2; }
PY=$(command -v python3 || command -v python)
export PYTHONIOENCODING=utf-8

# ── Les identifiants du décor, exigés d'un bloc ────────────────────────────
#
# ⚠️ Vérifiés AVANT le premier banc, pas au fil de l'eau : découvrir au
# vingtième que `COMMERCANT_PIN` manque aurait coûté vingt minutes pour rien.
MANQUANTS=""
for v in ADMIN_EMAIL ADMIN_PASSWORD AGENT_EMAIL AGENT_PASSWORD \
         AGENT_B_EMAIL AGENT_B_PASSWORD COMMERCANT_TEL COMMERCANT_PIN \
         COMMERCANT_ID; do
  eval "val=\${$v:-}"
  [ -n "$val" ] || MANQUANTS="$MANQUANTS $v"
done
if [ -n "$MANQUANTS" ]; then
  echo "❌ identifiants du décor absents :$MANQUANTS"
  echo "   Lancer ./scripts/provision-decor.sh et coller son bloc export."
  echo "   ATTENDU_LAT/ATTENDU_LNG se déclarent à la main — le point que CET"
  echo "   environnement est censé servir (pilote : 34.6703 / 3.2630)."
  exit 2
fi

# ── Ce que ce lot NE lance PAS, et pourquoi ────────────────────────────────
#
# Nommé ici plutôt que simplement absent de la liste : une exclusion non écrite
# est indiscernable d'un oubli.
declare -A EXCLUS=(
  [parcours-ecran]="exige l'émulateur, et flutter drive DÉSINSTALLE l'app à la fin"
  [perf-carte]="exige l'émulateur, en mode --profile"
)

# ⚠️ Ordre délibéré : les bancs en LECTURE SEULE d'abord, pour qu'ils mesurent
# un décor intact ; les bancs qui écrivent ensuite ; ceux qui suppriment ou
# suspendent des comptes en dernier.
BANCS=(
  # — lecture seule —
  defaut-client ville-client filtre-categorie client-carte client-fiche
  client-applinks auth-login perf plan-sql
  # — écritures bornées —
  frontiere-http frontiere-admin revocation-jwt admin-audit-log admin-agents
  admin-dashboard agent-creation agent-promo client-liste client-rayon
  client-highlight admin-highlight storage-upload commercant-dashboard
  commercant-profil commercant-b position-publication promo-cycle
  plafond-promos plafond-admin recherche-parc tournee-agent portee-agent
  journal-agent absences-commune
  # — modération et signalements (seaux stricts) —
  abus-signalement file-moderation moderation-course admin-moderation
  notifications registre
  # — destructifs : suppriment ou suspendent des comptes —
  sortie-agent commercant-autosuppression cycle-commercant
)

SEULEMENT="${SEULEMENT:-}"

echo "══════════════════════════════════════════════════════════════════════"
echo "  Lot complet — $API_URL · pause ${PAUSE_SECONDS}s entre bancs"
echo "══════════════════════════════════════════════════════════════════════"
echo "  ${#BANCS[@]} bancs à lancer, ${#EXCLUS[@]} exclus (détaillés à la fin)"
echo "  durée attendue : ~$(( (${#BANCS[@]} * PAUSE_SECONDS) / 60 )) min de pauses,"
echo "  plus le temps d'exécution."
echo

RESULTATS=()
NB_OK=0; NB_ECHEC=0; NB_NONCONCLUANT=0; NB_SAUTE=0
PREMIER=1

for b in "${BANCS[@]}"; do
  if [ -n "$SEULEMENT" ]; then
    # shellcheck disable=SC2254
    garder=0
    for motif in $SEULEMENT; do
      case "$b" in $motif) garder=1 ;; esac
    done
    [ "$garder" = "1" ] || continue
  fi

  if [ ! -x "$HERE/test-$b.sh" ]; then
    RESULTATS+=("SAUTE|$b|enveloppe absente ou non exécutable")
    NB_SAUTE=$((NB_SAUTE + 1))
    continue
  fi

  [ "$PREMIER" = "1" ] || sleep "$PAUSE_SECONDS"
  PREMIER=0

  echo "── $b ──"
  SORTIE="$("$HERE/test-$b.sh" 2>&1)"
  CODE=$?

  # La dernière ligne de décompte, telle que chaque banc la rend.
  RESUME="$(echo "$SORTIE" | grep -E "^[0-9]+ contrôles?, " | tail -1)"

  if [ -z "$RESUME" ]; then
    # ⚠️ Un banc qui ne rend aucun décompte n'a pas conclu — qu'il ait rendu 0
    # ou non. Le compter « ok » sur son seul code de sortie est le défaut que
    # ce dépôt a payé le 2026-08-04 (un harnais jugeant sur un code de sortie).
    PREMIERE_ERREUR="$(echo "$SORTIE" | grep -E "^❌" | head -1)"
    RESULTATS+=("SAUTE|$b|${PREMIERE_ERREUR:-aucun décompte rendu (code $CODE)}")
    NB_SAUTE=$((NB_SAUTE + 1))
    echo "  ⚠️  aucun décompte — ${PREMIERE_ERREUR:-code $CODE}"
    continue
  fi

  ECHECS="$(echo "$RESUME" | sed -E 's/.*, ([0-9]+) échec.*/\1/')"
  NONCONC="$(echo "$RESUME" | sed -E 's/.*, ([0-9]+) non concluant.*/\1/')"
  echo "  $RESUME"

  if [ "${ECHECS:-0}" != "0" ]; then
    RESULTATS+=("ECHEC|$b|$RESUME")
    NB_ECHEC=$((NB_ECHEC + 1))
  elif [ "${NONCONC:-0}" != "0" ]; then
    RESULTATS+=("NONCONC|$b|$RESUME")
    NB_NONCONCLUANT=$((NB_NONCONCLUANT + 1))
  else
    RESULTATS+=("OK|$b|$RESUME")
    NB_OK=$((NB_OK + 1))
  fi
done

echo
echo "══════════════════════════════════════════════════════════════════════"
echo "  Tableau final"
echo "══════════════════════════════════════════════════════════════════════"
for r in "${RESULTATS[@]}"; do
  etat="${r%%|*}"; reste="${r#*|}"; nom="${reste%%|*}"; detail="${reste#*|}"
  case "$etat" in
    OK)       printf "  ✅ %-26s %s\n" "$nom" "$detail" ;;
    ECHEC)    printf "  ❌ %-26s %s\n" "$nom" "$detail" ;;
    NONCONC)  printf "  ⚠️  %-26s %s\n" "$nom" "$detail" ;;
    SAUTE)    printf "  ⏭️  %-26s %s\n" "$nom" "$detail" ;;
  esac
done

if [ "${#EXCLUS[@]}" -gt 0 ]; then
  echo
  echo "  Exclus de ce lot, délibérément :"
  for k in "${!EXCLUS[@]}"; do
    printf "  ⏭️  %-26s %s\n" "$k" "${EXCLUS[$k]}"
  done
fi

echo
printf "  %d verts · %d échec(s) · %d non concluant(s) · %d sauté(s)\n" \
  "$NB_OK" "$NB_ECHEC" "$NB_NONCONCLUANT" "$NB_SAUTE"

# ⚠️ Un saut n'est pas une réussite, et un non-concluant non plus. Le seul
# code 0 possible est « tout a été lancé et tout a conclu au vert ».
if [ "$NB_ECHEC" != "0" ]; then
  echo "  ❌ des bancs ont ÉCHOUÉ."
  exit 1
fi
if [ "$NB_NONCONCLUANT" != "0" ] || [ "$NB_SAUTE" != "0" ]; then
  echo "  ⚠️  tout n'a pas conclu : ce n'est pas un lot vert."
  exit 1
fi
echo "  ✅ lot complet au vert."
exit 0
