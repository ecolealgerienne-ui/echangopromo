# Audit de sécurité — echango Promo

**Date** : 2026-08-14
**Cible** : backend NestJS 11 + TypeORM + PostgreSQL 16, app Flutter multi-rôles. Commit `ad10ce1`, branche `claude/echango-promo-suite-2026-08-04`.
**Où** : instance locale auto-hébergée — backend `http://localhost:3000` (clone WSL `~/projects/echangopromo`), Postgres `echangopromo-postgres-1` (port hôte 5433), MinIO `echangopromo-minio-1`.
**Autorisation** : application appartenant à l'exploitant, auto-hébergée sur sa propre machine, base de développement. Test autorisé.
**Méthode** : les sept couches du skill `audit-securite`. Chaque constat est passé à un **vérificateur adverse** avant d'être écrit ici.

> ⚠️ **Ce document est le RÉSULTAT daté, pas la méthode.** La méthode générale
> vit dans le skill. Ce qui est propre à ce dépôt et se périme — les chiffres,
> les états — est ici.

---

## 1. Résumé exécutif

| | |
|---|---|
| Couches jouées | **C1** (revue), **C2** (statique), **C3** (dépendances), **C4** (images), **C5** (secrets), **C6** (dynamique) |
| Couches **NON jouées** | **C7** (client sur appareil) — aucun émulateur lancé |
| Constats de revue | **15 instruits** — 11 confirmés, **1 réfuté**, 4 corrigés dans leurs chiffres, leur portée ou leur sens |
| Attaques rejouées (C6) | 42 bancs, ~146 contrôles, **0 échec** — mais **3 bancs sautés**, dont la frontière HTTP |
| Secrets | 1 fuite historique, acceptée et documentée ; audit au vert après calibration |
| Images | 4 images, **0 verte** |
| Dépendances | 869 versions verrouillées, **1 avis** (sans portée production) |

**Conclusion.** Aucune faille d'authentification ni d'élévation de privilège
n'a été trouvée. Les deux problèmes qui comptent sont ailleurs :

1. **Un corpus de documents d'identité professionnelle est lisible sans
   authentification** dans l'environnement de développement (§4.1) ;
2. **une décision de modération peut être annulée en silence** par une
   republication concurrente (§4.2).

⚠️ **Ce que « 0 échec sur 146 contrôles » ne veut pas dire.** Trois bancs n'ont
pas conclu, dont `frontiere-http` — celui qui éprouve les 63 routes. La
frontière d'accès **n'est pas éprouvée dans cette passe**. Et les bancs sont
séquentiels : aucun des cinq constats de concurrence de §4 n'est à leur portée.

---

## 2. Périmètre — ce qui s'applique, et ce qui ne s'applique pas

Établi depuis la source (JWT Bearer HS256, aucun cookie, aucun flux OTP, client
natif) — pas depuis une liste OWASP générique.

| Classe | Applicable ? | Pourquoi | Où c'est joué |
|---|---|---|---|
| XSS / CSP / `X-Frame-Options` | ❌ | client Flutter natif, aucune surface de rendu HTML | — |
| **CSRF** | ❌ | **aucun cookie** — authentification par en-tête `Authorization` | — |
| Falsification de jeton (`alg:none`, signature) | ✅ | JWT | `pentest_dynamique.py` — voir §5.2 |
| Flux OTP (compteur, cooldown) | ❌ | aucun flux OTP n'existe (décision produit) | — |
| Injection SQL | ✅ vérifiée | 2 requêtes brutes, **toutes deux paramétrées `$1`** ; la seule interpolation injecte une constante de classe | mesuré, §3.3 |
| IDOR / appartenance | ✅ | 4 rôles, ressources adressables par id | `portee-agent` (36 contrôles), `frontiere-admin` (19) |
| Confiance dans l'en-tête d'IP cliente | ✅ | `trust proxy 1` derrière Traefik | §4.3 |
| Upload / URL présignées | ✅ | S3/MinIO, `@aws-sdk/s3-request-presigner` | §4.1 |
| Épinglage de certificat, obfuscation | ✅ | app mobile distribuée | §5.4 |

**Énumération depuis le routage** (`frontiere_http.py --list`) : **63 routes,
14 ouvertes, 49 protégées**. L'ensemble ouvert est **exactement** celui qui est
épinglé nommément — aucune route ouverte non déclarée, aucune route protégée
sans `@Roles`. La règle 33 tient.

---

## 3. Résultats par couche

### 3.1 C1 — revue par agents

4 agents en parallèle (généraliste, web, postgres, flutter), puis **8
vérificateurs adverses** sous des angles distincts (correctness, sécurité,
reproductibilité). Détail des constats en §4 et §5.

> **Un agent seul rend un rapport plausible ; c'est la paire qui rend un rapport
> juste.** Sur 15 constats instruits, **4 ont vu leurs chiffres, leur portée ou
> leur sens corrigés, et 1 est tombé.** Aucune de ces corrections ne venait
> d'une relecture : chacune venait d'une mesure que le premier agent n'avait pas
> faite.

### 3.2 C2 — pentest statique

| Périmètre | Fichiers | Erreurs de parsing | Constats |
|---|---|---|---|
| `apps/backend/src` (8 paquets de règles) | 132 | 0 | **1** |
| `apps/mobile/lib` | 130 | 0 | **0** |

Le constat unique — `regex_dos` sur `/iPhone|iPad|iPod/i.test(userAgent)` — est
un **faux positif** : alternance constante, sans quantificateur imbriqué, donc
linéaire.

⚠️ **Le vert du Dart vaut beaucoup moins qu'il n'en a l'air.** Témoin de
couverture soumis à semgrep, trois familles de secrets, en Dart :

```
TEMOIN Dart (3 familles) -> vues par semgrep : 1 /3   (seule la clé AWS)
```

130 fichiers analysés, 0 erreur de parsing, et presque **aucune règle
applicable**. « Le langage est supporté » ne qualifie que l'analyseur
syntaxique. C'est la mesure qui justifie le second moteur en C5.

### 3.3 C3 — dépendances

869 versions verrouillées (`apps/backend/package-lock.json` 730 +
`apps/mobile/pubspec.lock` 139), interrogées à osv.dev.

**1 avis** : `js-yaml` 4.3.0 — `GHSA-5p4m-2wfm-xmqj`, consommation CPU
quadratique sur `!!omap`, CVSS `C:N/I:N/A:H` (disponibilité seule).

**Instruit** : `npm ls js-yaml --omit=dev` rend **vide**. Il ne vient que
d'eslint, du CLI Nest et de ts-jest. Le `npm ci --omit=dev` du Dockerfile
l'exclut du runtime. **Réel, sans portée production.** Correction triviale
(→ 4.3.1), non urgente.

### 3.4 C4 — images de conteneur

⚠️ **Périmètre corrigé pendant cette passe** : l'outil ne lisait d'abord que les
clés `image:` des composes, et taisait donc **le service `build:` — c'est-à-dire
l'image du backend, la seule que nous produisons**. Corrigé.

| Image | Graves corrigeables | Concentrées dans | Instruction |
|---|---|---|---|
| `echangopromo-backend` | **12** | **Node.js ×12** | 🔴 le runtime. Rebuild sur le `node:22-alpine` du jour → **8**. Les 8 restants ne sont livrés par aucune image publiée |
| `postgres:16-alpine` | 18 | `gosu` ×15, base ×3 | les 15 de `gosu` sont **liées, jamais exécutées** (résolution d'utilisateur, `exec`). L'image locale est en retard : `docker pull` → 15 |
| `minio/minio:latest` | **78** | `usr/bin/minio` ×41, `mc` ×35 | 🔴 **atteignable** — serveur réseau. Re-tirer l'image ne change **rien** (mesuré) |
| `minio/mc:latest` | 37 | `usr/bin/mc` ×35 | idem |

**Mesure décisive** : `node:22-alpine` fraîchement tiré → 8 graves (identique) ;
`minio/minio:latest` fraîchement tiré → 78 (identique). *« Corrigeable » veut
dire « le correctif existe en amont », pas « une image que tu peux utiliser le
porte ».*

### 3.5 C5 — secrets

Deux moteurs (gitleaks v8.30.1 + semgrep), arbre **et** historique complet.
Auto-test **5/5**, audit réel **3/3**.

**Aucune fuite non acceptée.** Une fuite historique réelle, acceptée et
documentée dans `.gitleaksignore` : un PIN de développement dans
`dev_profile_switcher_screen.dart`, retiré de l'arbre le 2026-08-13, **toujours
dans l'historique**.

> 🔴 **Seule remédiation possible : ne jamais créer ce couple téléphone/PIN sur
> l'instance de production.** Retirer un secret d'un fichier ne le retire pas du
> dépôt. Portée nulle aujourd'hui (base de dev locale), réelle le jour où ce
> numéro s'inscrirait.

⚠️ Les ~170 règles **par défaut** rendent **zéro** sur ce dépôt. Les règles qui
voient nos secrets sont dans `.gitleaks.toml`, écrites pour ce dépôt.

### 3.6 C6 — pentest dynamique

`./scripts/provision-decor.sh` puis `./scripts/test-tout.sh`, clone WSL remis à
jour (il avait 9 commits de retard).

```
34 verts · 0 échec(s) · 5 non concluant(s) · 3 sauté(s)
⚠️  tout n'a pas conclu : ce n'est pas un lot vert.
```

| Sauté | Raison | Conséquence |
|---|---|---|
| **`frontiere-http`** | connexion commerçant `429 RATE_LIMITED` | 🔴 **la frontière d'accès n'est pas éprouvée dans cette passe** |
| `plan-sql` | `psycopg2` absent de l'environnement | les plans SQL ne sont pas vérifiés |
| `commercant-b` | code 2, aucun décompte | la frontière commerçant↔commerçant n'est pas éprouvée |

**Cause du 429 : l'audit lui-même.** Le décor consomme six connexions, et les
vérificateurs se sont authentifiés en parallèle.

### ✅ Rejoués seuls le 2026-08-14 — deux des trois trous sont fermés

```
frontiere-http : auto-test 17/17 (dont 6 refus)
                 49 routes protégées (63 au total, 14 ouvertes épinglées, 3 host-scopées)
                 141 sondes, 0 échec
                 ⚠️ 6 routes sans sonde « mauvais rôle » : elles acceptent les 3 rôles
commercant-b   : 4 contrôles, 0 échec
                 PATCH / publish / stop sur la promo d'un autre → 403 PROMO_NOT_OWNED_BY_COMMERCANT
                 le même geste sur sa propre promo → 200
plan-sql       : auto-test 17/17, puis TOUJOURS BLOQUÉ — `psycopg2` absent
```

**La frontière d'accès est donc éprouvée**, et la frontière commerçant↔commerçant
aussi. Reste `plan-sql` : `pip` n'existe pas dans le Python de cette WSL
(`No module named pip`). C'est un trou d'**environnement**, et il porte sur des
plans de requête — de la performance, pas de la sécurité.

---

## 4. Constats confirmés

### 4.1 🔴 Les documents de registre sont accessibles sans authentification (dev)

**Reproduit de bout en bout.**

```
X-Amz-SignedHeaders=host          (l'URL ne couvre pas Authorization)
PRESIGNED_BEFORE_REVOKE .......... 200
REVOKE_HTTP ...................... 201
AGENT_TOKEN_AFTER_REVOKE ......... 401   ← le JWT est bien mort
PRESIGNED_AFTER_REVOKE_NAKED ..... 200   ← MÊME URL, sans aucun en-tête
NAKED_OBJECT_NO_SIG .............. 200   ← chemin nu, SANS signature du tout
```

Deux défauts distincts, à ne pas confondre :

**(a) Le bucket est en lecture anonyme.** `docker-compose.yml:67` pose
`mc anonymous set download local/echango-promo` sur **tout** le bucket,
`registre-documents/*` compris :

```
Access permission for `echango-promo` is `download`
Statement: s3:GetObject / Principal:"*" / Resource: arn:aws:s3:::echango-promo/*
```

Le commentaire de `storage.service.ts:45-52` affirme que ce dossier est privé.
Dans l'environnement qui tourne, il ne l'est pas.

**(b) L'URL présignée est une capacité au porteur.** Signature SigV4
autoportante, TTL 15 min : `revoke-token` — que le plan produit désigne comme le
dernier levier face à un agent douteux — **la laisse vivre**.

Aggravants mesurés : `GET /admin/commercant` est `@Roles('admin','agent')`,
`MAX_PAGE_SIZE=100`, **aucun `@Throttle`** (seau global 60/min → jusqu'à 6 000
URL/min), et **aucune entrée d'audit**. Une seule requête de 34 Ko rend
**129 fiches, 100 téléphones, 57 URL de registre**.

⚠️ **Portée par environnement, à ne pas confondre :**
- **dev** : exposition **non bornée, sans jeton** — (a) domine, l'URL présignée
  ne protège rien ;
- **production (OVH)** : pas de MinIO, pas de `mc anonymous set`, et OVH ne
  supportant pas les *bucket policies*, seule l'ACL par objet s'applique —
  `private` tiendrait, et (b) devient la seule surface. **Reste à prouver sur
  OVH**, non mesurable depuis ce poste.

**Contexte** : le pentest du 2026-08-05 avait inscrit ce point en angle mort
explicite (*« contenu réel des jetons présignés S3 »*) et tournait quand l'agent
était encore cloisonné par commune. La bascule du 2026-08-13 a élargi le rayon
au parc national **sans que personne ne re-mesure**.

### 4.2 🔴 `publish()` annule une décision de modération

`promo/promo.service.ts:755-785`. `publish` charge un instantané, entre dans
`withCommercantLock`, puis `manager.save(promo)` — TypeORM réémet **toute**
colonne ayant dérivé en base entre-temps, dont `moderationStatus`.

**Mesuré, avec témoin négatif** (c'est le témoin qui donne sa valeur à la
mesure) :

| Cas | SQL émis |
|---|---|
| aucune modération concurrente | `SET dateFin, publishedAt, lifecycleStatus, updatedAt` → **pas de `moderationStatus`** |
| `masquer` pendant la fenêtre | `… moderationStatus=$4` avec `$4 = "normale"` |
| `verifier-ok` pendant la fenêtre | `… moderationStatus=$4 ('signalee'), verifiedOkAt=$5 (null)` |

État final : `{"lifecycleStatus":"publiee","moderationStatus":"normale"}` — **la
promo masquée redevient publique**, sans erreur nulle part. La variante
`verifier-ok` **efface aussi `verifiedOkAt`** (fenêtre d'ignore de 30 j) et
remet la promo en file.

**Atteignabilité prouvée sur les données réelles** : 128 promos publiables en
`normale`, et **5 promos simultanément en file** (`signalee`, ≥ 3 appareils) **et**
`arretee`/`expiree`, donc republiables. La file ne filtre pas le cycle de vie.

**Correction apportée par le vérificateur** : la fenêtre n'est **pas** « non
bornée » — mesurée **3,7 à 4,7 ms**. C'est toute la différence avec `update()`,
dont la fenêtre contenait un aller-retour S3. Le correctif du 2026-08-05 n'a pas
été porté ici, mais l'exposition est **trois ordres de grandeur plus faible**.

⚠️ **Même famille, fenêtre bien plus large, non relevée jusqu'ici** :
`purgeOldPhotosCron` (`promo.service.ts:1519-1532`) charge sa liste **une fois**
puis sauvegarde après N suppressions S3 **sans timeout**. L'instantané peut avoir
des minutes.

**Le banc est déterministe** — le verrou consultatif que `publish` prend
lui-même permet d'élargir la fenêtre à volonté depuis psql :

```
départ                    : arretee / normale
verrou tenu par un tiers  -- pg_advisory_xact_lock(hashtext('<commercantId>'))
masquer (200, affected=1) : arretee / masquee
après relâche             : publiee / normale     ← décision perdue
```

### 4.3 🟠 `trust proxy 1` : les seaux de cadence sont contournables latéralement

**Mesuré**, en lecture seule, sur `GET /promo/config` :

```
sans XFF, 4 tirs         → 56, 55, 54, 53
XFF: 203.0.113.7         → 59, 58     ← seau neuf
XFF: 198.51.100.9        → 59         ← seau neuf (rotation)
XFF: 1.1.1.1, 2.2.2.2    → 59  |  XFF: 9.9.9.9, 2.2.2.2 → 58   ← seul le DERNIER hop compte
retour sans XFF          → 52         ← témoin : le seau réel n'a rien absorbé
```

`@nestjs/throttler` 6.5.0 indexe sur `req.ip`, sans surcharge. Une valeur de
`X-Forwarded-For` = un seau vierge.

**Ce que ça coûte réellement** : `common/throttle.ts:22-37` écrit que **aucun
compteur de tentatives par compte n'existe** et que le plafond IP est *« l'unique
défense de la règle 2 »*. Le contournement ne la dégrade pas, **il la supprime** :
le brute-force de PIN passe de « 3 h 20 à 50/min » à quelques minutes.

**Strictement latéral.** Le backend ne publie aucun `ports:` ; l'unique entrée
est Traefik, et la sémantique « dernier saut » **ferme** l'attaque externe. Il
faut un pied dans un conteneur voisin de `echango_network` — où vivent Traefik et
le storefront Vendure ; `DEPLOIEMENT_VPS.md:95-107` documente un incident réel de
résolution croisée entre les deux stacks.

**Remède** : `app.set('trust proxy', <IP ou sous-réseau de Traefik>)` au lieu du
compteur `1` — la seule forme qui sait dire non à un client direct. Second filet,
indépendant de la topologie : le compteur par compte, déjà nommé comme manquant
dans `throttle.ts:39-43`.

⚠️ **L'absence de `helmet` n'est PAS un constat neuf** — elle est documentée et
arbitrée 🟢 dans `AUDIT_SECURITE_PROD_2026-07.md:187-195`, avec le raisonnement
exact. Et elle ne referme rien ici : aucun en-tête n'empêche un voisin de forger
un `X-Forwarded-For`.

### 4.4 🟠 Le journal d'audit ne couvre que les écritures

**Mesuré** : journal agent **445 avant, 445 après** 8 lectures privilégiées
toutes en `200`. **Rang : 0/8.**

Les 21 sites d'audit sont tous des écritures — vérifié route par route, zéro
`@Get`. Aucun intercepteur global, aucun middleware, aucun journal d'accès HTTP
(`morgan`/`pino`/`winston` : absents). Le journal **sait** écrire : 796 entrées,
22 actions distinctes, toutes des verbes d'écriture.

**Nuance imposée par le vérificateur** : le mot « désarmé » est faux. Le journal
fait correctement son travail sur les écritures (attribution par agent prouvée
par mutation). Le mot juste est **partiel** — il est d'une autre nature que ce
que la portée globale exige désormais de lui.

Ce qui reste critiquable : `admin.controller.ts:669-670` affirme *« il n'existe
plus aucune limite a priori, seulement une trace a posteriori »* **sans
restriction**, alors que le même fichier documente vingt lignes plus haut que 8
sites de **lecture** ont aussi basculé (*« il voyait zéro, il voit désormais
tout »*).

**Le fond** : la lecture est devenue l'acte le plus rentable de l'agent, et
c'est le seul qui ne laisse rien. Une exfiltration du parc est indiscernable
d'une absence totale de connexion. Défaut de redevabilité d'insider — compte
agent valide requis, aucune surface externe.

### 4.5 🟠 La garde d'`avertir` est aveugle sur sa propre branche

`resolveModeration` garde `{ id, moderationStatus: expected }` — ni
`lifecycleStatus`, ni `updatedAt`. Or `avertir` **écrit `NORMALE`**.

```
avertir A (expected=normale) affected: 1  → brouillon / normale
republication du commerçant                → publiee / normale
avertir B (expected=normale) affected: 1  → brouillon / normale   ← aucun 409
```

⚠️ **Une prémisse du constat initial est réfutée** : le cas **nominal** envoie
`signalee` (la file ne contient que ça), et la garde y **mord** — mesuré,
`affected: 0` → 409. `moderation_course.py` le tient déjà, mutation comprise.

Ce qui reste réel : la branche `expected = NORMALE`, chemin **conçu** depuis
l'écran « toutes les promos » (128 promos concernées). `avertir` est la seule des
trois résolutions où c'est destructeur — elle écrit sa propre valeur gardée, donc
se rejoue indéfiniment.

**La perte est celle du commerçant**, pas du modérateur : sa promo corrigée et
republiée est redépubliée par un onglet périmé, et sa republication ayant
rafraîchi `publishedAt`, le cooldown lui **interdit de republier pendant 24 h**.
Il suffit d'**un** modérateur dont l'onglet date de dix minutes.

### 4.6 🟠 Le cache ETag met en défaut les écrans publics pour un utilisateur connecté

`api_client.dart:48` enregistre le cache **avant** l'intercepteur qui pose
`Authorization` (`:50`). Dio 5.10.0 exécute `onRequest` en **FIFO** : au moment
où `_cachable()` teste `containsKey('Authorization')`, l'en-tête n'existe pas
encore.

**Reproduit sur un `ApiClient` réel** :

```
REQUETE 2 : {If-None-Match: W/"v1", Authorization: Bearer jwt-commercant}
RESULTAT  : 304 → ApiException.code = SERVER_UNAVAILABLE
```

Prémisse serveur vérifiée : le backend rend `Vary: Accept-Encoding`, **pas**
`Authorization`.

**Trois corrections du vérificateur** : ce n'est pas « inerte » (l'intercepteur
fonctionne — le défaut est une **asymétrie** entre `onRequest` et
`onResponse`/`onError`) ; ce n'est pas « tous les GET authentifiés » (il faut une
entrée posée en session anonyme — mais `splash_screen.dart:83` envoie **chaque
lancement** vers la vitrine publique, et `EtagCacheStore.vider()` **n'a aucun
appelant**) ; et **la gravité est fonctionnelle, pas confidentielle** — aucune
fuite inter-comptes.

⚠️ **La justification de l'ordre est fausse.** `api_client.dart:39-42` affirme
*« enregistré après, il ne verrait jamais un seul 304 »*. Contrefactuel mesuré,
ordre inversé : le 304 anonyme est **conservé** et le défaut **fermé**. Un
commentaire cru sans mesure a dicté le câblage.

### 4.7 🟡 `on ApiException catch` : code mort qui coupe les rafraîchissements

`notification_provider.dart:49`. L'intercepteur enveloppe toute `ApiException`
dans une `DioException` — mesuré : `REMONTE — DioException`, `.error :
ApiException`, code `NOTIFICATION_NOT_FOUND`. Aucun `throw ApiException` nu dans
`lib/`.

Les quatre appelants n'ont aucun `try`. **Gravité sous-estimée par le constat
initial** : la `Future` non rattrapée ne fait pas qu'échouer, elle **coupe les
trois `ref.invalidate`** qui suivent — la notification reste affichée non lue
alors que le serveur l'a bien marquée. C'est la règle 26, violée dans le seul
endroit que personne n'a relu.

### 4.8 🟡 Autres constats confirmés, sans surface d'attaque

- **Deux commentaires prescriptifs invoquent une garde supprimée** —
  `promo.controller.ts:354-359` (JSDoc de `createByAgent` affirmant l'IDOR
  corrigé, au-dessus d'un corps qui fait l'inverse) et `admin.controller.ts:440`.
  ⚠️ **Le constat initial en annonçait 4 ; 2 tiennent.** Les deux autres sont un
  récit au passé et un commentaire faux depuis le 2026-07-12, sans rapport avec
  le chantier « agent global ».
- **Doublon de signalement concurrent → 500 au lieu du 409 qui existe.**
  Mécanisme confirmé sur les objets réels (`23505` → `AllExceptionsFilter` → 500
  `INTERNAL_ERROR`). Fenêtre mesurée **~2 ms**, **inatteignable depuis l'app**
  (feuille modale d'abord, aucun rejeu, un seul POST). Reste : un refus métier
  déguisé en panne, et un 5xx **actionnable de l'extérieur** dans les journaux.
- **`@Column` en double sur `Agent.tokenVersion`** (`agent.entity.ts:51-52`).
  Aucune faille — une seule colonne est produite. ⚠️ Mais le mécanisme annoncé
  était faux : c'est le **premier poussé** qui gagne, donc la ligne **du bas**.
  Une édition faite sur la ligne 51 est **silencieusement jetée**, et les quatre
  contrôles du projet — dont `migration:generate`, la mesure de vérité
  entité↔base — la déclarent conforme.
- **0 contrainte `CHECK` dans tout le schéma.** Aucune borne métier ne survit à
  un import ou un second client : `prixApres < prixAvant`, latitude/longitude,
  `position > 0`. Le type est bon, le domaine n'est nulle part.
- **`moderationStatus` non indexé** — sélectivité 1,3 %, deux `Seq Scan` de
  `promo` par chargement de la file, payés par chaque agent du pays.
  **`audit_log` n'a aucun index hors la clé primaire**, et aucune purge.
- **`createdByAgentId`** écrit à la création, **lu par personne** — le dernier
  lien agent↔parc du modèle (règle 31).
- **Commentaire périmé** `report.service.ts:129-135`, qui décrit encore la
  modération comme non protégée depuis le 2026-08-13.

---

## 5. Constats RÉFUTÉS ou corrigés — à écrire, sinon on les redécouvrira

### 5.1 ❌ RÉFUTÉ — « le routeur ouvre les 24 routes à rôle pendant le chargement »

Le défaut technique est réel (`_load()` sans `try/catch`, état figé en `loading`,
et `return null` laisse bien passer). **La conséquence de sécurité n'existe
pas** : les routes ne sont pas adressables (intent-filter borné à `/p`, AASA
`/p/*`, aucun schéma personnalisé, aucun `restorationScopeId`), la fenêtre et la
navigation interne s'excluent, et même en concédant une arrivée le token est
`null` → 401 → `logout()` → redirection, sur un écran vide.

**Ce qui reste** : un commerçant légitime, après restauration de téléphone,
silencieusement déconnecté sans message. Robustesse, pas sécurité.

### 5.2 ⚠️ CORRIGÉ — deux attributions causales fausses dans le pentest du 2026-08-05

Pas une faille produit : une **fausse assurance dans le document qu'on lit pour
clore le sujet**. Les résultats mesurés (400, 401) sont réels ; leurs
**explications** sont inventées.

- **`forbidNonWhitelisted`** (lignes 94, 133) : absent de `main.ts`, et
  `git log -S` sur l'historique rend vide — il n'a **jamais** existé. Mesuré :
  `GET /promo?limit=1&evil=x` → **200**, champ silencieusement effacé. La sonde
  envoie `"reason":"AUTRE"` alors que l'enum vaut `'autre'` : son 400 vient
  d'`@IsEnum` seul. Tes propres commentaires du 2026-08-13
  (`list-promo-query.dto.ts:37-43`) documentent déjà cette absence.
- **`algorithms: ['HS256']`** (lignes 72, 128) : `HS256` n'apparaît **que dans le
  rapport**. Et poser l'épinglage serait un **garde-fou décoratif** — mesuré, le
  refus d'`alg:none` vient de la **signature vide**, *avant* toute comparaison
  d'algorithme :

  ```
  alg:none sans options           → REFUSE : jwt signature is required
  alg:none avec algorithms:HS256  → REFUSE : identique
  ```

  Le seul jeton que l'épinglage refuserait est signé HS384 **avec le vrai
  secret** — quiconque l'a peut signer en HS256.

**Action** : corriger les lignes 72, 94, 128, 133 du rapport. **Ne pas** ajouter
l'épinglage pour faire taire le constat.

### 5.3 ⚠️ CORRIGÉ — le décalage de fuseau ne vaut qu'en développement, et son sens était inversé

Réel sur WSL : l'API rend `createdAt` **2 h dans le passé** (12 colonnes
`timestamp without time zone`, paramètres `Date` sérialisés en heure locale).

**Deux réfutations de portée :**
- **En production, le décalage est nul.** `node:22-alpine` n'a pas de
  `/etc/localtime` → UTC → offset 0 → fenêtre exactement 24 h. Aucun `TZ` posé
  nulle part dans le dépôt.
- **Le premier compte portait sur le mauvais objet** : totaux tous commerçants
  confondus, alors que la garde compte **par commerçant**. Recompté :
  `refusés_24h = 10`, `refusés_22h = 10`, **0 divergent**.

Et le **signe** est l'inverse : la fenêtre est plus **courte** → le plafond
refuse **moins**. Ce n'est pas un plafond qui enferme, c'est **un anti-abus qui
fuit de 2 h par cycle**.

⚠️ **Le vrai risque résiduel** : rien n'épingle le `TZ` du conteneur. Poser
`TZ=Africa/Algiers` pour des journaux lisibles rallume le défaut en production —
et un fuseau à l'ouest d'UTC produirait cette fois de **faux refus**.

### 5.4 ⚠️ CORRIGÉ — stockage mobile : le fait est réel, les deux conséquences sont fausses

- **Clonage du `device_id` : réfuté et inversé.** Les gardes sont des **index
  d'unicité**, pas des quotas (`COUNT(DISTINCT deviceId)`,
  `@Index(['promoId','deviceId'], unique)`). Un identifiant cloné est un
  **doublon** : il consomme un quota déjà consommé. Trois chaînes aléatoires sont
  gratuites et strictement meilleures pour un attaquant.
- **JWT restaurable : réfuté sur les deux plateformes.** Android : clé AES
  enveloppée par une clé RSA du Keystore, non exportable — la sauvegarde emporte
  le chiffré et rien pour l'ouvrir (*c'est exactement le mécanisme qui produit
  §5.1*). iOS : `synchronizable: false` par défaut, l'entrée n'est pas dans le
  trousseau iCloud.
- **Épinglage de certificat** : son absence est acceptable (HTTPS seul, `minSdk
  24` n'approuve pas les autorités utilisateur, et un épinglage ajoute un mode de
  panne dur). **C'est l'absence de trace écrite de cette décision qui est le
  constat.**

**Ce qui survit** : position GPS, favoris, `device_id` et cache ETag partent dans
Auto Backup faute de `dataExtractionRules`. Et à `targetSdk 36`,
`allowBackup="false"` **seul ne suffirait pas** — il faut les deux sections
`cloud-backup` **et** `device-transfer`. 🟡 vie privée, pas autorisation.

---

## 6. Ce qui n'a PAS été testé

- **C7 — le client réel sur appareil.** Aucun émulateur lancé. Restent entiers :
  le rendu clair/sombre, **le RTL** (`role_choice_screen.dart:62-66` épingle le
  sélecteur de langue en `Alignment.centerRight` — en arabe il atterrit dans le
  coin opposé à celui qu'on balaie, sur le seul écran que voit un utilisateur qui
  ne lit pas le français), les permissions natives réellement demandées, **les
  JPEG temporaires jamais supprimés** (dont le registre de commerce), l'absence
  de `FLAG_SECURE`, et l'assemblage.
- **La frontière HTTP** (`frontiere-http`) — sautée sur 429.
- **La frontière commerçant↔commerçant** (`commercant-b`) — code 2.
- **Les plans SQL** (`plan-sql`) — `psycopg2` absent.
- **La concurrence réelle** : les bancs sont séquentiels. **Aucun** des constats
  §4.2, §4.5 et §4.8 n'est à leur portée.
- **La production** : ni TLS, ni en-têtes réels, ni ACL OVH — d'où les « reste à
  prouver » de §4.1 et §5.3.
- **La chaîne de construction** (codemagic), les sauvegardes et leur
  restauration, le déni de service, l'accessibilité mesurée.

---

## 7. Reproductibilité

```sh
# C6 — les bancs (décor d'abord, puis coller le bloc export)
./scripts/provision-decor.sh
ATTENDU_LAT=34.6703 ATTENDU_LNG=3.2630 ./scripts/test-tout.sh

# C3/C4/C5 — hors du lanceur : réseau + démon de conteneurs requis
sh scripts/audit-dependances.sh   [--self-test]
sh scripts/audit-image.sh         [--self-test]
sh scripts/audit-secrets.sh       [--self-test]

# C2 — statique (sans installation)
docker run --rm -v "$PWD:/repo:ro" -w /repo semgrep/semgrep semgrep scan \
  --config=p/typescript --config=p/nodejsscan --config=p/security-audit \
  --config=p/owasp-top-ten --metrics=off apps/backend/src
```

Chaque script d'audit porte son `--self-test`. **Un outil qui n'a pas su refuser
n'est pas installé.**

---

## 8. Recommandations

### Corrige le 2026-08-14 (commit `3eaa008`)

| # | Action | Preuve |
|---|---|---|
| 1 | 🔴 `mc anonymous set download` ne porte plus que sur les **trois dossiers publics** — `registre-documents/` sort du perimetre anonyme (§4.1a) | forme calquee sur la production, ou seule l'ACL par objet agit |
| 3 | 🔴 `update` cible dans `publish()` et `stop()` (§4.2) | **prouve par mutation** — voir ci-dessous |
| 7 | 🟠 ordre des intercepteurs Dio inverse, et le commentaire faux corrige (§4.6) | `flutter test` 23/23, `analyze` 0 |
| 8 | 🟠 les 4 lignes fausses du pentest du 2026-08-05 corrigees (§5.2) | — |
| 10 | 🟡 `apiErrorCode(error)` au lieu de `on ApiException catch` (§4.7) | `check_all` 4/4 |
| 12 | 🟡 `TZ=UTC` epingle dans le `Dockerfile` (§5.3) | transforme un accident en invariant |
| 13 | 🟡 `dataExtractionRules` **et** `fullBackupContent`, deux fichiers au format distinct (§5.4) | Android a change de schema a API 31 |
| 14 | 🟡 `@Column` en double supprime (§4.8) | — |
| 15 | 🔴 `frontiere-http` et `commercant-b` rejoues : **141 sondes / 49 routes, 0 echec** (§3.6) | le trou de couverture est ferme |

#### La preuve par mutation du n°3

Le banc deterministe — verrou consultatif tenu depuis psql pour elargir la
fenetre a volonte — a ete joue **contre les deux versions du code** :

```
code MUTE (manager.save(promo), version d'avant)  ->  publiee / normale   <- decision ECRASEE
code CORRIGE (manager.update cible)               ->  publiee / masquee   <- decision INTACTE
```

Le banc **sait donc refuser**. Sans cette seconde execution, le vert n'aurait
prouve que sa capacite a dire oui.

### NON corrige, et pourquoi — un constat qu'on ne corrige pas doit etre ecrit

| # | Action | Pourquoi pas maintenant |
|---|---|---|
| 2 | 🔴 **Verifier sur OVH que l'ACL `private` par objet est effective** (§4.1) | **non mesurable depuis ce poste.** C'est la ligne de partage entre « dev casse par sa compose » et « prod exposee 15 min au porteur ». **Le correctif n°1 ne referme PAS ce point.** |
| 4 | 🟠 `trust proxy <IP de Traefik>` (§4.3) | demande l'IP ou le sous-reseau reel de Traefik, que je n'ai pas. Poser une valeur au hasard serait pire que le compteur actuel |
| 5 | 🟠 compteur de tentatives **par compte** (§4.3) | fonctionnalite, pas correctif — et c'est le seul filet independant de la topologie |
| 6 | 🟠 `WHERE` des trois resolutions de moderation (§4.5) | le vrai remede est un `expectedUpdatedAt` : **changement d'API + 3 ecrans**. Un demi-correctif serait une hypothese de plus, pas une correction |
| 9 | 🟠 journaliser les lectures privilegiees, ou ecrire l'exemption (§4.4) | **decision produit** — journaliser chaque lecture de liste gonfle le journal d'un ordre de grandeur et noie les ecritures |
| 11 | 🟡 rebuild/pull des images (§3.4) | a faire au prochain deploiement ; sans effet sur le code |
| 16 | 🔴 **ne jamais creer le couple telephone/PIN de `.gitleaksignore` en production** (§3.5) | **permanent, et non corrigeable** — le secret est dans l'historique |
| — | `plan-sql` (§3.6) | `pip` absent du Python de la WSL. Trou d'environnement, portant sur des plans de requete |
| — | **C7 — le client sur appareil** (§6) | demande l'emulateur. Reste la couche au meilleur rendement par heure |

> **Tenir ce tableau a jour fait partie du controle.** Un etat perime fait
> conclure : un lecteur qui s'y fie refait le travail, ou l'inscrit a tort comme
> bloquant.
