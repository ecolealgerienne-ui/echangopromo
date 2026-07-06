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

---

## Phase 2 — Revue statique OWASP Top 10 (code réel)

**Note méthodologique honnête** : la demande initiale citait un "OWASP Top
10:2025" avec des catégories précises (A03 Supply Chain, A10 Mishandling of
Exceptional Conditions, SSRF fusionné dans A01...). Je n'ai pas de
confirmation fiable qu'une révision 2025 du Top 10 a été officiellement
publiée par l'OWASP à la date de cet audit — je préfère le dire plutôt que
de présenter des catégories non vérifiées comme un standard confirmé.
L'analyse ci-dessous suit donc l'**OWASP Top 10:2021** (la révision
officielle confirmée la plus récente), en couvrant quand même les thèmes
cités (chaîne d'approvisionnement logicielle, gestion des erreurs, SSRF)
sous les catégories existantes.

### A01:2021 — Broken Access Control

[Statut] **Contrôlé, aucun nouveau problème.**

- IDOR agent→commerçant (finding historique `AUDIT_V0.md`) : `assertZoneMatches`
  est bien appelée dans `promo.controller.ts:84` et `:149` avant toute
  action agent sur une ressource commerçant — pas de méthode de garde
  orpheline (CLAUDE.md règle #1 respectée).
- Révocation JWT : `jwt-auth.guard.ts:42` compare `payload.tokenVersion` au
  `tokenVersion` actuel en base à chaque requête — un token volé devient
  inutilisable dès que le compte est révoqué, pas seulement à expiration.
- CORS : `main.ts:19-22` — `origin: false` par défaut (aucune origine
  autorisée) tant que `CORS_ORIGINS` n'est pas renseigné ; pas de wildcard
  `*` avec `credentials: true` (combinaison qui serait une vraie faille).
- SSRF : aucun endpoint ne récupère une URL fournie par le client
  (`AppLinksController.redirectToStore` redirige vers des URLs de
  configuration serveur `PLAY_STORE_URL`/`APP_STORE_URL`, jamais une URL
  utilisateur ; le paramètre `:id` de `GET /p/:id` n'est jamais lu). Aucune
  surface SSRF identifiée dans le code actuel.

### A02:2021 — Security Misconfiguration

[Statut] **1 problème réel trouvé, corrigé dans cette session.** 🟠 Élevé

**🔴 Rate limiting par IP potentiellement inopérant derrière Traefik — CORRIGÉ**
[Criticité] Élevé 🟠
[Outcome] **Fixed** — `app.set('trust proxy', 1)` ajouté dans `main.ts`
(commit de cette session). À déployer sur le VPS comme n'importe quel
changement de code (`git pull` + rebuild du conteneur `backend`).
[Preuve] `main.ts` ne contient aucun `app.set('trust proxy', ...)`.
Express, sans cette option, prend l'adresse IP du **socket TCP immédiat**
comme `req.ip` — derrière un reverse proxy (Traefik, sur le même réseau
Docker), c'est l'IP interne de Traefik, **identique pour toutes les
requêtes**, jamais la vraie IP du client mobile.
[Impact] `@nestjs/throttler` (utilisé pour tout le rate-limiting :
login PIN/mot de passe, `/commercant/claim`, `/report` — CLAUDE.md règles
#2/#7) s'appuie sur `req.ip` pour distinguer les clients. Si toutes les
requêtes arrivent avec la même IP apparente, **tous les utilisateurs
partagent le même compteur de rate-limit** : un attaquant qui sature la
limite (5 req/min sur les logins) peut faire bloquer temporairement tous
les autres utilisateurs légitimes (déni de service applicatif), et la
protection anti-brute-force perd son objectif d'isoler un attaquant précis.
[PoC résumé] Envoyer 6 requêtes rapides sur un endpoint `STRICT_THROTTLE`
depuis deux machines différentes derrière le même Traefik ; si la 2ᵉ
machine est bloquée après seulement quelques requêtes de la 1ʳᵉ, le
partage de compteur est confirmé.
[Correction] Dans `main.ts`, avant `app.listen()` :
```ts
app.set('trust proxy', 1); // fait confiance au 1er hop (Traefik) uniquement
```
`1` (pas `true`) est important : `true` ferait confiance à toute la chaîne
`X-Forwarded-For`, permettant à un client de la falsifier lui-même pour
usurper n'importe quelle IP et contourner le rate-limiting. `1` ne fait
confiance qu'au reverse proxy immédiat (Traefik), qui écrase déjà tout
`X-Forwarded-For` entrant côté client par la vraie IP (comportement
standard de Traefik).
[Références] CWE-290 (Authentication Bypass by Spoofing via IP), OWASP
A02:2021.

Autres points de cette catégorie, vérifiés sans problème :
- `JWT_SECRET` : `env.validation.ts` rejette au démarrage un secret vide,
  trivial (`change-me`/`secret`) ou < 32 caractères **en production**
  spécifiquement — fail-fast plutôt qu'un défaut silencieusement faible.
- `synchronize: false` figé (pas de bascule `NODE_ENV`), schéma
  entièrement piloté par migrations versionnées.
- Pas de `helmet` installé, mais les headers de sécurité observés en
  Phase 1 (HSTS, X-Frame-Options, etc.) sont posés par les middlewares
  Traefik (`security-headers@file`), pas par l'app elle-même — fonctionne
  aujourd'hui car Traefik est systématiquement devant, mais **aucune
  défense en profondeur côté NestJS** : si l'app était un jour exposée
  hors de Traefik (debug direct, changement d'infra), ces headers
  disparaîtraient sans que le code ne le remarque. Recommandation basse
  priorité : ajouter `helmet` côté NestJS en plus (redondant mais
  robuste aux changements d'infra futurs).
- `Cross-Origin-Resource-Policy` absent des headers observés — sans
  impact réel ici (API JSON pure, pas de ressources statiques
  cross-origin à protéger), mais à ajouter si des images/fichiers
  finissent par être servis directement par ce domaine plutôt que par S3.

### A03:2021 — Injection *(couvre aussi la chaîne d'approvisionnement logicielle, thème cité dans la demande initiale)*

[Statut] **Aucune injection trouvée ; 1 point process à noter.**

- Aucune requête SQL construite par concaténation de chaîne trouvée
  (`grep` sur `.query(\`` ne remonte que les migrations, DDL statique sans
  entrée utilisateur) — tout le code applicatif passe par le query builder
  / repository TypeORM (paramétré par construction).
- Aucun `eval`, `child_process`/`exec` dans le code applicatif.
- Pas de XSS applicable : API JSON pure, la seule page HTML servie
  (`AppLinksController`, page d'attente) ne reflète aucune entrée
  utilisateur.
- **Chaîne d'approvisionnement (process, pas une CVE précise)** : cette
  session a trouvé et corrigé un vrai désync `package-lock.json`/
  `package.json` (`typeorm` verrouillé sur `^1.0.0` inexistant vs
  `^0.3.20` déclaré) resté invisible en local (`npm install` tolère
  l'écart) et bloquant seulement au premier `npm ci` en prod (voir
  `docs/status_v0.md`, 2026-07-05). Recommandation : ajouter `npm ci`
  (pas `npm install`) à une étape CI si un pipeline est mis en place, pour
  détecter ce genre de désync avant le déploiement plutôt qu'au moment du
  build Docker de prod. `npm audit` n'a pas été exécuté dans cette session
  (nécessiterait un accès réseau vers le registre npm non disponible ici) —
  à lancer manuellement : `cd apps/backend && npm audit`.

### A04:2021 — Cryptographic Failures

[Statut] **Correct, 1 amélioration mineure suggérée.** 🟢

- Mots de passe/PIN hashés avec `bcrypt`, jamais en clair ni MD5/SHA1 non
  salé (`auth.service.ts`).
- `SALT_ROUNDS = 10` — valeur raisonnable mais `12` est la recommandation
  actuelle la plus courante pour bcrypt (coût de calcul qui double environ
  tous les +1) ; pas urgent, amélioration mineure à budget de calcul
  serveur constant.
- HSTS actif avec `preload` (Phase 1) — HTTP redirigé vers HTTPS par
  Traefik (`entrypoints=websecure`, confirmé dans `docker-compose.promo.yml`).
- TLS terminé par Traefik, pas par l'app — configuration TLS réelle (version,
  cipher suites) non vérifiable depuis ce sandbox (Phase 1) : à vérifier
  avec `https://www.ssllabs.com/ssltest/` ou `nmap --script ssl-enum-ciphers`
  depuis une machine avec connectivité normale.

### A05:2021 — Insecure Design

[Statut] **Correct.** 🟢 Plafond de 5 promos actives protégé par verrou
consultatif Postgres (`pg_advisory_xact_lock`) contre la race condition
déjà identifiée et corrigée (`AUDIT_V0.md`). Rate limiting présent sur
tous les endpoints sensibles (sous réserve du fix Phase A02 ci-dessus pour
qu'il soit réellement per-IP).

### A07:2021 — Identification and Authentication Failures

[Statut] **Correct pour ce profil d'app, avec dette déjà documentée.**

- Hashing bcrypt, révocation JWT par `tokenVersion`, rate-limiting sur les
  logins (sous réserve du fix `trust proxy`).
- Pas de MFA — dette déjà documentée comme non bloquante pour le pilote
  (`docs/status_v0.md`), acceptable pour un compte commerçant/agent à
  faible surface d'attaque (PIN + téléphone, pas de paiement en ligne).
- PIN 4-6 chiffres variable — dette déjà documentée, décision produit à
  trancher, pas un bug de sécurité en soi tant que le rate-limiting
  fonctionne réellement (cf. A02).

### A08:2021 — Software and Data Integrity Failures

[Statut] **Correct.** 🟢 Upload S3 via POST policy avec
`content-length-range` (5 Mo max) + vérification a posteriori des magic
bytes (`storage.service.ts:100-116`) — un `Content-Type` déclaré à la
signature n'engage à rien sur le contenu réel, la vérification après coup
comble ce point déjà identifié dans `AUDIT_V1.md`.

### A09:2021 — Security Logging and Monitoring Failures

[Statut] **Correct.** 🟢 `AuditLogModule` confirmé branché (appelé depuis
`admin.controller.ts`, `agent.controller.ts`, `moderation.service.ts` —
plus le module orphelin trouvé dans `AUDIT_V0.md`). `AllExceptionsFilter`
logue l'exception complète côté serveur (`logger.error(exception)`) mais
ne renvoie qu'un message générique au client (pas de stack trace exposée) —
bon équilibre observabilité/fuite d'information.

### A06:2021 / A10:2021 (Vulnerable Components / SSRF)

Voir A03 (chaîne d'approvisionnement) et A01 (SSRF) ci-dessus — ces deux
thèmes cités dans la demande initiale sont traités dans les catégories où
l'OWASP 2021 les classe réellement, pour éviter la confusion avec la
liste 2025 non confirmée.
