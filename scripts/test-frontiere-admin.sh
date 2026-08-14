#!/usr/bin/env bash
#
# Frontière admin — l'agent est-il refusé là où il doit l'être ?
#
# Neuf routes sont @Roles('admin') SEUL. Mesuré : toutes leurs écritures ne sont
# jamais exercées qu'avec un jeton ADMIN — aucun banc ne les attaque avec un
# jeton d'AGENT. Trois seulement ont un témoin négatif (GET /admin/agent, GET
# /admin/audit-log, PATCH plafond-promos). Un GET refusé ne prouve rien du POST
# d'à côté : la polarité est par route, et la route qu'on oublie est OUVERTE
# (règle 33).
#
# ⚠️ Les gardes SONT montées, je l'ai lu — et c'est précisément ce qu'on n'a pas
# le droit de conclure depuis le code : énumérer les routes protégées depuis leur
# garde fait rétrécir l'ensemble contrôlé avec ce qu'il contrôle.
#
# ⚠️ Ce banc n'écrit RIEN : les gardes NestJS s'exécutent avant les pipes, donc
# un corps vide fait ressortir l'admin en 400 VALIDATION_ERROR — preuve qu'il a
# franchi la garde — sans rien créer. Seule exception, jouée en dernier :
# POST /admin/me/revoke-token révoque pour de bon le jeton de l'admin.
#
# Le détail, les verdicts et l'auto-test sont dans `lib/frontiere_admin.py`.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-frontiere-admin.sh
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
SORTIE_AUTOTEST="$("$PY" "$HERE/lib/frontiere_admin.py" --self-test)" || {
  echo "$SORTIE_AUTOTEST"
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}
echo "$SORTIE_AUTOTEST"

# ⚠️ Un code de sortie 0 ne vaut rien ici : un fichier Python vide sort en 0.
echo "$SORTIE_AUTOTEST" | grep -q "^auto-test : [0-9]\+ cas, dont [0-9]\+ refus$" || {
  echo "❌ l'auto-test n'a annoncé aucun cas — module vide ou tronqué."
  exit 2; }

echo
exec "$PY" "$HERE/lib/frontiere_admin.py" "$@"
