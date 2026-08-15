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

## Seed (admin)

⚠️ **`seed:communes:prod` a disparu le 2026-08-13** avec le découpage
administratif : le script, la table et les deux entrées `package.json` sont
supprimés. Cette page l'ordonnait encore comme une étape de mise en
production — un runbook qui prescrit une commande inexistante fait échouer un
déploiement au pire moment, et rien ne l'aurait signalé avant.

Le script de seed restant (`src/scripts/seed-admin.ts`) est compilé dans
`dist/scripts/` par `nest build` (comme `main.ts` → `dist/main.js`), donc
exécutable directement dans le conteneur de prod sans dépendance dev
(`ts-node` n'est pas dans l'image finale) :

⚠️ **Le mot de passe ci-dessous reste un espace réservé, et doit le rester.**
Ce fichier est versionné et poussé sur GitHub : y écrire le vrai secret le
publie, et l'historique Git le garde même après correction — il faudrait alors
faire tourner le mot de passe, pas seulement modifier la ligne. Le secret réel
se tape au moment du seed et ne vit nulle part dans le dépôt.

```bash
# Premier admin (une seule fois)
docker compose --env-file .env.production -f docker-compose.promo.yml exec backend \
  npm run seed:admin:prod -- admin@echango.com "<mot-de-passe-hors-dépôt>" "Admin Promo"
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

⚠️ **Et c'est pourquoi une migration qui échoue ne dégrade pas : elle coupe.**
Le conteneur enchaîne `migration:run && node dist/main` — si la première
commande sort en erreur, la seconde n'est jamais lancée et **le backend ne
démarre pas du tout**. Une migration qui refuse volontairement (contrôle de
doublons, par exemple) doit donc être précédée de sa vérification, sur la base
de production, **avant** le `up -d`.

> **Export vers le CRM Odoo** (PR #28, 2026-08-15) : procédure dédiée dans
> [`DEPLOIEMENT_CRM_VPS.md`](DEPLOIEMENT_CRM_VPS.md). Aucune migration de
> schéma ; trois clés à poser dans le `.env.production` du VPS, qu'aucun
> `git pull` ne met à jour. Sans elles, la tâche de 04:00 journalise son
> abstention et ne pousse rien — le déploiement est donc inerte tant qu'on ne
> l'allume pas.

> **Migration du téléphone en E.164** (PR #25, 2026-08-15) : procédure dédiée
> dans [`MIGRATION_TELEPHONE_VPS.md`](MIGRATION_TELEPHONE_VPS.md). Elle réécrit
> l'identifiant de connexion de toutes les fiches commerçant et **refuse en
> bloc** s'il existe deux comptes actifs qui deviennent un doublon. Sa
> première étape est une requête en lecture seule à passer avant tout
> déploiement.

## Outils d'exploitation — deux scripts qui écrivent en base

⚠️ **Les deux court-circuitent le produit**, et il faut le savoir avant de les
lancer : ils écrivent directement dans PostgreSQL, donc **aucune règle métier
n'est appliquée et aucune entrée d'audit n'est écrite**. Leur sortie est la
seule trace de ce qu'ils ont fait — la conserver.

Tous deux fonctionnent **en simulation par défaut** : sans `--appliquer`, ils
lisent, affichent ce qu'ils feraient, et sortent sans rien changer.

⚠️ Tous deux exigent d'être lancés **depuis `/opt/echangopromo`** : ils lisent
`.env.production` et cherchent le conteneur Postgres via `docker compose`.

### Remettre en ligne les promos expirées

```bash
./scripts/prolonger-promos-prod.sh 30              # simulation
./scripts/prolonger-promos-prod.sh 30 --appliquer
```

Le nombre est une **durée en jours à partir de maintenant** : toutes les promos
remises reçoivent la même échéance. Ce n'est pas un ajout à leur date existante
— laquelle est de toute façon passée.

Il vise `lifecycleStatus = 'expiree'` **et** `moderationStatus = 'normale'`, et
fait deux choses : repasse le cycle de vie à `publiee` et pose la nouvelle date.
Prolonger la date seule ne suffirait pas — une promo expirée reste invisible
tant que son cycle de vie n'a pas changé.

**Ce qu'il ne touche pas** : les promos signalées ou masquées (les remettre en
ligne reconduirait un contenu qu'un modérateur a écarté), et les promos
arrêtées (un arrêt est un geste volontaire du commerçant).

⚠️ Le plafond de promos actives n'étant plus appliqué par le produit, le script
le calcule lui-même par commerçant, en lisant `commercant."promoActiveCap"` et
`PROMO_ACTIVE_CAP`. Il annonce combien de promos il laisse de côté faute de
place — un « 0 remise » avec des expirées en attente vient de là, pas d'une
panne.

⚠️ **Pourquoi la base et non l'API** : aucune route ne prolonge une promo
existante (`update-promo.dto.ts` ne porte ni `dureeJours` ni `dateFin`). Les
clés `PROMO_*_DURATION_DAYS` ne valent que pour les publications à venir.

### Supprimer définitivement des commerçants

```bash
./scripts/supprimer-commercants-prod.sh --telephone +213555     # simulation
./scripts/supprimer-commercants-prod.sh --telephone +213555 --appliquer
./scripts/supprimer-commercants-prod.sh --id <uuid> --appliquer
./scripts/supprimer-commercants-prod.sh --tous --appliquer      # confirmation
```

⚠️⚠️ **IRRÉVERSIBLE. Faire une sauvegarde avant** (§ Sauvegardes ci-dessous).

**La portée est obligatoire** — aucune valeur par défaut, et `--tous` exige une
confirmation tapée à la main. Un script destructeur dont on peut oublier le
filtre vide la base un jour de fatigue.

⚠️ **Il ne fait pas ce que fait le produit.** `DELETE /commercant/me` est une
suppression *douce* : `deletedAt` posé, promos passées en `SUPPRIMEE`, rien
d'effacé. Elle ne convient pas à un nettoyage, parce que **le numéro de
téléphone reste occupé** : `assertPhoneAvailable` filtre sur `deletedAt`, mais
`login` ne le fait pas (défaut P10) — un numéro recyclé enferme son repreneur
dehors.

**Ce qui part** : le commerçant, ses promos (CASCADE), et les quatre tables qui
les référencent **sans clé étrangère** — `report`, `promo_view`,
`notification`, `commercant_view`. Sans traitement explicite, ces lignes
resteraient à pointer vers des disparus ; personne ne le verrait, jusqu'au jour
où un décompte de signalements ou de vues sortirait faux.

**Ce qui reste** : `audit_log`, parce qu'on ne réécrit pas le journal des
décisions. Et les diapositives curées, dont la clé passe à `NULL` — ⚠️ **à
vérifier après coup dans `/admin/highlight`**, le script le rappelle.

Tout se fait dans **une seule transaction** : tout passe, ou rien ne passe.

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

## Sauvegardes — installation sur le VPS

Rien de tout ceci n'est automatique : le code est dans le dépôt, la
**configuration ne peut pas y être** (elle porte une clé S3 et une phrase de
passe). Tant que ces étapes ne sont pas faites sur le VPS, il n'y a **aucune
sauvegarde de la production** — et le dépôt ne le dira pas, puisque le script
existe.

### 0. Ce dont le VPS a besoin

```bash
command -v python3 gpg docker      # les trois sont indispensables
df -h /var/lib/docker              # place libre ≳ 2 × la taille de la base
```

`python3` et `gpg` sont présents sur une Debian/Ubuntu standard. La place
libre compte parce que la vérification **restaure réellement** chaque
sauvegarde dans une base jetable, sur ce même serveur : il faut de quoi loger
une seconde copie de la base le temps du contrôle.

### 1. Une clé S3 **dédiée**, pas celle de l'application

À créer dans le manager OVH, distincte de `S3_ACCESS_KEY_ID` :

- **Pourquoi** — la clé de l'application vit dans `.env.production`, lue par
  un service exposé sur Internet. Si elle sert aussi aux sauvegardes, qui
  compromet le backend peut **effacer les sauvegardes**, c'est-à-dire
  transformer un incident récupérable en perte définitive.
- **Portée souhaitée** — écriture et lecture sur `echango-private`
  uniquement. ⚠️ Le support des politiques fines est partiel chez OVH
  (`storage.service.ts:185` note un `NotImplemented` sur les *bucket
  policies*). Si une clé restreinte n'est pas réalisable, prendre au minimum
  un **utilisateur S3 distinct** — et noter ici que la restriction n'a pas pu
  être appliquée, pour que ce soit un choix constaté et non un oubli.

### 2. Le fichier de configuration

```bash
cd /opt/echangopromo
cp scripts/backup.env.example ~/.echango-backup.env
chmod 600 ~/.echango-backup.env      # le script REFUSE tout autre mode
nano ~/.echango-backup.env
```

Quatre valeurs à renseigner : les deux identifiants de l'étape 1, et
`BACKUP_PASSPHRASE`.

> ⚠️ **`BACKUP_PASSPHRASE` se range ailleurs que sur le VPS.** La perdre rend
> **toutes** les sauvegardes définitivement illisibles ; la laisser
> uniquement sur la machine sauvegardée revient à la perdre avec elle, le jour
> exact où l'on en a besoin. Gestionnaire de mots de passe, ou coffre.

**Et trois clés propres au VPS**, à ajouter dans ce même fichier — le script
le charge en entier avant de démarrer, donc tout s'y met :

```bash
# Le conteneur Postgres de la stack de prod ne porte PAS le nom par défaut
# (qui vise le dev local). Le vérifier plutôt que le supposer :
#     docker ps --format '{{.Names}}' | grep postgres
PG_CONTAINER=echangopromo-postgres_promo-1

# La prod ne lit pas apps/backend/.env — son DATABASE_URL est ici :
ENV_FILE=/opt/echangopromo/.env.production

# Où déposer les dumps sur l'hôte (créé au besoin)
BACKUP_DIR=/var/backups/echangopromo
```

### 2 bis. Ce que la rétention garde, et ce qu'elle peut effacer

**7 quotidiennes + 8 hebdomadaires** — une quinzaine de fichiers pour deux
mois d'histoire. L'exemplaire hebdomadaire est le **premier de chaque semaine
ISO**, pas celui d'un jour fixe : si le serveur dort le vendredi, c'est samedi
qui prend le relais. Un jour fixe ferait disparaître la semaine entière, sans
que rien ne le signale. L'étiquette est dans le nom :

```
echango_promo-20260805-030000.dump                  ← quotidienne
echango_promo-20260807-030000-hebdo-2026W32.dump    ← l'exemplaire de la semaine 32
```

> ⚠️ **`echango-private` est partagé entre plusieurs applications de la
> suite — le préfixe est donc une frontière, pas du rangement.** Il borne
> l'ensemble sur lequel la rétention **supprime**. Trois gardes sont en place,
> et il vaut mieux savoir qu'ils existent :
>
> - un préfixe vide, sans barre finale, ou commençant par `/` est **refusé**
>   au démarrage (`echango-promo` sans barre capturerait
>   `echango-promo-v2/…`) ;
> - la purge ne supprime **que** les clés commençant par le préfixe
>   configuré — on ne fait pas dépendre les sauvegardes d'un voisin du
>   filtrage côté serveur ;
> - une clé dont on ne sait pas lire l'horodatage n'est **jamais** supprimée :
>   inconnue ≠ vieille.

Si vous ajoutez une autre nature de sauvegarde pour ce produit (objets S3,
configuration), donnez-lui **son propre préfixe**. Deux natures sous le même
préfixe se feraient purger l'une l'autre pour tenir dans les 7 + 8.

### 3. Le premier passage, à faire à la main

```bash
cd /opt/echangopromo && ./scripts/backup-db.sh
```

Huit contrôles doivent s'afficher. Ce qu'il faut **vraiment** regarder :

| Ligne | Ce qu'elle prouve |
|---|---|
| `comptes source ↔ restauré` | le fichier se restaure, table par table |
| `chiffrement + déchiffrement` | le chiffré se **rouvre** — sinon il ne vaut rien |
| `étanchéité (requête anonyme)` | l'objet déposé **ne se lit pas sans clé** |
| `rétention distante` | ⚠️ **c'est ici que ça se joue, voir ci-dessous** |

⚠️ **La rétention distante est la seule étape jamais éprouvée contre OVH.**
Le banc local tourne contre MinIO, qui ne fait pas de *virtual-hosted* et
répond à la demande de listage par la liste des **dépôts** — le script le
détecte et rend `non concluant` plutôt que de conclure « rien à purger ».
Sur OVH ce doit être un `ListBucketResult` normal. **Si le premier passage
affiche encore « document `ListAllMyBucketsResult` », c'est là qu'il faut
regarder** : sans listage, les sauvegardes distantes s'accumuleront sans
jamais être purgées.

Puis vérifier que la récupération fonctionne — **avant d'en avoir besoin** :

```bash
set -a; . ~/.echango-backup.env; set +a
python3 scripts/lib/backup_upload.py --lister
```

### 4. La tâche planifiée

```cron
0 3 * * *  cd /opt/echangopromo && ./scripts/backup-db.sh >> /var/log/echangopromo-backup.log 2>&1
```

L'utilisateur du cron doit pouvoir lancer `docker` (root, ou membre du groupe
`docker`).

> **Ce qu'une supervision doit surveiller, c'est le CODE DE SORTIE**, jamais
> la présence du fichier : le mode de défaillance visé est précisément « le
> dump tourne toutes les nuits, sort 0, et produit un fichier tronqué ».

Les deux messages d'échec ne veulent **pas** dire la même chose :

- *« la sauvegarde a été produite mais NE SE RESTAURE PAS »* → le fichier ne
  vaut rien, traiter comme s'il n'y avait pas de sauvegarde. **Urgent.**
- *« saine et restaurable, mais elle N'A PAS QUITTÉ LA MACHINE »* → la
  sauvegarde est bonne, c'est l'envoi qui a échoué. On est protégé d'un
  `DELETE` malheureux, pas d'une perte de disque.

### 5. Restaurer — la procédure du jour de l'incident

Éprouvée de bout en bout (rapatriement, déchiffrement, restauration de 13
tables, empreinte identique à la source) :

```bash
cd /opt/echangopromo
set -a; . ~/.echango-backup.env; set +a

python3 scripts/lib/backup_upload.py --lister
python3 scripts/lib/backup_upload.py --rapatrier echango-promo/db-backups/<fichier>.dump.gpg /tmp/restaure.dump

# Restaurer À CÔTÉ d'abord — jamais par-dessus la base vivante
docker compose --env-file .env.production -f docker-compose.promo.yml \
  exec postgres_promo createdb -U echango echango_promo_restaure
docker compose --env-file .env.production -f docker-compose.promo.yml \
  exec -T postgres_promo pg_restore -U echango -d echango_promo_restaure --no-owner < /tmp/restaure.dump
```

Regarder ce qu'on a récupéré **avant** de basculer quoi que ce soit. Une
restauration par-dessus la base vivante détruit l'état actuel — y compris ce
qu'on aurait voulu garder.

## Rotation du mot de passe `superadmin`

Point de sécurité ouvert au registre : le mot de passe a circulé dans un APK
de test. La capacité existe depuis le 2026-08-05 ; le geste demande un accès
au serveur.

```bash
docker compose --env-file .env.production -f docker-compose.promo.yml exec backend \
  npm run seed:admin:prod -- admin@echango.com "<nouveau-mot-de-passe>" "Nom Admin" --rotate
```

⚠️ `--rotate` incrémente aussi `tokenVersion` : **toutes les sessions admin en
cours sont coupées**, sur tous les appareils. C'est voulu — changer le mot de
passe sans couper les sessions laisserait un jeton déjà volé valide jusqu'à
son expiration (30 jours). Prévenir avant de le lancer.

Sans `--rotate`, la commande refuse de toucher à un compte existant : c'est
volontaire, pour qu'on ne remplace jamais un mot de passe en croyant créer un
compte.

## Différence avec `docker-compose.yml` (dev local)

`docker-compose.yml` (racine du repo) reste pour le développement local
uniquement : ports hôte publiés (`5433`, `3000`, `9000`/`9001`), MinIO en
remplacement de S3 OVH. `docker-compose.promo.yml` est spécifique au VPS
(réseau Traefik externe, pas de MinIO, credentials S3 OVH réels). Les deux
partagent le même `apps/backend/Dockerfile`.
