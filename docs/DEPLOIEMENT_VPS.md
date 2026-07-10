# Déploiement backend + DB sur le VPS

Procédure pour faire tourner le backend echango Promo dans
`/opt/echangopromo` sur le VPS, derrière le Traefik déjà en place pour
`echango.com` (stack Vendure/storefront, dépôt séparé). Pas d'automatisation
GitHub pour l'instant côté déploiement (`git pull` manuel sur le VPS) — voir
`CLAUDE.md`/`docs/status_v0.md` si une Action GitHub est ajoutée plus tard,
ce document reste la référence des commandes.

## Prérequis sur le VPS

- Le réseau Docker externe `echango_network` doit déjà exister (créé par la
  stack principale Traefik/Vendure, démarrée au moins une fois). Vérifier :
  `docker network inspect echango_network` — si absent, démarrer d'abord la
  stack principale.
- `/opt/echangopromo` = clone de ce dépôt (branche déployée à définir avec
  l'utilisateur — `main` par défaut).

## Premier déploiement

```bash
cd /opt/echangopromo
git clone <url-du-repo> .   # ou git pull si déjà cloné

# Fichier d'env réel, jamais commité (gitignoré) — un seul fichier, à la
# fois lu par `docker compose --env-file` (substitution ${...} dans
# docker-compose.promo.yml) et injecté dans le conteneur backend (env_file) :
cp .env.production.example .env.production
# éditer : POSTGRES_PASSWORD (alphanumérique uniquement, voir commentaire
# dans le fichier), DATABASE_URL (même mot de passe que POSTGRES_PASSWORD),
# JWT_SECRET, credentials S3 OVH, BASE_DOMAIN.

docker compose --env-file .env.production -f docker-compose.promo.yml up -d --build
```

Le conteneur `backend` lance automatiquement les migrations au démarrage
(`Dockerfile` : `npx typeorm migration:run -d dist/data-source.js && node
dist/main`) — rien à faire de spécial pour ça, `up -d` suffit.

## Seeds (admin, communes)

Les scripts de seed (`src/scripts/seed-admin.ts`, `seed-communes.ts`) sont
compilés dans `dist/scripts/` par `nest build` (comme `main.ts` →
`dist/main.js`), donc exécutables directement dans le conteneur de prod
sans dépendance dev (`ts-node` n'est pas dans l'image finale) :

```bash
# Premier admin (une seule fois)
docker compose --env-file .env.production -f docker-compose.promo.yml exec backend \
  npm run seed:admin:prod -- admin@echango.com "mot-de-passe" "Nom Admin"

# Référentiel communes (idempotent, à relancer si la liste est corrigée)
docker compose --env-file .env.production -f docker-compose.promo.yml exec backend \
  npm run seed:communes:prod
```

Ne pas mettre `ADMIN_EMAIL`/`ADMIN_PASSWORD`/`ADMIN_NOM` dans
`.env.production` sur le VPS (ce fichier tourne en continu) : passer les
identifiants uniquement en argument CLI au moment du seed.

## Redéploiement (mise à jour du code)

```bash
cd /opt/echangopromo
git pull origin main
docker compose --env-file .env.production -f docker-compose.promo.yml up -d --build backend
```

Les migrations en attente s'appliquent automatiquement au redémarrage du
conteneur `backend`.

## Réseau Traefik — labels utilisés

Voir `docker-compose.promo.yml` pour les labels exacts (routeur
`echango-promo`, service `echango-promo-svc`, entrypoint `websecure`,
priorité `20` pour passer devant le routeur wildcard `storefront-vendor` de
la stack Vendure, middlewares `security-headers@file` + `compress@file`).
Le port `3000` déclaré dans le label loadbalancer est le port interne du
conteneur — aucun port n'est publié sur l'hôte, Traefik y accède via
`echango_network`.

PostgreSQL de cette stack reste sur un réseau interne séparé (`internal`,
défini dans `docker-compose.promo.yml`), jamais attaché à
`echango_network` : la base de données n'a aucune raison d'être joignable
depuis le réseau partagé avec la stack Vendure.

**Incident réel rencontré au premier déploiement** : le service Postgres
s'appelait initialement `postgres` tout court. Comme la stack Vendure a
elle aussi un service nommé `postgres` sur le même réseau externe
`echango_network`, et que `backend` est attaché aux deux réseaux, le nom
`postgres` se résolvait silencieusement vers **leur** conteneur au lieu du
nôtre — `getent hosts postgres` depuis `backend` renvoyait l'IP de
`echango-postgres-1` (Vendure), pas de `echangopromo-postgres-1`. Résultat :
`password authentication failed for user "echango"` alors que le mot de
passe était rigoureusement correct des deux côtés (vérifié caractère par
caractère) — le backend parlait simplement à la mauvaise base. Renommé en
`postgres_promo` (nom qui ne peut pas collisionner) pour éliminer la classe
d'erreur. À vérifier systématiquement en cas de nouveau symptôme
d'authentification similaire sur un réseau Docker partagé entre plusieurs
stacks : `docker compose run --rm backend getent hosts <nom-du-service>`
doit résoudre vers l'IP du conteneur attendu.

## Différence avec `docker-compose.yml` (dev local)

`docker-compose.yml` (racine du repo) reste pour le développement local
uniquement : ports hôte publiés (`5433`, `3000`, `9000`/`9001`), MinIO en
remplacement de S3 OVH. `docker-compose.promo.yml` est spécifique au VPS
(réseau Traefik externe, pas de MinIO, credentials S3 OVH réels). Les deux
partagent le même `apps/backend/Dockerfile`.
