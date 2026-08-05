#!/usr/bin/env bash
#
# Sauvegarde de la base — et la seule qui compte : celle qu'on a restaurée.
#
# Aucun mécanisme de sauvegarde n'existait depuis le début du projet. La dette
# a été identifiée le 2026-07-12 APRÈS UN INCIDENT DE CORRUPTION, et c'est le
# seul point du registre dont l'échec serait irréversible.
#
# ⚠️ Ce script RESTAURE chaque sauvegarde qu'il produit, dans une base jetable,
# et compare les lignes table par table. Un fichier qu'on n'a jamais restauré
# n'est pas une sauvegarde : le mode de défaillance classique n'est pas « le
# dump n'a pas tourné », c'est « il tourne tous les jours, exite 0, et produit
# un fichier tronqué » — découvert le jour où l'on en a besoin.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/backup-db.sh
#   GARDER=14 BACKUP_DIR=/mnt/sauvegardes ./scripts/backup-db.sh
#
# ── En tâche planifiée ──────────────────────────────────────────────────────
#
#   0 3 * * *  /home/amar/projects/echangopromo/scripts/backup-db.sh >> \
#              /var/log/echangopromo-backup.log 2>&1
#
# ⚠️ Le code de sortie est non nul si la sauvegarde ne se restaure pas : c'est
# lui qu'une supervision doit surveiller, pas la présence du fichier.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"

command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."; exit 2; }
command -v docker >/dev/null 2>&1 || {
  echo "❌ docker absent : pg_dump est pris DANS le conteneur, pour que les"
  echo "   versions client et serveur s'accordent par construction."; exit 2; }

cd "$RACINE" || exit 2

echo "── auto-test ──"
python3 "$HERE/lib/backup_db.py" --self-test || {
  echo "❌ l'auto-test échoue : le script lui-même est en cause."; exit 2; }

echo
exec python3 "$HERE/lib/backup_db.py" "$@"
