#!/usr/bin/env bash
#
# Banc du journal d'audit — une action tracée laisse-t-elle vraiment une trace ?
#
# `AuditLogModule` est le cas fondateur de la règle 11 : il existait, bien
# conçu, depuis le premier commit — et n'a jamais tracé une seule action. Un
# module non branché ne produit aucune erreur, il produit une fausse impression
# de couverture.
#
# D'où le seul contrôle qui compte : faire l'action, puis regarder si elle est
# dans le journal. Le détail et l'auto-test sont dans `lib/audit_log.py`.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./scripts/provision-decor.sh     # pose admin, commerçant
#   # … coller le bloc export imprimé, attendre une minute …
#   ./scripts/test-admin-audit-log.sh
#
# ⚠️ Ce banc ÉCRIT : il suspend puis réactive le commerçant du décor. L'état est
# restauré — mais si le banc s'interrompt entre les deux, le commerçant reste
# suspendu. Ne pas le lancer contre une base qui n'est pas de test.

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
"$PY" "$HERE/lib/audit_log.py" --self-test || {
  echo "❌ l'auto-test échoue : le banc lui-même est en cause."
  exit 2
}

echo
exec "$PY" "$HERE/lib/audit_log.py" "$@"
