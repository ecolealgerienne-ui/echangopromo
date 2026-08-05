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
# ⚠️ Et depuis le 2026-08-05, elle PART HORS SITE (étape 4). Les trois premières
# étapes ne couvrent que la corruption logique : un fichier posé à côté de la
# base disparaît avec le disque qui la porte. Le dump est chiffré localement,
# déposé dans `echango-private` en ACL privée, puis **redemandé en anonyme** —
# un objet qui répondrait 200 à ce moment-là est supprimé sur-le-champ et le
# lot échoue. `PutObject` rend 200 que l'objet soit privé ou public : sans ce
# contrôle, « l'envoi a réussi » ne veut rien dire.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/backup-db.sh
#   GARDER=14 BACKUP_DIR=/mnt/sauvegardes ./scripts/backup-db.sh
#
# ── Configuration de l'envoi ────────────────────────────────────────────────
#
# Dans ~/.echango-backup.env (voir scripts/backup.env.example), PAS dans le
# .env du backend : la phrase de passe n'a aucune raison d'entrer dans
# l'environnement du processus NestJS. Le fichier doit être en 600 — ce script
# REFUSE de lire une phrase de passe que tout le monde peut lire.
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

# ── Configuration de l'envoi hors site ──────────────────────────────────────
CONF="${BACKUP_ENV_FILE:-$HOME/.echango-backup.env}"
if [ -f "$CONF" ]; then
  # ⚠️ Un secret lisible par tous n'est pas un secret. On refuse plutôt que de
  # corriger en silence : `chmod` derrière le dos de l'utilisateur masquerait
  # le fait que le fichier a été exposé, peut-être depuis longtemps.
  PERM=$(stat -c '%a' "$CONF" 2>/dev/null || echo "???")
  case "$PERM" in
    600|400) ;;
    *) echo "❌ $CONF est en $PERM — il porte une phrase de passe."
       echo "   chmod 600 \"$CONF\" puis relancer."; exit 2 ;;
  esac
  set -a; . "$CONF"; set +a
else
  echo "ℹ️  $CONF absent — envoi hors site non configuré."
  echo "   Modèle : scripts/backup.env.example"
fi

echo "── auto-tests ──"
python3 "$HERE/lib/backup_db.py" --self-test || {
  echo "❌ l'auto-test échoue : le script lui-même est en cause."; exit 2; }
python3 "$HERE/lib/backup_upload.py" --self-test || {
  echo "❌ l'auto-test d'envoi échoue : le script lui-même est en cause."; exit 2; }

echo
exec python3 "$HERE/lib/backup_db.py" "$@"
