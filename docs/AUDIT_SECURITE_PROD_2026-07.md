# Audit de sécurité — production `promo.echango.com` (2026-07-06)

Audit mené après le premier déploiement VPS réussi (voir
`docs/status_v0.md`, entrées du 2026-07-05/06). Périmètre convenu avec
l'utilisateur : **revue statique du code backend + vérifications passives
en lecture seule** — pas de test actif (brute-force, injection, scan de
ports) contre l'instance de production, qui partage son VPS/Traefik avec
une autre stack (Vendure) en production. Méthodologie de référence :
OWASP Top 10 (catégories 2021, les plus stables/vérifiables), croisée avec
les audits déjà menés (`docs/AUDIT_V0.md`, `docs/AUDIT_V1.md`) pour éviter
de redécouvrir des points déjà traités.

Mené par phases, chaque phase committée séparément.

---

## Phase 1 — Reconnaissance passive

### Limite d'environnement à noter honnêtement

Les vérifications réseau depuis l'environnement d'exécution de cette
session (sandbox Claude Code) se sont révélées **non fiables** pour cet
audit :
- Le trafic HTTPS sortant passe par un proxy égress propre à
  l'environnement, qui **intercepte le TLS** — le certificat observé lors
  d'un `openssl s_client` est celui du proxy (`CN = Egress Gateway SDS
  Issuing CA`), pas celui du vrai site. Impossible de vérifier depuis ici
  la version TLS réelle, les cipher suites, ou le certificat effectivement
  présenté aux utilisateurs.
- La connectivité vers `promo.echango.com` s'est dégradée après quelques
  requêtes (`curl` renvoyant `000`, connexion refusée) — probablement une
  conséquence du rate-limiting Traefik/NestJS déclenché par les requêtes
  successives depuis la même IP de proxy, ou une instabilité du chemin
  réseau du sandbox lui-même.

**Conséquence** : les résultats de reconnaissance externe ci-dessous
s'appuient sur (a) la requête déjà exécutée **directement depuis le VPS**
par l'utilisateur (donnée fiable, chemin réseau réel), et (b) la revue du
code source (fiable à 100%, accès direct). Les points marqués *"à vérifier
par l'utilisateur"* nécessitent une commande à lancer depuis une machine
avec une connectivité normale (pas ce sandbox) — indiqué explicitement
plutôt que deviné.

### Résultat DNS

- `promo.echango.com` → `151.80.130.163` (résolution A confirmée, résolveur
  système du sandbox).
- MX / TXT (SPF, DMARC) / NS : **non vérifiable depuis cet environnement**
  (résolution DNS brute UDP/53 non disponible, seul le résolveur système
  local — utilisé pour l'A record ci-dessus — fonctionne). À vérifier
  manuellement : `dig TXT echango.com`, `dig TXT _dmarc.echango.com`, ou un
  outil en ligne (mxtoolbox.com, dnschecker.org).

### Headers HTTP (donnée réelle, capturée depuis le VPS par l'utilisateur)

```
HTTP/2 200
content-type: application/json; charset=utf-8
cross-origin-opener-policy: same-origin
strict-transport-security: max-age=31536000; includeSubDomains; preload
x-content-type-options: nosniff
x-frame-options: DENY
permissions-policy: camera=(), microphone=(), geolocation=(), payment=()
referrer-policy: strict-origin-when-cross-origin
x-xss-protection: 1; mode=block
x-ratelimit-limit: 60
x-ratelimit-remaining: 59
x-ratelimit-reset: 60
```

| Header | Statut | Commentaire |
|---|---|---|
| Strict-Transport-Security | ✅ | `max-age=31536000` (1 an), `includeSubDomains`, `preload` — excellent |
| X-Frame-Options | ✅ | `DENY` |
| X-Content-Type-Options | ✅ | `nosniff` |
| Referrer-Policy | ✅ | `strict-origin-when-cross-origin` |
| Permissions-Policy | ✅ | Désactive caméra/micro/géoloc/paiement — cohérent (API JSON pure, pas de page web) |
| Cross-Origin-Opener-Policy | ✅ | `same-origin` |
| Cross-Origin-Resource-Policy | ❌ manquant | absent des headers observés — voir recommandation Phase 2 |
| Content-Security-Policy | ⚠️ absent | pas d'impact ici (pas de page HTML servie, API JSON pure) — sans objet tant qu'aucun frontend web n'est ajouté |
| Server / X-Powered-By | ✅ | absents des headers observés — pas de fuite de version serveur |
| X-RateLimit-* | ✅ | présence confirmée d'un rate-limiting actif en prod (`@nestjs/throttler`, cohérent avec CLAUDE.md règle #2) |

Ces headers sont posés par NestJS (`helmet` ou équivalent) — **à confirmer
dans le code en Phase 2** plutôt que supposé ici.

### Chemins/fichiers exposés

**Non vérifié depuis ce sandbox** (connectivité dégradée après les
premières requêtes, cf. limite ci-dessus). À faire depuis le VPS ou une
machine normale — liste de commandes prête à copier-coller :

```bash
for p in / /robots.txt /sitemap.xml /.env /.env.production /.git/config \
         /.well-known/security.txt /package.json /Dockerfile; do
  echo -n "$p -> "
  curl -s -o /dev/null -w "%{http_code}\n" "https://promo.echango.com$p"
done
```

Attendu (d'après le code, `AppLinksController` + `PromoController` sont les
seules routes hors API mobile) : tout ce qui n'est pas une route NestJS
explicitement définie doit renvoyer `404` (géré par `AllExceptionsFilter`,
voir Phase 2) — un `200` sur `/.env`, `/.git/config` ou `/package.json`
serait une fuite critique à traiter immédiatement.
