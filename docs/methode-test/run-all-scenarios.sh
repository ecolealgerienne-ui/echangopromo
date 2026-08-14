#!/usr/bin/env bash
#
# Rejoue TOUS les bancs, et dit lesquels passent — squelette (étage 3).
#
# ── Pourquoi ce lanceur ─────────────────────────────────────────────────────
#
# Les bancs s'accumulent un par un, et personne ne les rejoue tous : chacun est
# lancé le jour où il est écrit, puis oublié. Or ils partagent une base et une
# infrastructure — un lot qui casse l'un casse souvent les autres, et on ne le
# voit qu'au prochain passage manuel.
#
# ⚠️ **Il s'arrête à `set +e`, délibérément** (mode M10 appliqué au lot). Un
# `set -e` global sortirait au premier échec, donc on ne saurait jamais si les
# suivants passent — et c'est précisément l'information qu'on cherche quand on
# rejoue une suite. Chaque banc est isolé, son code de sortie relevé, et le
# tableau final dit tout.
#
# ── Ce qu'il ne fait pas ────────────────────────────────────────────────────
#
# Il ne relance ni l'analyse statique, ni les tests unitaires, ni les
# vérificateurs de synchronisation : ce sont des contrôles qui ne demandent
# aucune infrastructure, et les mêler ici allongerait la boucle sans rien
# apprendre sur les bancs.
#
# ⚠️ Conséquence assumée : **il n'existe pas de commande unique « tout est
# vert »**. C'est une limite connue de la méthode, pas un oubli.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/run-all-scenarios.sh
#
#   ONLY=motif    ne joue que les bancs dont le nom contient `motif`
#   PACE=65       secondes de pause entre deux bancs (0 pour enchaîner)
#   LOGDIR=/tmp/… où écrire les journaux

set -uo pipefail   # PAS de `-e` : voir l'en-tête.

ONLY="${ONLY:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
LOGDIR="${LOGDIR:-/tmp/echango-bancs}"
mkdir -p "$LOGDIR"

# ─────────────────────────────────────────────────────────────────────────────
# À ADAPTER — l'ordre n'est pas indifférent, et chaque entrée dit pourquoi
# ─────────────────────────────────────────────────────────────────────────────
#
# Trois principes d'ordonnancement, dans cet ordre de priorité :
#
#   1. **Ce qui n'écrit rien d'abord.** Un banc qui ne fait qu'appeler des
#      routes qui doivent refuser ne peut pas salir le décor des suivants — et
#      un échec s'y lit sans avoir à démêler ce que les autres ont laissé.
#   2. **Les non-régressions du socle ensuite.** Si la brique fondamentale est
#      cassée, tout le reste échouera pour la même raison et le tableau serait
#      illisible.
#   3. **Ce qui perturbe l'infrastructure en dernier.** Un banc qui arrête un
#      service ferait échouer tous ceux qui tournent pendant ce temps.
#
BANCS=(
  # N'écrit rien : n'appelle que des routes qui doivent refuser, avec des
  # identifiants inexistants. Placé en tête pour cette raison.
  # ⚠️ Consomme du débit : ~3 sondes par route, plusieurs minutes.
  test-frontiere-http

  # ⚠️ ÉCRIT ET SUPPRIME — et ce commentaire disait le contraire jusqu'au
  # 2026-08-13. `test-appartenance` ne touchait à rien parce que ses sondes
  # étaient toutes refusées ; `test-portee-agent` prouve l'inverse (l'agent est
  # global), donc elles passent : suspendre, réinitialiser un PIN, supprimer.
  # Il crée son propre commerçant et l'efface en dernière sonde, mais ce n'est
  # plus un banc en lecture seule.
  test-portee-agent

  # À ADAPTER : les bancs métier, un par règle qui a DÉJÀ produit un défaut.
  # Chacun porte en tête ce qu'il éprouve ET le défaut qui l'a fait naître.
  # test-plafond-promos
  # test-fenetre-signalement
  # test-visibilite-rayon

  # ⚠️ En dernier : perturbe l'infrastructure (arrêt/redémarrage d'un service).
  # test-resilience-degradee
)

noms=(); codes=(); notes=()

for b in "${BANCS[@]}"; do
  [ -z "$ONLY" ] || case "$b" in *"$ONLY"*) ;; *) continue ;; esac

  if [ ! -f "$HERE/$b.sh" ]; then
    noms+=("$b"); codes+=(-1); notes+=("absent"); continue
  fi

  # ⚠️ **Temporisation entre bancs, activée par défaut** (mode M9).
  #
  # Les endpoints d'authentification sont plafonnés. Enchaînés sans pause, les
  # bancs se refusent mutuellement l'accès — et le refus arrive déguisé en
  # « identifiants incorrects », ce qui envoie chercher un bug
  # d'authentification, voire supprimer des lignes en base, pour un problème
  # qui se résout en attendant.
  #
  # Elle ne règle PAS un éventuel plafond HORAIRE d'inscription : le tableau
  # final le nomme plutôt que de laisser chercher.
  if [ "${#noms[@]}" -gt 0 ] && [ "${PACE:-65}" -gt 0 ]; then
    echo "   (pause ${PACE:-65}s — plafond de connexion)"
    sleep "${PACE:-65}"
  fi

  printf '\n════ %s ════\n' "$b"
  # ⚠️ Journal dans un fichier, et code relevé JUSTE APRÈS (mode M10). Un
  # `bash … | tail` rendrait le code de `tail`, donc toujours 0.
  bash "$HERE/$b.sh" >"$LOGDIR/$b.log" 2>&1
  code=$?

  # Le plafond n'est pas un échec métier : le nommer évite de chercher un bug
  # dans le code pendant une heure.
  note=""
  if [ "$code" -ne 0 ] && grep -qi 'throttl\|too many requests\|HTTP 429' "$LOGDIR/$b.log" 2>/dev/null; then
    note="plafond de requêtes (429) — rejouer plus tard"
  fi

  noms+=("$b"); codes+=("$code"); notes+=("$note")
  if [ "$code" -eq 0 ]; then
    echo "✅ $b"
  else
    echo "❌ $b (code $code)${note:+ — $note}"
    tail -6 "$LOGDIR/$b.log" | sed 's/^/   /'
  fi
done

echo
echo "════════════════════════════════════════════════════════════════"
ok=0; ko=0; absents=0
for i in "${!noms[@]}"; do
  case "${codes[$i]}" in
    0)  printf '  ✅ %-34s\n' "${noms[$i]}"; ok=$((ok+1)) ;;
    -1) printf '  ·  %-34s script absent\n' "${noms[$i]}"; absents=$((absents+1)) ;;
    *)  printf '  ❌ %-34s code %s %s\n' "${noms[$i]}" "${codes[$i]}" "${notes[$i]}"; ko=$((ko+1)) ;;
  esac
done
echo "════════════════════════════════════════════════════════════════"
echo "  $ok passés, $ko échoués, $absents absents — journaux dans $LOGDIR"

# ⚠️ Les bancs absents ne font PAS échouer le lot, mais ils sont COMPTÉS et
# affichés : un banc supprimé qui disparaîtrait du tableau serait une baisse de
# couverture silencieuse (mode M11).
[ "$ko" -eq 0 ]
