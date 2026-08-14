#!/usr/bin/env bash
#
# Banc de l'upload — taille, format réel, périmètre par rôle.
#
# L'upload n'avait jamais été éprouvé contre un vrai bucket, alors que MinIO
# tourne en local depuis le début. La sonde qui compte le plus envoie un
# fichier texte en le déclarant `image/jpeg` : un Content-Type déclaré
# n'engage à rien (règle 5), et c'est le comportement qu'aurait quelqu'un
# cherchant à déposer autre chose qu'une image dans un bucket public.
#
# Le détail et l'auto-test sont dans `lib/storage_upload.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh     # pose le commerçant
#   # … coller le bloc export imprimé, attendre une minute …
#   ./scripts/test-storage-upload.sh
#
# ⚠️ Ce banc ÉCRIT dans le bucket : un objet de 125 octets par passage, sous
# `promo-photos/<commercantId>/`. Il n'est rattaché à aucune promo et sera
# balayé par la purge de rétention. Ne pas le lancer contre un bucket de
# production.
#
# ⚠️ Il consomme 6 écritures sur le seau SENSITIVE_ACTION_THROTTLE (20/min,
# partagé) : ne pas l'enchaîner immédiatement après un autre banc écrivant.

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
"$PY" "$HERE/lib/storage_upload.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}

echo
exec "$PY" "$HERE/lib/storage_upload.py" "$@"
