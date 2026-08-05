#!/usr/bin/env bash
#
# Voir l'en-tête de `lib/registre.py`. Le registre est la preuve d'existence
# légale du commerce : c'est lui qui fait passer un compte de « inscrit » à
# « peut publier ».
#
# ⚠️ Ce banc couvre DEUX lignes de la matrice §6 —
# `test-commercant-registre` (dépôt) et `test-admin-registre` (décision).
# Les séparer aurait obligé chacun à reconstruire le décor de l'autre : un
# dépôt sans décision ne prouve rien, une décision sans dépôt n'a rien à
# décider. Les quatre routes concernées sont exercées ici.
#
#   ./scripts/provision-decor.sh   # … coller le bloc export, attendre 1 min …
#   ./scripts/test-registre.sh
#
# ⚠️ Ce banc ÉCRIT : il crée SON PROPRE commerçant, dépose un document, le fait
# valider et réinitialise son PIN. Il ne touche jamais à celui du décor.
#
# ⚠️ Il consomme 3 connexions sur le seau strict de 5/min.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$HERE/.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 absent — l'absence de verdict n'est pas un verdict."; exit 2; }
cd "$RACINE" || exit 2
echo "── auto-test du banc ──"
python3 "$HERE/lib/registre.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."; exit 2; }
echo
exec python3 "$HERE/lib/registre.py" "$@"
