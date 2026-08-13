#!/usr/bin/env bash
#
# Banc du journal d'audit côté agent — qui a fait quoi, et pas seulement quoi.
#
# Depuis le 2026-08-13, `CLAUDE.md` dit du journal qu'il « est devenu le seul
# contrepoids à la portée globale » de l'agent. Ce contrepoids n'était éprouvé
# pour personne d'autre que l'admin : `audit_log.py` agit en admin et n'assertent
# que `actorType == "admin"`.
#
# Trois mécanismes d'enregistrement distincts existent pour un agent
# (`PromoController.auditStaffWrite`, `ModerationService.record`, et onze appels
# en ligne dans `AdminController`) : une sonde par mécanisme, au minimum.
#
# Le détail, le témoin négatif et l'auto-test sont dans `lib/journal_agent.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh
#   # … coller le bloc export imprimé …
#   ./scripts/test-journal-agent.sh
#
# ⚠️ Il lui faut les DEUX agents du décor : la sonde qui compte le plus est
# l'attribution, et avec un seul agent « il trace » et « il trace toujours la
# même chose » sont indiscernables.
#
# ⚠️ Il ÉCRIT : il crée sa propre promo, la modifie, la masque et l'arrête. Il
# ne touche ni au commerçant du décor (la validation de registre qu'il rejoue
# est idempotente) ni à sa promo. Il laisse derrière lui une promo à lui,
# masquée et arrêtée — invisible de tous, dans aucune file.
#
# ⚠️ Il consomme 4 connexions (seau d'authentification, 50/min) et ~7 écritures
# (seau des écritures, 20/min — PARTAGÉ).

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
  echo "❌ python3 ou python requis — l'absence de verdict n'est pas un verdict."
  exit 2; }
PY=$(command -v python3 || command -v python)

# ⚠️ La console Windows est en cp1252 : sans ça, le moindre « ═ » fait planter
# le banc en UnicodeEncodeError, et un banc qui ne peut pas AFFICHER son verdict
# n'en rend aucun.
export PYTHONIOENCODING=utf-8

cd "$RACINE" || exit 2

echo "── auto-test du banc ──"
SORTIE_AUTOTEST="$("$PY" "$HERE/lib/journal_agent.py" --self-test)" || {
  echo "$SORTIE_AUTOTEST"
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}
echo "$SORTIE_AUTOTEST"

# ⚠️ Un code de sortie 0 ne vaut rien ici : un fichier Python vide sort en 0
# (défaut réel du 2026-08-12).
echo "$SORTIE_AUTOTEST" | grep -q "^auto-test : [0-9]\+ cas, dont [0-9]\+ refus$" || {
  echo "❌ l'auto-test n'a annoncé aucun cas — le module est vide, tronqué ou"
  echo "   n'exécute plus son auto-test."
  exit 2; }

echo
exec "$PY" "$HERE/lib/journal_agent.py" "$@"
