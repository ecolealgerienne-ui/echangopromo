# Synthèse de revue — echango Promo (31 constats confirmés → 27 après fusion)

## Fusions opérées

| Constats fusionnés | Angles réunis |
|---|---|
| `GET /promo/:id` × 2 | **modèle de données** (règle 8 : un seul des deux champs orthogonaux est testé) + **invariant non tenu** (règle 30 : le commentaire déclare partager la règle de `findActiveForClient`, il n'en reprend qu'une condition sur cinq) |
| `countVisible` × 2 | **duplication** (règle 9 : 4ᵉ copie de « promo visible ») + **commentaire qui ne tient rien** (règle 30). *Réserve du sceptique : le titre « son propre commentaire déclare aligner » est surinterprété — le commentaire ne revendique l'alignement que sur `dateFin`.* |
| `photoKeys` promo + `photoKey` profil | même défaut, deux surfaces — traité en une entrée ci-dessous |

---

## 1 — Critique

### 1.1 L'écran `/dev/profiles` embarque les identifiants admin/agent/commerçant en clair dans le binaire release
`apps/mobile/lib/features/dev/screens/dev_profile_switcher_screen.dart:41-47` · `apps/mobile/lib/app/router.dart:99` — **règle 22** (rôle attaché à la route) et **règle 30** (« À SUPPRIMER avant l'ouverture publique » est un commentaire, il ne peut pas échouer).

**Défaillance :** un `strings base.apk | grep echangopromo.com` sur l'APK déjà distribué en test interne Play rend `superadmin@echangopromo.com` / `123456789` — compte admin **unique** de la V0, à droits d'écriture larges — et `env.dart` met `defaultValue: 'https://promo.echango.com'`, donc un release sans `--dart-define` pointe la production.

**Correctif :** vider les six `TextEditingController` (le stockage sécurisé remplit déjà via `_loadSaved`), construire `_appRoutes` avec `...[if (kDebugMode) _AppRoute('/dev/profiles', …)]`, **et faire tourner le mot de passe admin** — la suppression du code ne rappelle pas les APK déjà installés. Nuance du sceptique : l'écran lui-même n'est pas atteignable (l'intent-filter ne route que `/p`) — le vecteur exploitable est l'extraction de chaînes du snapshot AOT, pas la navigation.

### 1.2 Aucune garde d'appartenance sur les clés S3 fournies par le client — suppression croisée d'objets
`apps/backend/src/promo/promo.service.ts:839` + `apps/backend/src/commercant/commercant.service.ts:273` — **règle 1** (le rôle JWT ne suffit jamais) et **règle 10** (la garde existe, elle n'est pas branchée).

**Défaillance :** `GET /promo` et `GET /commercant/:id/public` — deux routes **publiques** — servent l'URL complète, donc la clé S3 littérale, des objets d'un tiers ; un commerçant fait un `PATCH` avec la clé du concurrent (l'IDOR de `assertCanManage` est respecté, la promo lui appartient), puis un second `PATCH` avec ses propres clés : `removedKeys` / `previousPhotoKey` contient la clé du tiers et `deleteObject` la détruit — définitivement, sans erreur, sans audit, sans notification. Entre les deux `PATCH`, la photo du tiers s'affiche sur la fiche de l'attaquant (usurpation d'enseigne).

**Correctif :** un unique `assertKeyOwnedBy(key, folder, ownerId)` levant `ForbiddenAppException` + `ErrorCode` dédié (+ les 3 mappings mobile, règle 26), appelé dans `PromoService.create`/`update` sur **chaque** entrée de `dto.photoKeys` et dans `CommercantService.updateProfile` sur `dto.photoKey` — exactement ce que `requestRegistreVerification:336` fait déjà pour `registre-documents/${commercantId}/`. Attention au cas agent/admin : `StorageController.upload` préfixe avec le `sub` de l'**acteur**, la garde doit accepter ce préfixe-là.

---

## 2 — Majeur

### 2.1 « Avertir » une promo déjà masquée produit une promo republiée et définitivement invisible
`apps/backend/src/promo/promo.service.ts:786` — **règle 8**.

**Défaillance :** `resolveAvertir` ne remet `moderationStatus = NORMALE` que si le statut vaut exactement `SIGNALEE` ; sur une promo `MASQUEE` le masque persiste, la notification dit pourtant « repassée en brouillon, republiez-la », le commerçant republie, consomme un de ses 5 emplacements, obtient 0 vue et n'a aucun indicateur (`moderationStatus` n'est affiché sur **aucun** écran commerçant).

**Correctif :** poser `NORMALE` pour tout statut bloquant (`SIGNALEE` **et** `MASQUEE`), ou refuser l'action sur `MASQUEE` avec un `ErrorCode` dédié — et faire que `PromoModerationTile:106-110` ne propose que les transitions atteignables depuis le statut courant.

### 2.2 `countPendingModeration` compte des signalements, pas des promos
`apps/backend/src/report/report.service.ts:199` — **nouveau** (aucune règle existante ne le couvre).

**Défaillance :** `getCount()` sur une requête `GROUP BY`/`HAVING` — TypeORM 0.3.30 remet les `groupBys` à zéro et **conserve** le `HAVING` (`SelectQueryBuilder.js:1740` + `:466`) : 2 promos × 3 devices affichent `signalementsEnAttente: 6` au dashboard, et `listPendingModeration` rend `total: 6` pour 2 items — le mobile pagine sur des pages fantômes ; cas dégénéré symétrique : le compteur rend **0** sur une file non vide.

**Correctif :** `SELECT COUNT(*) FROM (<requête groupée>) AS q` via un query builder enveloppant, ou `(await qb.getRawMany()).length`. **Plus un test qui exige 2 et non 6** (règle 28 : le contrôle doit savoir refuser).

### 2.3 `GET /promo/:id` n'applique qu'une des cinq conditions de visibilité
`apps/backend/src/promo/promo.controller.ts:166` — **règles 8 + 30**.

**Défaillance :** la route publique de lien partagé `/p/:id` continue de servir intégralement une promo `ARRETEE`, expirée, en brouillon, ou d'un commerçant **suspendu** (dont la cascade a repassé les promos en `BROUILLON`) — et `promo_detail_screen.dart` ne lit jamais `lifecycleStatus`, son `_DeadlineChip` affiche « se termine aujourd'hui » sur une date passée : une offre périmée se présente comme en cours, une suspension ne coupe pas les liens en circulation.

**Correctif :** supprimer le filtre local, appeler `promoService.findVisibleByIds([id])` (`promo.service.ts:636`, qui porte déjà les cinq conditions) et lever `PROMO_NOT_FOUND` si vide.

### 2.4 Le banc d'appartenance passe au vert quand sa requête a échoué
`scripts/lib/appartenance.py:268` — **règle 28**.

**Défaillance :** le statut HTTP est jeté (`_, _, d`) et `d.get("items", [])` rend `[]` sur 429, 401, 500 ou coupure — pour l'agent B (`doit_voir=False`), toute panne imprime « ✅ agent B ne le voit pas » : le contrôle **négatif**, le seul qui prouve la projection par commune, ne sait pas refuser. Atteignable : le banc enchaîne 16 écritures sur un seau de 20/min.

**Correctif :** exiger 200 **et** la présence de la clé `items` ; sinon `non_concluant`, comme `verdict_refus:80` le fait déjà pour les 429. Ajouter au `self_test` deux cas de refus : réponse sans `items`, statut 429.

### 2.5 Le miroir `NotificationType` échappe à `check_enums.dart` et lève au lieu de replier
`apps/mobile/lib/domain/models/notification.dart:13` — **règle 19**.

**Défaillance :** absent des 8 `_paires` et des `_mobileSeuls`, il n'est pas contrôlé — le vérificateur annonce quand même « les 8 couples sont d'accord » ; son `firstWhere` **sans `orElse`** lève, donc une 8ᵉ valeur backend (le précédent est documenté 3 fois dans `src/migrations`) fait basculer `notificationsProvider`, `notificationHistoryProvider` et le dashboard commerçant en `error` — perte de **toutes** les notifications à cause d'une ligne.

**Correctif :** ajouter la paire à `_paires`, et remplacer `firstWhere` par `fromApiValue` (les 5 autres miroirs l'utilisent déjà) — le repli demande une décision explicite ici, `notificationIcon`/`notificationIconColor` faisant deux `switch` exhaustifs.

### 2.6 `PromoService.update` réécrit `moderationStatus`/`lifecycleStatus` depuis un instantané pris avant l'aller-retour S3
`apps/backend/src/promo/promo.service.ts:832` — **règle 13**.

**Défaillance :** `findByIdOrFail` (l.802) → `tryGenerateThumbnail` (plusieurs secondes) → `save(promo)`, sans transaction, sans verrou (`withCommercantLock` existe mais n'est pas utilisé ici) et sans `@VersionColumn` nulle part : un « masquer » ou un « avertir » décidé pendant l'édition est **annulé** par le `save`, et l'admin croit la promo masquée.

**Correctif :** `this.promos.update({id}, {description, prixAvant, prixApres, categorie, photoKeys, thumbnailKey})` ciblé puis relecture pour la réponse — ou transaction + `pg_advisory_xact_lock`, la génération de vignette restant hors section critique.

---

## 3 — Mineur (groupés par famille)

**État de compte & compteurs de dashboard**
- **`create`/`publish` ne vérifient jamais `deletedAt`/`suspendedAt`** — `promo.service.ts:240` · règle 8 · un agent republie pour un commerçant suspendu et défait la cascade (invisible au client grâce aux gardes défensives des 3 lectures, mais l'état en base contredit la modération) · ajouter `assertAccountActive(commercant)` à côté des deux `assert*` existants, dans `create` **et** `publish`.
- **`countVisible` omet les gardes commerçant** — `promo.service.ts:911` · règles 9 + 30 · la promo republiée ci-dessus est comptée `promosPubliees` au dashboard alors qu'aucun client ne la voit · extraire `applyVisibleConditions(qb)` et le faire appeler par les **quatre** méthodes.
- **`countPendingRegistre`/`countPendingProfileReview` comptent supprimés et suspendus** — `commercant.service.ts:443` · règle 9 · `registresEnAttente: 1` reste affiché indéfiniment pour un compte supprimé, et le vider notifie un destinataire mort · ajouter `deletedAt: IsNull()`/`suspendedAt: IsNull()`, ou factoriser `activeAccountWhere(communeIds)` avec `countActive` (déjà corrigé le 2026-07-14).
- **Promo expirée encore `PUBLIEE` jusqu'au cron de 1h** — `promo.service.ts:304` · règle 8 · pendant ≤24h elle occupe un des 5 emplacements et `publish` la refuse en `PROMO_ALREADY_PUBLISHED` (récupérable en deux gestes via « Arrêter ») · une méthode `isEnLigne(promo)` appelée par `publish` **et** `assertUnderCap`.

**Le refus qui n'atteint pas l'utilisateur**
- **`@Param('id')` non-UUID → 500 `INTERNAL_ERROR`** — `promo.controller.ts:164` · règle 25 · un lien `/p/abc123` tronqué par une messagerie affiche « erreur inattendue » au lieu de « Promotion introuvable » et écrit une pile dans les journaux à chaque appel (0 `ParseUUIDPipe` dans tout le backend) · `ParseUUIDPipe` avec `exceptionFactory` rendant un `NotFoundAppException(PROMO_NOT_FOUND)`.
- **Au-delà de 2 Mo, Multer refuse sans `code`** — `storage.controller.ts:45` · règle 25 · `PayloadTooLargeException` (413) tombe dans le `default` de `fallbackCode` → `HTTP_ERROR`, alors que `STORAGE_FILE_TOO_LARGE` existe et est traduit en 3 langues ; atteignable via le filet `return lastAttempt ?? original;` (`storage_api.dart:94`) · `exceptionFactory` sur le `FileInterceptor` + corriger le commentaire « (5 Mo) » périmé (`storage.controller.ts:32`).
- **Course sur `assertPhoneAvailable` → 500** — `commercant.service.ts:100` · règle 13 · deux inscriptions simultanées : la seconde heurte `UQ_commercant_telephone_active`, `QueryFailedError 23505` non rattrapé (0 occurrence dans tout le backend) → l'utilisateur croit qu'un tiers a pris son numéro · transaction + `catch` du `23505` relevé en `ConflictAppException(COMMERCANT_PHONE_TAKEN)`.
- **Dernier `error.toString()` du dépôt** — `commercant_fields_form.dart:105` · règle 26 · sur le tout premier écran de saisie du produit, un `GET /commune` en échec affiche le message **français** au lieu de la langue choisie (`ApiClient` réenveloppe toujours dans un `DioException`) · `error: (error, _) => ApiErrorText(error)` comme les 15 autres sites, puis retirer `communesError` des 3 `.arb`.
- **`fromDioError` confond « rien reçu » et « reçu quelque chose d'illisible »** — `api_exception.dart:24` · règle 29 · un `502 Bad Gateway` en `text/html` de Traefik (en frontal en prod, `main.ts:26`) affiche « Vérifiez votre connexion » : l'utilisateur coupe sa 4G et conclut que l'app est cassée · code `SERVER_UNAVAILABLE` dédié quand `error.response != null`, `NETWORK_ERROR` réservé à `response == null`.
- **Notifications servies en français dans une app fr/en/ar** — `notifications_panel.dart:128` · règle 27 (en amont, pas dans le widget) · les 7 messages sont des littéraux backend sans paramètre de langue ; un commerçant arabophone lit du français en mise en page RTL · `notificationLabel(context, type, {promoDescription})` + 7 clés dans les 3 `.arb`, en levant `@Exclude()` sur `Notification.metadata` ; le `message` serveur ne reste qu'en dernier recours.

**Bornes et invariants recopiés**
- **Bornes de durée 1–7 j recopiées 3 fois** — `promo_form_screen.dart:15`, `agent_promo_form_screen.dart:12`, `promo_form_fields.dart:35` · règle 32 · un changement de `PROMO_MAX_DURATION_DAYS` fait refuser le serveur avec `PROMO_DATE_FIN_EXCEEDS_MAX`, non traduit ; aggravant : la `dateFin` est calculée sur l'horloge du téléphone et comparée sans tolérance (`promo.service.ts:105`) · servir les bornes par l'API et **n'envoyer que `dureeJours`**, pour que la seule horloge qui compte soit celle qui valide.
- **Fenêtre « expire bientôt » de 24 h tenue par un commentaire** — `promo.dart:103` · règle 30 · le commentaire dit « une seule définition dans tout le produit », il y en a deux (`promo.service.ts:731`) ; changer la cadence du cron ferait afficher le badge sans notification correspondante · constante nommée des deux côtés + entrée dans `check_server_rules.dart`.
- **`ModerationItem` ne désérialise pas `dateFin`, `isExpired: false` en dur** — `promo_moderation_tile.dart:50`, `admin_promo_detail_screen.dart:83/85` · règle 31 (champ servi sans lecteur) · affichage faux ≤24h sur l'écran détail admin — le sceptique a réfuté le scénario « file de signalements », le libellé de cycle de vie n'y est rendu que si `activeReportCount == null` · ajouter `dateFin` au modèle et partager le calcul avec `Promo.isExpired`.

**Outils qui ne savent pas refuser**
- **`check_error_codes.dart` ne vérifie jamais les codes client-seuls** — `:272` · règle 28 · supprimer `NETWORK_ERROR` de `error_messages_ar.dart:50` rend « ✅ accord complet » — le code le plus affiché sur un marché à couverture réseau variable est le seul indéfendu · `attendus = serveur.difference(_exclusions).union(_codesClientSeuls.keys.toSet())` + un cas de refus au `--self-test`.
- **`check_server_rules.dart` compare à l'ENSEMBLE des nombres du fichier** — `:322` · règle 28 · deux bornes lisant le même fichier avec le même motif ({60, 100}) ne peuvent pas être distinguées : intervertir titre et sous-titre reste vert · ancrer `motifApp` sur le contexte du champ, + un cas de refus « valeurs interverties ».
- **`provision-decor.sh` avale l'échec de la publication** — `:229` · règle 29 · seul appel écrivant qui ne passe pas par `est_erreur`, 49 lignes après le commentaire qui condamne le geste ; le décor annonce « ✅ Promo » sur une promo restée en `BROUILLON` · capturer la sortie et `est_erreur && fail`.
- **`seed-demo.sh` : `(.items // .) | length`** — `:213` et `:140` · règle 29 · un objet d'erreur `{statusCode, code, message}` compte **3** → « 3 mises en avant déjà présentes — inchangé » et l'étape 5 est sautée · `est_erreur` puis `.items` seul, et supprimer `${DEJA:-0}`.

**Divers**
- **`PATCH /admin/agent/:id/communes` n'injecte même pas `@CurrentUser()`** — `admin.controller.ts:122` · règle 11 · seule route d'écriture d'`AdminController` structurellement incapable de journaliser, alors qu'elle élargit le périmètre IDOR consommé par `assertCommuneMatches` — et que `transfer-communes`, même effet, journalise 50 lignes plus bas · ajouter `@CurrentUser()` + `auditLogService.record({action: 'assign_agent_communes', metadata: {communeIds}})`.
- **`Notification` déclare 2 `@Index()` et des types que la migration n'a jamais créés** — `notification.entity.ts:53` · règle 12 · le prochain `migration:generate` émettra les `CREATE INDEX` **plus** `ALTER COLUMN "createdAt" TYPE TIMESTAMP` — perte de fuseau sur tout l'historique, glissée dans une migration qu'on croira additive · aligner l'entité sur la base (`type: 'uuid'`, `timestamptz`) ; `report.entity.ts:38` est le jumeau déjà corrigé.
- **Brouillon interdit à un commerçant en attente de validation** — `promo.service.ts:240` · règle 25 (décalage geste/message) · les deux `assert*` sont posés avant `if (dto.asDraft)`, donc « Enregistrer comme brouillon » échoue en 403 disant « avant de pouvoir **publier** » — y compris pour un `confirmé_agent` qui corrige son adresse · déplacer les deux `assert*` dans la seule branche de publication immédiate (`publish` les rappelle déjà).
- **Compteur d'emplacements dérivé d'une page de 100 tous statuts** — `promo_api.dart:9` · règle 29 · le commentaire justifie la page unique par le plafond de **5 actives**, que l'endpoint ne renvoie pas ; au-delà de 100 promos cumulées le dashboard affiche « 2 emplacements restants » et le serveur refuse en `PROMO_ACTIVE_CAP_REACHED` · exposer le compte publié dans `GET /commercant/me` et paginer réellement « Mes promos ».
- **`generateThumbnail` republie en `public-read` en dur** — `storage.service.ts:242` · règle 5 · un agent peut faire republier en JPEG 240×240 permanent un objet de `PRIVATE_FOLDERS` dont il connaît la clé (registre d'un tiers) — mais il est déjà autorisé à le lire en entier, aucune frontière de privilège n'est franchie · dériver l'ACL de la même fonction qu'`uploadPhoto` et refuser toute `sourceKey` hors de `promo-photos/`.
- **`AuthSession.userId` écrit par 3 écrans, lu nulle part** — `auth_provider.dart:28` · règle 31 · le `me()` de complaisance qu'il impose peut échouer après un `login()` qui a **déjà persisté** la session : l'utilisateur voit « connexion impossible » et se retrouve authentifié au relancement · supprimer le champ de `AuthSession`, `AuthSessionStore` et `loginThenResolveId`.

---

## 4 — Constats liés (une cause, un geste)

**A. La clé S3 vient du client et n'est jamais rattachée à son propriétaire** → 1.2 + `generateThumbnail`. Un `assertKeyOwnedBy(key, folder, actorId)` + un refus de toute `sourceKey` hors `promo-photos/` ferment les trois surfaces. **La garde existe déjà** dans `requestRegistreVerification:336` — c'est un cas de règle 10, pas de code manquant.

**B. « Promo visible » et « promo en ligne » existent en cinq exemplaires** → 2.3, `countVisible`, `create`/`publish` sans `assertAccountActive`, `assertUnderCap` sans `dateFin`, `ModerationItem.isExpired`. Un `applyVisibleConditions(qb)` privé + `findVisibleByIdOrFail` + `isEnLigne(promo)` côté serveur, un seul calcul d'expiration partagé côté Dart. Quatre constats disparaissent d'un refactor ; le commentaire `promo.service.ts:439` (« la définition vit ici et ne doit pas être réécrite ailleurs ») devient enfin vrai.

**C. Chaque compteur du dashboard porte son propre filtre** → `countPendingModeration`, `countVisible`, `countPendingRegistre`, `countPendingProfileReview`. Le bug de `countActive` a déjà été trouvé et corrigé le 2026-07-14 **sur un seul des quatre**. Un test par compteur, avec un cas qui doit échouer (2 promos ≠ 6 signalements ; un compte supprimé ne compte pas).

**D. Les outils rassurent au lieu de regarder** → `appartenance.py`, `check_error_codes.dart`, `check_server_rules.dart`, `provision-decor.sh`, `seed-demo.sh`. Même geste : **bannir les replis** (`|| true`, `(.items // .)`, `.get("items", [])`, `${X:-0}`), exiger le statut, et ajouter à **chaque** `--self-test`/`self_test` autant de cas qui doivent échouer que de cas qui passent (règle 28). Le dépôt documente déjà le bon remède dans `provision-decor.sh:184-186` — il n'est pas appliqué partout.

**E. Les miroirs mobile↔backend non tenus par un vérificateur** → `NotificationType`, bornes de durée, fenêtre 24 h, messages de notification. `check_enums.dart` ignore un enum et annonce quand même « les 8 couples sont d'accord » ; `check_server_rules.dart` ne sait pas lire une valeur d'environnement ni une durée. Étendre les deux outils **et** faire servir les bornes par l'API plutôt que de les recopier.

**F. Le chemin d'échec sort du contrat `{statusCode, code, message}`** → `@Param` non-UUID, Multer 413, `23505` non rattrapé, `error.toString()`, `fromDioError`. Toutes ces exceptions arrivent au filtre global sans être des `AppException` : le mobile reçoit `INTERNAL_ERROR`/`HTTP_ERROR` et ne peut rien localiser. Un audit ciblé « tout ce qui peut lever hors `AppException` » vaut mieux que cinq correctifs isolés.

---

## 5 — Angles morts

Cette revue est **statique** : rien n'a été exécuté, aucune requête émise, aucun binaire inspecté. Ce qu'elle n'a pas pu voir :

1. **Aucun SQL réellement exécuté.** Le diagnostic `getCount()` sur `GROUP BY` est déduit de la lecture de `node_modules/typeorm`, pas d'un log de requête. **Banc à écrire :** 2 promos signalées × 3 devices distincts, exiger `2` et non `6` — et le cas dégénéré (compte global < 3 → `0` sur file non vide).
2. **Aucune course provoquée.** `update` pendant une modération, `assertPhoneAvailable` en double inscription, `assertUnderCap` sur le plafond de 5 — la fenêtre est raisonnée, jamais mesurée. **Banc :** deux clients concurrents, latence S3 forcée.
3. **Aucun APK inspecté.** Le `strings base.apk | grep echangopromo.com` n'a **pas** été lancé, ni la vérification de la chaîne `API_BASE_URL` dans `kernel_blob.bin` (piège `--dart-define` documenté). Tant que ce n'est pas fait, on ne sait pas quels builds sont dans la nature ni vers quel serveur ils pointent.
4. **Aucun objet S3 touché.** La suppression croisée n'a pas été reproduite contre MinIO, et l'ACL réelle d'une vignette n'a pas été lue en `HEAD` — le comportement d'ACL de MinIO peut différer d'S3.
5. **Aucun appel HTTP.** Les plafonds (429 déguisé en refus métier), le 502 `text/html` de Traefik, le `PayloadTooLarge` de Multer à 2 Mo : tous déduits du code. **Banc :** un jeu de sondes qui déclenche chaque chemin d'erreur et vérifie que le corps porte un `code` connu des 3 tables.
6. **Aucun `migration:generate` lancé.** Le « diff destructeur » sur `Notification` est une prédiction. Le lancer en écriture-sèche sur une base de décor le trancherait en une minute.
7. **Le cron n'a pas tourné.** Expiration à 1h, `notifyExpiringSoon` à 9h : la fenêtre de ≤24h et le badge « expire bientôt » sont raisonnés, pas observés.
8. **Aucun écran rendu.** RTL arabe sur des notifications françaises, thème sombre, badges de statut : la revue lit du code, elle ne regarde pas un écran.
9. **La couverture des routes ouvertes n'a pas été rejouée.** `scripts/lib/frontiere_http.py` épingle 14 routes ouvertes ; la règle 33 dit que **seul le banc** peut affirmer qu'aucun garde ne manque. Une route ajoutée depuis le dernier passage n'est couverte ni par ce banc ni par cette revue.
10. **Rien sur la performance.** N+1 (règle 14), index manquants sur `notification(recipientId)`/`(promoId)`, coût du `GROUP BY` de modération à volume : aucune mesure, aucun `EXPLAIN`.