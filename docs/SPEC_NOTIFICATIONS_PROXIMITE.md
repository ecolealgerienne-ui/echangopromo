# SPEC — Notifications de proximité (client)

> **État : spécification, rien n'est implémenté.** Écrit le 2026-08-17, avant
> tout code. Le suivi d'avancement vit dans `docs/status_v0.1.md`, pas ici.

Notifier un client anonyme quand une promo est publiée **dans le cercle qu'il a
lui-même enregistré**. C'est le premier élément de la phase 2 annoncée par
`SPECS_ECHANGO_PROMO_V0.md` §7 (« notifications push géolocalisées »).

Ce document suppose lus `docs/PLAN_BASCULE_GEO.md` — dont la **§2.1** est la
contrainte structurante de tout ce chantier — et les règles de `CLAUDE.md`.

---

## 1. Ce qui n'existe pas aujourd'hui

Mesuré le 2026-08-17. Aucune des quatre briques n'est présente ; ce n'est pas un
« presque fait ».

| Brique | État |
|---|---|
| Destinataire client | ❌ `NotificationRecipientType` ne connaît que `COMMERCANT`, `AGENT`, `ADMIN` (`notification.entity.ts:35`) |
| Transport push | ❌ zéro occurrence de `firebase_messaging`, `flutter_local_notifications`, OneSignal ou token d'appareil dans le dépôt |
| Identité client persistante | ❌ le client est anonyme ; seul un `X-Device-Id` **déclaratif** existe, et il n'identifie rien |
| Position client côté serveur | ❌ elle transite en **paramètre de requête** (`latitude`/`longitude`/`radiusKm` de `ListPromoQueryDto`) et vit dans les `SharedPreferences` de l'appareil (`client_position_store.dart`) |

Le module `notification` existant reste **in-app et en pull** : l'app liste et
compte, rien n'est poussé. Il n'est **pas** réutilisé ici — voir §11.

---

## 2. Décisions

Prises en discussion les 2026-08-17. Numérotées pour être citables.

| # | Décision |
|---|---|
| N1 | Le déclencheur est la **publication d'une promo**, en temps quasi réel. Pas de résumé périodique. |
| N2 | Le périmètre est le **cercle que le client a enregistré** : son point (③ de la §2.1 du plan géo) et le rayon qu'il a cadré. |
| N3 | S'il n'a **rien cadré** (`rayonKm` absent), le **rayon serveur par défaut** s'applique — le même que sa liste utilise déjà. |
| N4 | **Aucun plafond de volume.** Recevoir beaucoup et couper est une décision assumée du client. |
| N5 | L'interrupteur est **tout ou rien**. Pas de granularité par catégorie ni par favori. |
| N6 | Couper **supprime la ligne serveur**. Ce n'est pas un booléen mis à `false`. |
| N7 | Transport **FCM** (API HTTP v1) pour les deux plateformes. |
| N8 | **Android d'abord.** iOS reçoit le code mais **n'est pas republié** dans ce cycle. |
| N9 | Aucun capteur, aucun suivi en arrière-plan. **La décision 12 du plan géo reste intacte** et n'est pas rouverte. |

### 2.1 ⚠️ Ce que N9 protège, et pourquoi c'est le point le plus important

La §2.1 de `PLAN_BASCULE_GEO.md` distingue quatre données dont **une seule**
quitte l'appareil : ③, le point que le client enregistre lui-même — une
**préférence saisie**, pas une mesure.

Cette spec n'ajoute **aucune** donnée de localisation nouvelle : elle réutilise
③, déjà transmis après consentement depuis la décision 10. Ce qu'elle ajoute est
un **identifiant d'installation** (le token FCM), et c'est cela, et seulement
cela, qu'il faut déclarer aux stores et dans les CGU (§12).

⚠️ **Toute dérive vers ④ (le capteur, en arrière-plan) sort de cette spec** et
fait mentir d'un coup les CGU, l'`Info.plist` et les deux fiches store. Le
geofencing temps réel — « tu passes devant la boutique » — a été **écarté** en
discussion pour cette raison. Il n'est pas interdit à jamais ; il est un autre
chantier, avec sa propre décision produit et son propre passage store.

---

## 3. Modèle de données

Une table, `client_push_subscription`. **C'est la première identité client
persistante du produit.**

| Colonne | Type | Note |
|---|---|---|
| `id` | uuid PK | clé technique |
| `token` | text, **unique** | le token FCM. C'est lui, l'identité |
| `platform` | enum `android` \| `ios` | pour diagnostiquer, et pour ne pas envoyer vers iOS avant N8 levée |
| `latitude` | double precision, NOT NULL | copie de ③ |
| `longitude` | double precision, NOT NULL | copie de ③ |
| `rayonKm` | double precision, **NULL autorisé** | voir §3.2 |
| `createdAt` / `updatedAt` | timestamptz | |

### 3.1 ⚠️ Pas de colonne `deviceId`, et ce n'est pas un oubli

Le `X-Device-Id` est **déjà** stocké dans `report`, `promo_view` et
`commercant_view`. Le porter aussi ici en ferait la **jointure qui
dé-anonymise les signalements** : « qui a signalé quelle promo » relié à « qui
se trouve à ces coordonnées ».

Aujourd'hui cette jointure n'existe pas, et c'est précisément ce qui rend le
`X-Device-Id` inoffensif malgré son caractère déclaratif. Le token FCM suffit
comme identité — il est déjà unique par installation, et le supprimer efface
tout.

**Aucune clé étrangère non plus** : cette table ne référence ni commerçant, ni
promo, ni rien. Elle est un point et un tuyau.

### 3.2 ⚠️ `rayonKm` reste nullable, et on ne matérialise pas le défaut

Un client qui a posé son point avant la version du 2026-08-14, ou qui l'a posé
sans cadrer, **n'a pas de rayon** (`position_providers.dart:46-49`). La décision
N3 dit d'appliquer le rayon serveur — mais **au moment de l'envoi**, jamais en
l'écrivant dans la ligne.

Écrire `5` à l'inscription figerait ces clients sur la valeur du jour : le
lendemain où `CLIENT_DEFAULT_RADIUS_KM` change dans le `.env`, ils resteraient
sur l'ancienne, et **rien ne le dirait**. C'est la règle 29 dans sa forme
exacte : un défaut posé détruit l'information d'absence.

### 3.3 L'index — copier `IDX_commercant_position`, à l'identique

```sql
CREATE INDEX "IDX_client_push_subscription_position"
  ON "client_push_subscription"
  USING gist (point("longitude", "latitude"));
```

Le type `point` et l'opérateur `<@` sont **natifs** dans PostgreSQL, avec un
opclass GiST fourni en standard. **PostGIS n'est pas installé et ne doit pas
l'être** — voir la justification complète dans
`1783880000000-CommercantPositionGistIndex.ts`, qui a mesuré le gain (53 lignes
justes contre 101 remontées par un btree à deux colonnes).

⚠️ **`point(x, y)` attend `point(longitude, latitude)`** — l'ordre est inversé
par rapport à tout le reste du produit, qui dit « lat, lng ». Un index construit
dans un ordre et interrogé dans l'autre **ne lève aucune erreur** : il rend des
résultats faux, silencieusement, et seulement pour les points où l'inversion
sort du cadre. Le banc doit comparer un décompte SQL à un décompte applicatif,
comme `test-plan-sql.sh` le fait déjà.

⚠️ **Ne PAS déclarer cet index avec `@Index()` sur l'entité.** Le décorateur
TypeORM ne sait décrire que des colonnes : le déclarer ferait dire au modèle un
btree que la base n'a pas, et `migration:generate` proposerait de remplacer le
GiST par un btree **à chaque exécution**. C'est le miroir assumé de la règle 12,
déjà documenté sur `commercant.entity.ts:78-93`. Le garde-fou n'est pas le
décorateur, c'est la mesure : **`migration:generate` doit rendre vide** après
cette migration, et ça se vérifie.

L'unicité de `token`, elle, est une contrainte de colonne ordinaire et se
déclare normalement.

---

## 4. Les routes

Deux, toutes deux **publiques** — le client est anonyme par conception, il n'y a
pas de jeton à présenter.

### `PUT /client/push-subscription`

**Idempotent par token.** Les tokens FCM tournent sans prévenir : la même
installation reviendra avec un token neuf, et l'ancien deviendra mort. Un
`INSERT … ON CONFLICT (token) DO UPDATE` est le comportement attendu, pas une
création à chaque appel.

Corps : `token`, `platform`, `latitude`, `longitude`, `rayonKm?`.

### `DELETE /client/push-subscription`

L'interrupteur. **Supprime la ligne.**

⚠️ **Il doit refuser quand il n'a rien supprimé** — `404`, avec un code dédié.
C'est exactement la leçon de `markAsRead` (2026-08-05, § journal de
`status_v0.1.md`) : un geste sans effet annoncé comme réussi laisse l'app
rafraîchir son état en croyant l'avoir changé. Ici la conséquence est pire que
sur une notification lue : un client dont le token a tourné entre-temps croirait
avoir coupé, et **continuerait de recevoir**.

### 4.1 ⚠️ Épinglage obligatoire dans `frontiere_http.py`

`ROUTES_OUVERTES` passe de **14 à 16 entrées**, chacune avec sa justification —
et le commentaire « Les 14 routes ouvertes » en tête du dictionnaire est à
mettre à jour dans le même commit, sinon il devient un compteur faux.

Rappel de la règle 33 : ici, **la route qu'on oublie est OUVERTE**, et l'oubli
ne se voit ni à la compilation, ni à l'exécution, ni dans les journaux.

### 4.2 ⚠️ Un seau de throttling DÉDIÉ, jamais `SENSITIVE_ACTION_THROTTLE`

`SENSITIVE_ACTION_THROTTLE` (20/min) est un **seau partagé** par les écritures
authentifiées. Y verser une route publique et anonyme créerait exactement le
défaut qui a forcé le relèvement d'`AUTH_THROTTLE` de 5 à 50 le 2026-08-13 :
**le NAT opérateur du parc mobile algérien met des milliers de clients derrière
une même IP**. Quelques clients anonymes ouvrant leur app épuiseraient le budget
d'écriture d'un commerçant partageant leur sortie réseau, qui verrait ses
publications refusées sans comprendre.

Un seau `PUSH_THROTTLE` propre, dimensionné pour un appel au démarrage plus les
changements de point.

### 4.3 DTO borné, pas seulement décoré (règle 34)

- `token` : `@IsString()` **et** `@MaxLength()` — un token FCM fait quelques
  centaines de caractères ; sans borne, c'est une colonne `text` alimentée
  librement par une route publique.
- `latitude` / `longitude` : `@IsLatitude()` / `@IsLongitude()`, et **les deux
  ensemble** (`@ValidateIf`), sur le modèle de `ListPromoQueryDto:104-125` — une
  latitude seule est une requête cassée, pas une requête sans position.
- `rayonKm` : **refusé** au-delà de `CLIENT_MAX_RADIUS_KM`, jamais raboté. Le
  précédent est `promo.service.ts:909`, et sa justification vaut ici mot pour
  mot : l'app lit `maxRadiusKm` sur `GET /promo/config` et n'a aucune raison de
  dépasser ; une requête qui dépasse est soit un client cassé, soit un abus.
- `platform` : `@IsEnum`.

Et les `ErrorCode` ajoutés obtiennent leur entrée dans les **trois** mappings
mobile dans le même commit (règle 26).

---

## 5. Le déclenchement

### 5.1 Rien dans la requête de publication

Le commerçant écrit sa promo, reçoit son `201`, terminé. **Aucun appel réseau
vers Google pendant qu'il attend.** Si FCM est lent ou en panne, sa publication
n'en sait rien.

### 5.2 Un cron court, pas une file d'attente

Il n'y a pas de file d'attente dans la stack, et en ajouter une pour ça serait
disproportionné. `@nestjs/schedule` est déjà présent et déjà utilisé (purge des
notifications, « expire bientôt ») : **zéro composant nouveau**.

Le cron ramasse les promos publiées et non encore notifiées, et sert chacune.

Le prix est une latence de quelques minutes. Pour une promo de quartier, ce
n'est pas un défaut.

### 5.3 ⚠️ Le marqueur, et l'arbitrage qu'il impose

Sans marqueur de ce qui a déjà été servi, un cron qui meurt au milieu d'un lot
**renotifie tout le monde** au redémarrage. Ce n'est pas une charge en régime
normal ; c'est ce qui arrive le jour où ça casse — et sans plafond (N4), recevoir
deux fois la même promo est précisément ce qui fait couper l'interrupteur.

Le marqueur retenu : une colonne `pushNotifiedAt` (timestamptz, **nullable**) sur
`promo`. `NULL` = jamais servie, et c'est une absence réelle, pas un défaut posé.

**Elle est écrite AVANT l'envoi, pas après.** Le choix est explicite :

| | Marquer après | **Marquer avant** ✔ |
|---|---|---|
| Sur crash en cours de lot | la promo est **renvoyée en entier** au passage suivant | la promo n'est **pas** renvoyée |
| Défaut produit | doublons, silencieux, chez des gens qui couperont | notification manquée |

⚠️ Marquer avant crée une absence — et une absence non dite est exactement ce
que la règle 29 interdit. Elle est donc **journalisée explicitement** : l'échec
d'envoi écrit une ligne nommant la promo et le nombre de destinataires perdus.
L'information n'est pas détruite, elle est déplacée. C'est le même compromis, et
la même justification, que le repli de `configNumber`.

⚠️ **Fenêtre de ramassage** : ne traiter que les promos publiées **avant**
l'instant de démarrage du passage, sinon une promo publiée pendant l'exécution
peut être vue à moitié.

### 5.4 L'envoi

⚠️ **Le point d'entrée en lot de FCM a été retiré par Google.** Le SDK envoie
désormais **une requête HTTP par destinataire**, en parallèle. Cinq cents
destinataires, cinq cents appels réseau. *(À revérifier au moment de
l'implémentation : ce point a bougé récemment.)*

Deux gardes obligatoires, faute de quoi un lot lent retient le passage suivant
et les promos s'accumulent :

- un **plafond de concurrence** (`PUSH_SEND_CONCURRENCY`) ;
- un **délai d'expiration** par envoi — `withTimeout` (`common/async/with-timeout.ts`)
  existe déjà et c'est son cas d'emploi.

### 5.5 La purge des tokens morts

FCM répond `UNREGISTERED` (ou équivalent) quand l'app a été désinstallée ou la
permission retirée dans l'OS. Il faut **supprimer la ligne**, pas seulement
journaliser l'échec.

Sinon la table accumule des fantômes, et surtout **tout compteur d'envoi ment** :
le serveur croit notifier N personnes, personne ne reçoit. C'est le cas
particulier de « la révocation OS n'est pas notifiée à l'app » — l'utilisateur
peut couper les notifications depuis les réglages du téléphone, et le serveur ne
l'apprend que par ce retour.

---

## 6. La requête de proximité

C'est **l'inverse** de la requête d'aujourd'hui :

| | Liste client (existant) | Notification (nouveau) |
|---|---|---|
| Question | quelles promos près de **ce client** ? | quels clients près de **cette promo** ? |
| Point fixe | le client | la promo |
| Rayon | un seul, celui de la requête | **un par ligne**, propre à chaque abonné |

Même géométrie, sens opposé — et **un index qui sert l'une ne sert pas l'autre**.

### 6.1 ⚠️ Le rayon variable, et ce qui rend la requête indexable

Aucun index spatial ne sait interroger « les points dont *leur propre* cercle
contient ce point ». Ce qui sauve la requête, c'est **le plafond
`CLIENT_MAX_RADIUS_KM`** — décidé le 2026-08-14 pour une tout autre raison
(« echango Promo est un service de proximité, pas un site d'annonces
national »).

Aucun abonné situé au-delà du plafond ne peut matcher, **quel que soit son
rayon**. D'où un filtrage en deux temps :

1. **Pré-filtre par boîte englobante du rayon MAXIMUM** autour de la promo —
   c'est lui qui emprunte l'index GiST. Il ne dépend d'aucune valeur de ligne.
2. **Distance exacte en haversine** sur le petit ensemble restant, comparée à
   `COALESCE("rayonKm", <défaut serveur>)` — c'est là que N3 s'applique.

Réutiliser la formule de `PromoService.distanceKmSql` (`promo.service.ts:433`),
y compris son `LEAST(1, GREATEST(-1, …))` : sans cette borne, `acos` déborde
d'un epsilon quand l'abonné est **exactement** sur le point de la promo, et
Postgres lève `input is out of range`.

⚠️ Cette formule vivrait alors à **deux endroits**. Règle 30, appliquée
littéralement : si l'un change, l'autre doit changer ⇒ **un seul endroit**. Elle
doit être extraite avant d'être réutilisée, pas recopiée avec un commentaire
« même formule que ».

En production `CLIENT_MAX_RADIUS_KM` vaut **5 km** : la boîte fait environ
0,09° de côté. Le candidat est minuscule.

---

## 7. Le consentement et l'interrupteur

### 7.1 ⚠️ Un seul consentement, pas deux — le point le plus délicat du chantier

`ClientPositionController.retirer()` (`position_providers.dart:121-124`) efface
aujourd'hui le point **et** le consentement ensemble, toujours. Il doit désormais
**supprimer aussi l'abonnement push**.

Sans ça, un client qui retire sa position continue de recevoir des notifications
calculées sur un point qu'il croit effacé. C'est le défaut le plus grave de
cette spec, et le plus silencieux : rien à l'écran ne le contredit.

Deux consentements indépendants finiraient par diverger. **Ils sont donc liés**,
dans ce sens : *pas de point ⇒ pas de notification*. La réciproque est libre —
couper les notifications ne retire pas le point, puisque la liste continue d'en
avoir besoin.

### 7.2 ⚠️ Le point qui bouge doit mettre à jour l'abonnement

Un client qui déplace son point ou change son cadrage, et dont l'abonnement
garde les anciennes coordonnées, sera notifié **sur son ancien quartier**
indéfiniment. Même classe de défaut, même invisibilité.

`invalidateAfterPositionChange` (`position_providers.dart:193`) est la fonction
nommée qui centralise déjà les suites d'un changement de point. La mise à jour
de l'abonnement passe par **elle**, jamais par un appel recopié dans chaque
écran — règle 37, dont c'est le cas d'école : le défaut n'apparaît qu'au
**retour** sur un écran, après l'action qui vient de changer la donnée.

### 7.3 L'interrupteur, tel que le client le voit

Un seul réglage (N5). Trois états à ne jamais confondre :

| | Où il vit | Qui le change |
|---|---|---|
| ① Permission OS | iOS / Android 13+ | l'utilisateur, **hors de l'app, sans que l'app en soit prévenue** |
| ② Réglage dans l'app | l'écran de réglages | l'utilisateur, dans l'app |
| ③ Abonnement serveur | la ligne `client_push_subscription` | le serveur |

**Le seul « off » qui compte est ③.** Si couper ne faisait que jeter le message à
l'arrivée, le serveur continuerait de calculer et d'envoyer — et « le client a
coupé » deviendrait indiscernable de « rien à proximité ».

① se perd sans prévenir ; c'est §5.5 qui la rattrape, a posteriori.

---

## 8. Mobile

1. `firebase_core` + `firebase_messaging`, `google-services.json`. **Le build
   Android bouge** : c'est là que ressort l'historique PKIX / analyse HTTPS de
   l'antivirus décrit au § Environnement de `CLAUDE.md`.
2. Permission `POST_NOTIFICATIONS` (Android 13+), demandée **au moment du geste**,
   pas au démarrage.
3. Le réglage, avec ses chaînes dans les **trois** `.arb` (règle 27).
4. Le branchement de §7.1 et §7.2.
5. **iOS : le package est présent, l'entitlement n'est pas activé, et on ne
   publie pas iOS ce cycle** (N8). C'est cette dernière clause, et elle seule,
   qui économise une seconde soumission — voir §10.

⚠️ **Règle 31** : la route n'est pas finie tant qu'un écran ne l'appelle pas.
`PUT` et `DELETE` doivent avoir leur appelant dans le même commit que leur
création.

---

## 9. Configuration

Règle 36 — **trois endroits, même commit** :

| | |
|---|---|
| `apps/backend/.env.example` | versionné |
| `.env.production.example` | versionné, **à la RACINE du dépôt** |
| `~/projects/echangopromo/apps/backend/.env` | **hors dépôt**, dans WSL, à la main |

⚠️ Les deux `.example` **ne sont pas dans le même dossier**, et ce piège a déjà
coûté le 2026-08-14. Chercher une **clé**, pas un fichier :
`grep -rn "PUSH_" --include=".env*" .` depuis la racine.

Clés à ajouter :

| Clé | Rôle |
|---|---|
| `FCM_PROJECT_ID` | projet Firebase |
| `FCM_SERVICE_ACCOUNT_JSON` | **secret** — la clé de compte de service |
| `PUSH_SCAN_INTERVAL_MINUTES` | période du cron (§5.2) |
| `PUSH_SEND_CONCURRENCY` | plafond de parallélisme (§5.4) |
| `PUSH_SEND_TIMEOUT_MS` | délai d'expiration par envoi (§5.4) |
| `PUSH_THROTTLE` | le seau dédié (§4.2) |

Toute lecture numérique passe par `configNumber` (`common/config/`) — un
`configService.get<number>` ne convertit **rien**, le `<number>` est une
assertion effacée à la compilation et la valeur arrive en **chaîne**.

`FCM_SERVICE_ACCOUNT_JSON` obtient une entrée dans `.gitleaks.toml`.

---

## 10. Charge, et coût réel

**Zéro euro de licence.** FCM est gratuit sans plafond de volume, les packages
Flutter sont open source, APNs passe par le compte développeur Apple déjà payé.

La charge se formule :

```
pushes / jour  =  publications / jour  ×  abonnés dans le rayon
```

avec une borne haute structurelle : un commerçant est plafonné à **5 créations /
24 h**, donc `publications/jour ≤ commerçants actifs × 5`.

⚠️ **Ce n'est pas le nombre de commerçants qui fait changer de régime, c'est la
densité d'abonnés** — les deux facteurs grandissent ensemble dans une même
ville, donc le coût grandit comme leur **produit**.

Postgres n'est pas le goulot : la boîte de 5 km est minuscule et indexée. **La
charge est dans les envois FCM**, linéaires (§5.4).

Les coûts non financiers, eux, sont réels : un secret de production de plus, un
passage en revue Apple (différé par N8), le temps de build Android, et deux
textes à mettre à jour (§12).

⚠️ **FCM suppose les Google Play Services sur l'appareil.** Les terminaux qui en
sont dépourvus ne recevront rien, **sans aucune erreur visible**. À arbitrer si
la part de ces appareils dans le parc visé devient significative.

---

## 11. Ce que cette spec ne fait pas

Une exclusion non écrite est indiscernable d'un oubli.

| Écarté | Pourquoi |
|---|---|
| Geofencing temps réel (« tu passes devant ») | demande ④, le capteur en arrière-plan — rouvrirait la décision 12 du plan géo, les CGU, l'`Info.plist` et deux fiches store |
| Plafond de fréquence | N4, décision assumée |
| Granularité par catégorie ou favori | N5. Les favoris sont d'ailleurs en stockage **local** (`favoriteIds` passé en requête) : les cibler demanderait un second chantier d'identité client |
| Réutilisation du module `notification` | il est in-app, en pull, adressé à des rôles **authentifiés**, et sa table porte un `recipientId` typé `uuid` qui n'a pas de sens pour un anonyme. Deux mécanismes distincts, assumés |
| Historique des notifications côté client | rien n'est stocké : la notification est poussée, pas consultable après coup |
| iOS dans ce cycle | N8 |

---

## 12. Stores et textes légaux

**Ce ne sont pas des formalités**, et ils sont dans le chemin critique de la
livraison Android, pas après.

- **Play Console, formulaire *Data safety*** : le token push est un identifiant
  d'appareil **collecté**, ce qui n'était pas le cas jusqu'ici. À déclarer.
- **CGU et politique de confidentialité** : nouvelle donnée, nouvelle finalité.
  La §2.1 du `PLAN_BASCULE_GEO.md` est écrite au cordeau ; y ajouter une donnée
  sans mettre les textes à jour ferait mentir l'ensemble.
- **Ce qui ne change PAS**, et qu'il faut savoir dire : aucune donnée de
  localisation nouvelle n'est collectée (§2.1 de ce document). La position
  utilisée est ③, déjà transmise après consentement.

Pour iOS, le jour venu : dérouler `docs/RETOURS_APPLE.md` avant soumission.

---

## 13. La preuve

### 13.1 Le banc

`test-notifications-client.sh` + `scripts/lib/notifications_client.py`, sur le
modèle des bancs existants. Il doit **savoir refuser** (règle 28) — autant de cas
qui échouent que de cas qui passent :

| Cas | Attendu |
|---|---|
| abonné dans le rayon | **reçoit** ← le témoin, voir 13.2 |
| abonné hors du rayon | ne reçoit pas |
| abonné qui a coupé (`DELETE`) | ne reçoit pas |
| abonné sans `rayonKm` | reçoit selon le **défaut serveur** (N3) |
| `PUT` avec un token déjà connu | met à jour, **ne duplique pas** |
| `DELETE` sur un token inconnu | **refuse** (§4) |
| `rayonKm` > `CLIENT_MAX_RADIUS_KM` | **refusé**, pas raboté |
| token mort au retour FCM | ligne **supprimée** (§5.5) |
| décompte SQL vs décompte API | **identiques** — détecte l'inversion lat/lng (§3.3) |

### 13.2 ⚠️ Le témoin est obligatoire ici

Avant d'affirmer « l'abonné éloigné n'a rien reçu », **établir que l'abonné
proche a reçu**. Sans ça le banc est vert parce que la chaîne entière est morte —
FCM mal configuré, cron non démarré, table vide : tous produisent le même
silence que le comportement correct.

C'est la règle 38 dans sa forme la plus directe, et le principe général du dépôt :
*le silence est aussi ce que rend un contrôle qui n'a pas tourné.*

### 13.3 La mutation

Inverser la comparaison de rayon dans la requête de §6.1 : le banc doit virer au
rouge. Un banc qui reste vert sous mutation n'a rien mesuré.

### 13.4 ⚠️ Ce que ce banc ne prouvera PAS, et il faut l'écrire d'avance

**Un script ne reçoit pas une notification push.** Il peut vérifier ce que le
serveur a **décidé** d'envoyer et à qui — pas la livraison.

Le transport doit donc être derrière une interface, avec une implémentation
enregistreuse en environnement de test, et les assertions portent sur
**l'ensemble des destinataires retenus**.

La livraison réelle ne se prouve que **sur appareil** — la couche 7 de la méthode
d'audit. Le déclarer ici évite qu'un vert de banc passe pour une preuve de bout
en bout.

---

## 14. Ordre de mise en œuvre

Chaque étape rend la suivante possible. Le chemin critique est 1 → 2 → 3.

| # | Étape | Fin d'étape prouvée par |
|---|---|---|
| 1 | Entité, migration, index GiST | `migration:generate` rend **vide** |
| 2 | Routes `PUT`/`DELETE`, DTO bornés, seau dédié, épinglage | `test-frontiere-http.sh` passe à 16 routes ouvertes |
| 3 | Requête de proximité (§6), formule haversine extraite | décompte SQL == décompte API |
| 4 | Cron, marqueur, envoi FCM, purge des morts | `test-notifications-client.sh`, mutation comprise |
| 5 | Mobile Android : packages, permission, réglage, §7.1 et §7.2 | parcours sur appareil qui **revient** sur l'écran |
| 6 | Textes légaux, Data safety, build, tag | `docs/BUILD_ANDROID.md` déroulé |
| 7 | *(plus tard)* iOS : clé APNs, capacité Xcode, course `getToken()` | `docs/RETOURS_APPLE.md` déroulé |

⚠️ Étape 7, deux pièges connus : le fichier `.p8` **ne se télécharge qu'une seule
fois** (perdu = clé à révoquer et recréer, et le portail plafonne à 2 clés par
équipe) ; et sur iOS `getToken()` peut rendre `null` s'il est appelé avant
qu'APNs ait fourni son propre token — le symptôme est un iPhone qui ne reçoit
jamais rien, sans erreur nulle part.

---

## 15. Points laissés ouverts

À trancher avant l'étape 4, pas pendant.

1. **Période du cron** — 2 min ? 5 min ? Arbitrage entre fraîcheur perçue et
   nombre de passages à vide.
2. **Contenu du message** — quelle phrase, quelles données (nom du commerce,
   réduction, distance ?), et dans quelle langue, sachant que le serveur ne sait
   pas la langue de l'appareil (à porter dans l'abonnement, ou à laisser à l'app
   via un message de données plutôt qu'un message de notification).
3. **Comportement au tap** — ouvrir la promo suppose une route profonde ; le
   dépôt a déjà `app-links`, donc probablement réutilisable.
4. **Part d'iOS dans le parc** — chiffre manquant, et c'est lui qui validera ou
   non N8.
