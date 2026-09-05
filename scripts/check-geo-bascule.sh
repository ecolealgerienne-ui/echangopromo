#!/usr/bin/env bash
#
# La bascule du géocodage inverse vers echango-geo, éprouvée SANS monter tout
# le backend — on pilote directement `GeoClientService` compilé.
#
# ── Ce qu'il vérifie ─────────────────────────────────────────────────────
#
#   • une position connue est résolue en ville/wilaya (mapping city→ville,
#     province→wilaya) ;
#   • un point en mer rend { ville: null, wilaya: null } sans lever ;
#   • echango-geo injoignable → GeoUnavailableError (que `setPosition`
#     traduit en geocodageStatut = a_faire, sans casser la pose de position) ;
#   • `ping()` rend reachable:false sans lever quand echango-geo est absent.
#
# Ce que ce check NE couvre PAS : le passage par la route `/commercant/me/position`
# et l'export CRM — c'est `test-geo-bascule.sh` (backend + Postgres debout).
#
# ── Usage ────────────────────────────────────────────────────────────────
#
#   cd apps/backend && npm run build      # le check charge dist/
#   GEO_INTERNAL_TOKEN=... ./scripts/check-geo-bascule.sh
#
#   GEO_SERVICE_URL     instance echango-geo (défaut http://localhost:3000)
#   GEO_INTERNAL_TOKEN  jeton X-Internal-Token (obligatoire côté echango-geo)

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SVC="$HERE/../apps/backend/dist/common/geo/geo-client.service.js"

export GEO_SERVICE_URL="${GEO_SERVICE_URL:-http://localhost:3000}"
export GEO_INTERNAL_TOKEN="${GEO_INTERNAL_TOKEN:-}"

[ -f "$SVC" ] || { echo "❌ $SVC absent — lancer 'npm run build' dans apps/backend"; exit 2; }
[ -n "$GEO_INTERNAL_TOKEN" ] || { echo "❌ GEO_INTERNAL_TOKEN requis"; exit 2; }

echo "echango-geo : $GEO_SERVICE_URL"

SVC_PATH="$SVC" node -e '
const { GeoClientService } = require(process.env.SVC_PATH);
let ok = 0, ko = 0;
const t = (c, m) => { c ? (ok++, console.log("  ✅ " + m)) : (ko++, console.log("  ❌ " + m)); };
const config = { get: (k) => process.env[k] };

(async () => {
  const geo = new GeoClientService(config);

  const r = await geo.reverse(36.7538, 3.0588);
  t(!!r.ville, "position terrestre → ville : " + r.ville);
  t(!!r.wilaya, "  → wilaya : " + r.wilaya);

  const sea = await geo.reverse(30, -40);
  t(sea.ville === null && sea.wilaya === null, "point en mer → { ville: null, wilaya: null }, pas d’erreur");

  t((await geo.ping()).reachable === true, "ping → reachable:true");

  const dead = new GeoClientService({ get: (k) => k === "GEO_SERVICE_URL" ? "http://127.0.0.1:59998" : process.env[k] });
  try { await dead.reverse(36.75, 3.05); t(false, "panne : aurait dû lever"); }
  catch (e) { t(e.name === "GeoUnavailableError", "echango-geo injoignable → GeoUnavailableError"); }
  t((await dead.ping()).reachable === false, "panne ping → reachable:false (ne lève pas)");

  console.log("\n  " + ok + " ok, " + ko + " KO");
  process.exit(ko ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
'
