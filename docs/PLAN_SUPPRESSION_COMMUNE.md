# Plan — suppression de `wilaya`/`commune`, agent global, adresse libre

**Ouvert le 2026-08-13. Révisé le 2026-08-13** après deux revues adverses
(métier, technique) qui ont renversé une dizaine de ses affirmations. Ce qu'elles
ont corrigé est consigné au **§11** — non par scrupule, mais parce qu'une
assertion fausse qu'on ne sait pas fausse coûte deux fois.

Fait suite à `PLAN_BASCULE_GEO.md`, dont il consomme les acquis : le point GPS
est déjà l'ancre du produit, le client n'utilise plus aucun toponyme, la position
du commerçant est déjà obligatoire à la publication.

Ce chantier retire ce qui reste : le découpage administratif comme **modèle de
données** et comme **frontière d'autorisation**.

---

## 1. Décisions (arrêtées par le produit)

| # | Décision |
|---|---|
| D1 | **`Commune` et `wilaya` disparaissent entièrement** — table, colonne, relation, référentiel, sélecteurs, filtres |
| D2 | **`Commercant.adresse` devient le seul texte de lieu**, et il est **optionnel** |
| D3 | **Tout repose sur la position sur la carte** — capture GPS ou choix d'un point, par l'agent ou par le commerçant |
| D4 | **L'agent devient global** : plus de territoire, plus de rattachement, plus de cloisonnement |
| D5 | **Recopie `« commune, wilaya » → adresse`** avant le `DROP`, **uniquement si l'adresse est vide**, sur **toutes** les lignes y compris supprimées en douceur, migration **non réversible** |

D4 est un **élargissement de privilèges assumé**, pas un nettoyage.
**D5 est à reconsidérer** — le §9 explique pourquoi les revues l'ont mise en
cause, et ce que ça change si elle tombe.

---

## 2. Ce qui est mesuré, et ce qui ne l'est pas

**Mesuré le 2026-08-13**, sur ce dépôt :

| Fait | Valeur |
|---|---|
| Routes protégées / total / ouvertes épinglées / host-scopées | **51 / 66 / 15 / 3** (banc de frontière, 147 sondes, 0 échec) |
| Écritures perdant leur garde d'appartenance | **14** (+1 refus de création) — §3.1 |
| Clés `.arb` orphelines | **12**, × 3 fichiers = **36 entrées**, **+ 3 blocs `@`** |
| `ErrorCode` retirés | **3**, × 3 mappings = **9 entrées** |
| Fichiers mobile supprimés entièrement | **6** |
| `AuditLogService` importé par `promo/` | **0 occurrence** — §3.2 |
| Bancs déclenchant `PROMO_NOT_OWNED_BY_COMMERCANT` | **0** — §3.3 |
| Bancs lisant `agent.communes` et refusant sans elles | **6** |
| Sites de bancs postant un `communeId` | **11**, sur **7 modules** |
| `communeIds` de `promo_api.dart` : appelants | **0** |
| `communeCible` de `harness.dart` : appelants | **0**, alors que le shell passe `TEST_COMMUNE_ID` à 3 parcours qui ne le lisent pas |
| Parcours pilotant réellement la cascade | **2** |
| Autres fichiers suivis et vides | **0** (hors deux `.gitkeep` voulus) |

⚠️ **Non mesuré, et à ne pas présenter comme acquis** :

- **Le nombre de lignes que D5 touchera.** Les chiffres qui circulent (78 actifs,
  66 avec adresse, 34 avec position) datent du 2026-08-13 ; ceux du 2026-08-12
  (« 44 sans position sur 53 ») viennent d'un autre état. **Deux dates, deux
  bases.** Le compte réel se mesure au moment de la migration.
- **Que `migration:generate` rende vide.** C'est la mesure de la règle 12, et
  elle n'a pas été prise — voir §5, elle doit l'être **avant L1**.
- **Que l'ordre de `DROP` du §6.5 s'exécute**, ni que les noms de contraintes
  relus dans les migrations correspondent à la base. Raisonné, pas éprouvé.
- **Que l'`INSERT` du §3.0 échoue vraiment.** L'inférence est solide et c'est le
  premier point à éprouver, mais aucun `INSERT` n'a été lancé.

---

## 3. Les trous que ce chantier ouvre ou révèle

### 3.0 🔴 De L2 à L7, plus aucun commerçant ne peut être créé

**C'est le défaut qui casse l'ordre des lots, et il n'était pas vu.**

`whitelist` retire un champ du **DTO**. Il ne remplit pas la **colonne**.

- L2 retire `communeId` des deux DTO d'inscription — tous deux **requis**.
- L'entité porte toujours `communeId`, **`NOT NULL`** en base, et la colonne ne
  tombe qu'en **L7**.
- `commercant.service.ts` fait `create({ ...rest })` : plus rien ne la pose.

⇒ Entre L2 et L7, tout `POST /commercant/register` et tout
`POST /agent/commercant` lève `23502 not_null_violation` → **500**. Cela emporte
`provision-decor.sh` et `seed-demo.sh`, donc **le décor lui-même**, donc L5 et L6
ne peuvent plus tourner.

**Résolution retenue : la migration se scinde en deux.**

| | Contenu | Avec |
|---|---|---|
| **M1** | `ALTER TABLE commercant ALTER COLUMN "communeId" DROP NOT NULL` **+ l'entité passe à `@Column({ nullable: true })`** | **L2** |
| **M2** | la recopie + les trois `DROP` | **L7** |

Les deux moitiés sont indispensables : la migration seule ferait diverger entité
et base, et `migration:generate` cesserait de rendre vide entre L2 et L7 — ce que
la règle 12 pose comme « la seule normale ».

⚠️ **Et ça déplace la contrainte mobile.** Dès M1, un commerçant créé n'a plus de
`communeId`, et l'API sert `null` sur un champ que `commercant.dart` et
`admin_commercant_item.dart` lisent en `as String` **non nullable** — plantage à
la désérialisation. **Rien n'est publié** (`DEPLOIEMENT_STORES.md` : *« État
actuel : rien n'est publié »*), donc ce n'est pas un problème de déploiement :
c'est une fenêtre de développement où l'émulateur casse. ⇒ **L2 et L4 se
déploient ensemble**, ou L4 précède.

### 3.1 🔴 Quatorze écritures perdent leur seule garde d'appartenance

**Quatorze, pas dix** — les deux revues l'ont trouvé indépendamment, et le
document se contredisait lui-même (son §7.2 disait déjà 14).

| Garde | Sites |
|---|---|
| `assertCanModerate` | **3** — `masquer`, `verifier-ok`, `avertir` |
| `assertCanManageCommercant` | **7** — `suspend`, `reactivate`, `delete`, `registre/valider`, `registre/rejeter`, `profile/valider`, `reset-pin` |
| `assertCanManage` (branche agent) | **3** — `PATCH /promo/:id`, `publish`, `stop` |
| **`createByAgent` — appel direct** | **1** — `POST /promo/agent/:commercantId` |

🔴 **La 14ᵉ est celle qui compte.** Elle appelle la garde **en propre**, pas via
un wrapper — donc invisible à un grep sur `assertCanManage`, et c'est ainsi
qu'elle a été manquée. C'est **précisément la route que la règle 1 de `CLAUDE.md`
nomme comme l'IDOR fondateur**. La rouvrir sans le dire, c'est rouvrir l'IDOR
d'origine à son endroit d'origine.

🔴 **Et c'est la seule que l'app appelle.** Les trois routes promo mises en avant
n'ont **aucun appelant agent/admin** : `PromoApi.update` a zéro appelant (règle
31), `publish`/`stop` ne partent que de l'écran commerçant. Le seul geste
d'écriture de promo par un agent passe par la route omise.

**+1, d'une autre nature** : `agent.controller.ts` refuse `POST /agent/commercant`
si la commune n'est pas dans celles de l'agent. Son retrait change la sémantique
de la création — « dans mes communes » devient « partout ».

⚠️ **Le cas dégénéré s'inverse, sur huit sites** (pas sept) : un agent **sans
aucune commune** est aujourd'hui arrêté net — il voit **zéro**. Demain il voit
**tout**. Cinq sites rendent `0`, trois rendent une page paginée vide.

⚠️ **L'avertissement sur la perte de vérification d'existence est retiré.** Sa
prémisse est vraie — la garde faisait bien `findByIdOrFail` — mais **sa
conclusion est fausse** : chaque service revérifie seul, sur les quatorze
routes, et l'un des fichiers concernés porte déjà le commentaire qui le dit.
Aucune route ne change de statut. Laissé tel quel, cet avertissement aurait fait
écrire des vérifications inutiles.

### 3.2 🔴 La traçabilité qui justifie les privilèges de l'agent n'existe pas

Le contrôleur de promo exempte agent et admin des limites anti-abus au motif que
*« agent/admin agissent via un canal audité »*.

**Vérifié deux fois, indépendamment : `AuditLogService` n'apparaît nulle part
dans `promo/`**, ni contrôleur, ni module. Le canal n'est pas audité.

⚠️ **Deux limites sont levées, pas une** : le plafond de **5 créations / 24 h**
et le **cooldown de republication**. En revanche le plafond de **5 promos
actives n'est PAS exempté** — le plan l'écrivait à tort.

Aujourd'hui la commune borne le trou. **D4 le rend national.** C'est le cas
fondateur de la règle 11 dans sa forme la plus coûteuse : le module existe, il
est branché ailleurs, et un commentaire affirme qu'il couvre ce qu'il ne couvre
pas.

⇒ **Non négociable** : le lot qui élargit l'agent branche `AuditLogService` sur
les écritures de promo par agent, **ou** retire le commentaire et assume par
écrit une exemption sans trace. Le statu quo n'est pas une décision : c'est une
affirmation fausse dans le code.

⚠️ Et le journal d'audit ne se filtre que par `actorType` et n'affiche que des
UUID — exploitable pour un agent de commune, illisible pour un agent national.

### 3.3 🟠 La garde d'appartenance survivante n'est probée par personne

Après D4, la branche `commercant` de `assertCanManage`
(`PROMO_NOT_OWNED_BY_COMMERCANT`) devient la garde d'appartenance principale de
`PromoController`. **Vérifié : aucun banc ne la déclenche** — le code n'apparaît
qu'une fois dans `scripts/`, comme code *accepté*, jamais provoqué, et **aucun
second commerçant n'existe dans les décors**.

⚠️ **Correction** : elle n'est pas « la seule ». `assertPhotoKeysOwned`
(`STORAGE_KEY_NOT_OWNED`) survit — et son élargissement à un `actorId` existe
**précisément** pour le chemin agent qu'on retire. À relire à cette occasion.

⇒ **Non négociable** : le lot qui touche `assertCanManage` porte un banc
« commerçant B sur la promo de A », trois sondes, **asserté sur le code, pas sur
le statut**.

### 3.4 🟠 La commune n'était pas qu'une frontière : c'était l'allocation du travail

Les trois résolutions de modération sont des `update` **inconditionnels** — pas
de précondition d'état, pas de verrou, dernier écrivain gagne.

Aujourd'hui une promo signalée n'est visible que par l'admin et les agents de sa
commune. Demain **tous les agents du parc voient la même file**. Deux modérateurs
sur la même promo — « masquer » puis « avertir » — et la promo reste visible,
**sans erreur** (règle 13).

Rien dans ce plan ne remplace la partition : ni assignation, ni prise en charge,
ni idempotence. À trancher (§10).

### 3.5 🟠 L'admin perd son seul moyen de restreindre un agent

Créer un agent sans commune produit aujourd'hui un compte inoffensif. Après D4,
il n'existe plus **aucune granularité** entre « agent » et « admin moins deux
écrans » : pas de période d'essai, pas de lecture seule, pas de périmètre réduit.
Combiné au §3.2 (aucune trace) et au §7.3 (la révocation devient le seul frein),
l'outillage de l'admin face à un agent douteux se réduit à **supprimer le
compte**. C'est une perte de capacité produit, pas seulement un élargissement.

⚠️ **Asymétrie inattendue** : les trois routes d'écriture de promo sont ouvertes
à `commercant` et `agent` — **l'admin en est exclu**. Après D4, l'agent a donc
strictement **plus** de pouvoir d'écriture sur les promos que l'admin, ce qui
contredit les specs. À corriger ou à assumer.

### 3.6 🟠 La question haute n'est pas posée

`CLAUDE.md` et les specs disent tous deux que *« le rôle agent est amené à
disparaître à l'extension multi-wilaya »*. **D4 crée exactement l'état visé** —
un agent national sans territoire. La vraie question n'est pas si un écran de
détail a encore une raison d'exister, c'est si le **rôle** en a une. Elle est
ouverte au §10.

---

## 4. Ce que le chantier coûte vraiment côté surface visible

Trois affirmations de la première version étaient fausses et sont corrigées ici.

⚠️ **« Un seul écran affiche un nom de commune » : faux — trois.** La fiche
commerçant admin (qui affiche bien l'adresse juste au-dessus), **le détail
agent** (des chips de communes ; vidé, il ne montre plus qu'un e-mail) et **la
liste des agents** (les noms de communes en sous-titre de chaque ligne). Plus
trois widgets sélecteurs, dont un sur un écran **non-admin** : l'auto-inscription
du commerçant.

⚠️ **« Client : impact nul » : faux dès que D5 s'applique.** La fiche promo
affiche `commercant.adresse` au client. D5 y verse « commune, wilaya » pour les
fiches vides ⇒ **le client verra « Djelfa, Djelfa » comme adresse de commerce**,
une chaîne que le commerçant n'a jamais saisie. C'est le seul impact client du
chantier.

⚠️ **« Zéro impact légal » : faux.** La recherche de mots était juste — aucun
texte légal ne contient « commune » ni « wilaya » — mais deux clauses contredisent
D5 :
- les **CGU** font certifier au commerçant que *« les informations fournies (nom,
  **adresse**, catégorie, numéro de téléphone) sont **exactes** »* ;
- la **politique de confidentialité** déclare l'adresse *« **publique par
  nature** »*.

D5 écrit d'office, dans un champ certifié exact et déclaré public, une valeur que
le commerçant n'a pas fournie.

**Ce qui reste vrai** : le parcours client ne porte plus aucun toponyme depuis le
lot 3 de la bascule, et `PLAN_BASCULE_GEO.md` §4.3 est bien **caduc** — le client
n'utilise plus le sélecteur multiple, seuls deux écrans admin le tiennent.

---

## 5. Ordre des lots

**L0 est fait** (`47b5474`) : le banc de frontière était **vide depuis 24 h** et
rendait 0 sans rien mesurer. Il fallait le restaurer avant tout, L2 devant
dépingler `GET /commune`.

**L−1, préalable, une commande** : `npm run migration:generate` doit rendre
**RIEN** *avant* d'écrire quoi que ce soit. C'est la ligne de base de la règle 12,
et elle ne peut plus être prise après L2 — le §8 en faisait le verdict de L7,
c'était circulaire. ⚠️ **La commande ÉCRIT** : supprimer le fichier produit
avant tout `migration:run`.

| Lot | Contenu | Règles |
|---|---|---|
| **L1** | Gardes backend : les 14 sites du §3.1 + le refus de création, `scopedCommuneIds`, `assertCommuneMatches`. **+ §3.2 (trace d'audit) et §3.3 (banc commerçant B) dans le périmètre.** **+ `pentest_dynamique.py` et `admin_dashboard.py` §4 dans le MÊME commit** | 1, 10, 11, 38 |
| **L2** | Endpoints et DTO : 3 routes, **10 DTO** (dont 3 emportés par L1), filtres wilaya, `apply-wilaya-scope.ts`, `moderation.service.queue`. **+ M1 (§3.0) : colonne nullable + entité.** **+ dépinglage de `GET /commune` + les 3 décomptes** (module → 14, `CLAUDE.md`, journal) **+ `client_fiche.py`** | 12, 15, 33, 38 |
| **L3** | `ErrorCode` (3) **+ les 9 entrées des 3 `error_messages_*.dart`** — non sécable | 26 |
| **L4** | **Mobile, un seul commit** : 6 suppressions, ~20 modifications, **36 entrées `.arb` + 3 blocs `@`**, `gen-l10n` + `analyze` + `check_all.dart`. **Se déploie avec L2** (§3.0) | 21, 27, 31 |
| **L5** | Décor et bancs : `provision-decor.sh`, `seed-demo.sh`, les 11 sites `communeId` sur 7 modules, les **6** bancs lisant `agent.communes`, réécriture d'`appartenance.py` / `agent_creation.py` / `admin_agents.py` / `admin_dashboard.py`, suppression de `client_commune.py`. **+ la sonde « deux agents voient la même chose » (§7)** | 28, 29, 31, 38 |
| **L6** | Parcours : `harness.dart`, les **2** parcours à cascade, `test-parcours-ecran.sh` (`lire_zone`, `TEST_COMMUNE_ID`), **~16** commentaires périmés | 23, 38 |
| **L7** | **M2** : recopie + 3 `DROP`. En dernier, après que plus rien ne lise la colonne | 12 |
| **L8** | Documentation — liste complétée au §5.1 | 23 |

**Ordre rigide** : L−1 en premier · **L2 et L4 ensemble** (§3.0) · **L7 en
dernier**. L1 et L5 sont **imbriqués**, pas séquentiels.

### 5.1 Ce que L8 doit couvrir, et que la première version omettait

- **`docs/DEPLOIEMENT_VPS.md`** — 🔴 **runbook de production** qui ordonne
  `npm run seed:communes:prod` sur un script supprimé ;
- `apps/backend/src/scripts/seed-communes.ts` — **le référentiel lui-même**, que
  D1 supprime et qu'aucun lot ne nommait ;
- `apps/backend/package.json` — `seed:communes`, `seed:communes:prod` ;
- **`CLAUDE.md` bien au-delà des règles 1, 15 et 33** : le paragraphe « un agent
  est rattaché à zéro, une ou plusieurs `Commune` », l'arborescence des modules,
  la commande de seed, et **l'exemple de la règle 28** qui cite un écran disparu ;
- `apps/mobile/README.md`, `.env.production.example`,
  `docs/methode-test/run-all-scenarios.sh`, `pubspec.yaml`,
  `network_security_config.xml` ;
- **tout le module `highlight/`** — 5 commentaires commune **déjà** périmés
  depuis la bascule, plus `audit-log.service.ts` et `pagination-query.dto.ts` ;
- `map_providers.dart` — bloc de documentation **orphelin** décrivant un provider
  supprimé au chantier précédent, que `analyze` ne voit pas ;
- `map_screen.dart` — `_centeredOnCommune`, booléen mal nommé qui ne porte aucune
  commune : **il fera échouer le verdict L4** « plus aucune occurrence de
  `commune` dans `lib/` ».

Les archives datées (`AUDIT_*`, `rapport_pentest_*`, `status_v0.md`) sont
**hors périmètre** : elles décrivent un état à sa date, et les réécrire serait
falsifier un journal.

### 5.2 Ce qui doit partager un commit

| A | ↔ | B | Sinon |
|---|---|---|---|
| retrait de `GET /commune` | ↔ | dépinglage + les 3 décomptes | une entrée épinglée fantôme n'**avertit** que ; rien ne la rattrape |
| M1 | ↔ | l'entité `nullable: true` | `migration:generate` cesse de rendre vide |
| retrait d'un champ de réponse | ↔ | le banc qui l'exige **et** le modèle Dart | plantage à la désérialisation |
| retrait d'une garde | ↔ | les bancs qui prouvaient son refus | ils accusent un produit correct (règle 38) |
| un `ErrorCode` | ↔ | ses 3 mappings | `check_error_codes.dart` refuse — **le seul angle tenu par un outil** |
| une clé `.arb` | ↔ | ses 3 fichiers **et son bloc `@`** | **tenu par rien** — §6.1 |

---

## 6. Pièges

### 6.1 Les `.arb` restent le point le plus probable de défaillance

**36 entrées + 3 blocs `@`**, et **aucun vérificateur ne couvre les `.arb`**. Le
seul filet est `gen-l10n` puis `analyze`, et il ne joue que dans le sens
**code → arb**, jamais **arb → arb**.

Les 12 clés (positions `app_fr.arb`) : `wilayaLabel` 45, `communeLabel` 46,
`filterAllOption` 47, `communeRequired` 48, `assignCommunesLabel` 341,
`assignedCommunesLabel` 342, `noCommunesAssignedLabel` 343,
`transferCommunesLabel` 348, `fromAgentLabel` 349, `toAgentLabel` 350,
`selectAllInWilayaLabel` 351, `communesSelectedCount` 352.

⚠️ **Le bloc `@communesSelectedCount` existe dans les TROIS fichiers**, pas
seulement le template — la première version l'écrivait au singulier. Un `@`
orphelin dans `_en`/`_ar` ne fait échouer ni `gen-l10n` ni `analyze` : c'est
exactement le mode de panne que ce paragraphe annonce.

⚠️ **Correction de mécanisme** : seul `filterAllOption` a ses porteurs dans un
fichier supprimé. Les six autres vivent dans des fichiers **conservés** — un
lecteur qui les cherchera dans les 6 fichiers supprimés ne les trouvera pas.

### 6.2 `whitelist` sans `forbidNonWhitelisted` : ce qu'il fait et ce qu'il ne fait pas

⚠️ **Ce qu'il ne fait pas** : il ne remplit pas la colonne. Voir **§3.0** — c'est
le vrai défaut, et la première version affirmait le contraire (« les créations
passent »).

**Ce qu'il fait** : il retire en silence un `communeIds` envoyé par un client, ce
qui bascule une requête de « toutes les promos de mes communes » à « les promos
dans 5 km du point par défaut », **sans une ligne de journal**.
⚠️ Mais **cette question n'a pas d'objet** : rien n'est publié, il n'existe aucune
app installée. Elle est retirée des questions ouvertes.

⚠️ **La vraie source du problème est la provenance du `communeId`**, pas son
envoi. **Six** bancs (pas cinq) lisent `agent.communes` et refusent sans elles —
dont `client_rayon.py`, écrit la veille pour la bascule, qui porte déjà la
formule « l'agent n'a aucune commune — décor absent ? ». **Six bancs qui
accuseront le décor sur un produit sain.** Règle 38, six fois.

### 6.3 🔴 D5 rebloque les commerçants qu'elle sauve — et ils ne peuvent pas corriger

Tout champ modifié via `PATCH /commercant/me` pose `profilePendingReview = true`,
et la publication appelle `assertProfileValidated`. Un commerçant qui corrige la
localité auto-remplie tombe dans une file d'attente admin et **ne peut plus
publier**.

⚠️ **Et il ne peut pas l'effacer.** L'app n'envoie la clé `adresse` que si elle
est non vide : vider le champ ne transmet **rien**, et le serveur conserve
l'ancienne valeur. **On ne peut que remplacer, jamais retirer.** Aujourd'hui
c'est un champ décoratif ; D2 en fait le seul texte de lieu, et D5 y écrit une
valeur fabriquée — trois décisions qui, ensemble, produisent un cas de support
sans issue dans l'app.

⚠️ **Le texte recopié vient d'un référentiel non fiable** : l'architecture dit 36
communes, le seed et `TEST_PROMO.md` en disent 35, et l'en-tête du seed avertit
lui-même que la liste n'a pas été vérifiée.

Le précédent invoqué existe et est plus étroit que décrit : l'exemption de
`profilePendingReview` sur la position ne vaut que pour la **première** pose.

### 6.4 `adresse` devient le seul texte de lieu, sans borne et sans trim

Les trois DTO portent `@IsOptional() @IsString() @MinLength(2)` — **ni
`@MaxLength`, ni transform de trim** — face à un `varchar` **non borné**. Règle
34 : une borne manquante, pas un choix. Tolérable tant que le champ est
accessoire ; **D2 le rend central**. Le plan doit proposer la borne, pas
seulement la nommer.

### 6.5 M2 n'a qu'une seule fenêtre

```
1. UPDATE commercant SET adresse = commune.nom || ', ' || commune.wilaya
     FROM commune WHERE commercant."communeId" = commune.id
      AND (commercant.adresse IS NULL OR btrim(commercant.adresse) = '');
2. DROP TABLE "agent_communes";          -- emporte ses 2 index et 2 FK
3. ALTER TABLE "commercant" DROP CONSTRAINT "FK_c017a3a877de774baf103f4c0b8";
4. ALTER TABLE "commercant" DROP COLUMN "communeId";   -- emporte son index
5. DROP TABLE "commune";
```

**Noms vérifiés** dans les migrations : la contrainte et l'index de
`commercant.communeId`, et les deux FK pointant sur `commune` — aucune troisième
référence dans tout `src/migrations/`. ⚠️ Relus dans les **migrations**, pas dans
la base ; la règle 12 rappelle qu'entité et base ont déjà divergé ici.

⚠️ **Le `DROP INDEX` explicite est retiré** : Postgres l'emporte avec la colonne.
Placé *après* le `DROP COLUMN` il échouerait, et rien ne le dirait.

- **1 après 5** ⇒ la donnée est détruite définitivement. Seule fenêtre.
- **5 avant 2 ou 3** ⇒ Postgres refuse (deux FK), et TypeORM enveloppant
  **toutes** les migrations en attente dans **une seule transaction**, un lot
  légitime appliqué dans le même `run` serait annulé avec.
- **`btrim`, pas `IS NULL` seul.**
- **`down()` non réversible**, à déclarer **dans l'en-tête**.

🔴 **Une sauvegarde manquait, et elle rend la « seule fenêtre » réparable** :
avant M2, `COPY (SELECT id, "communeId" FROM commercant) TO …` plus un dump de
`commune`. Trente secondes.

### 6.6 Deux bancs deviennent incapables d'échouer, un troisième était déjà faux

- **`admin_dashboard.py` §4** (`verdict_disjonction`) rendra ❌ sur un produit
  correct ⇒ dans le même commit que L1. Son docstring écrit **déjà** que le
  résultat attendu *« est aussi celui qu'on obtient quand le périmètre a purement
  disparu »*. ⚠️ La première version attribuait cette phrase aux §2/§3 : c'est le
  **§4**.
- **§2 et §3** (cloisonnement, projection) perdent leur objet et se retirent.
- ⚠️ **`parcours_espace_pro_test.dart` ne perd pas sa capacité à échouer** — il
  mesure auprès du serveur avec le jeton du rôle, puis exige de retrouver les
  chiffres à l'écran. Il perd son **motif**, pas son pouvoir : règle 23, pas
  règle 28. La première version se trompait de diagnostic.
- ⚠️ **`concurrence_plafond.py` n'a jamais pu refuser sur ce cas** : son verdict
  range tout code inattendu dans « non concluant ». Il **passera encore** après
  L3 — le retrait du code mort ne le répare pas.
- ⚠️ **`admin_dashboard.py` §1 repose déjà sur une prémisse fausse depuis la
  bascule géo** : il compare un compteur **global** à une liste qui reçoit
  désormais le point par défaut + 5 km, et son commentaire affirme encore que
  « les deux appliquent les MÊMES cinq conditions ». Il est vert **parce que la
  base est expirée**. C'est le moment de regarder cette sonde.

### 6.7 Deux contrôles qui ne peuvent pas échouer

- `provision-decor.sh` teste la disponibilité de l'API par un
  `curl -sS -o /dev/null "$API_URL/commune"` **sans `--fail`** : vert sur un 404.
  À rebrancher sur `GET /promo/config` — épinglé, donc stable — **avec `--fail`**.
- La recherche admin ne porte que sur **nom et téléphone** — ni adresse, ni
  commune. Retirer le filtre commune supprime le **seul** moyen de resserrer
  géographiquement les trois écrans admin, et le champ de recherche ne prend pas
  le relais. **Ajouter `adresse` à la recherche fait partie du chantier**, pas
  d'un après.

### 6.8 Réécrire `appartenance.py` le rend destructif

Le fichier dit lui-même pourquoi ses 14 sondes sont aujourd'hui sans effet de
bord : *« garde neutralisé, la sonde `delete` supprimerait réellement le
commerçant du décor, et les sondes suivantes ne prouveraient plus rien »*.

Prouver « accepté, partout » les rend **toutes** destructives — `suspend`,
`delete`, `reset-pin`, `masquer`, `avertir`, `publish` s'exécutent pour de vrai,
en séquence, sur le même commerçant. ⇒ **le décor doit devenir jetable par
sonde**, ou les sondes ordonnées de la moins destructive à la plus. Ce n'est pas
une ligne de travail, c'est la refonte du banc.

---

## 7. Ce qui doit ÉPROUVER l'agent global

1. **La globalité est un fait, pas une absence.** **Deux agents distincts doivent
   voir la MÊME liste**, égale à celle de l'admin. ⇒ **l'agent B du décor est
   conservé et repurposé** : sans un second agent, « l'agent voit tout » est
   indiscernable de « l'agent voit ce qu'il voyait », et la sonde ne peut pas
   refuser (règle 28).
2. **`appartenance.py` se réécrit** — il est le seul à exercer 14 routes avec un
   jeton agent, et devra prouver l'**acceptation**. Voir §6.8 pour le prix.
3. **La révocation devient le seul frein.** Un agent global compromis dispose de
   14 routes d'écriture sur tout le parc. `revocation_jwt.py` passe de « banc de
   conformité » à « banc de dernier recours ». **Ne pas y toucher.**

### Pertes de couverture à assumer

- Le seul contrôle de **projection** disparaît ; la relation « compteur = liste »
  doit survivre **pour l'agent aussi**.
- `client_commune.py` était le seul à éprouver qu'un endpoint de référence n'est
  pas tronqué. **C'est la fin de l'exception nommée de la règle 15** — à retirer
  en même temps, sinon elle protège un fantôme.
- Le **journal d'audit garde des lignes** pointant vers une table supprimée
  (`assign_agent_communes`, `transfer_communes`, avec leurs `metadata.communeIds`).
  Ne rien purger — c'est de la traçabilité historique — mais le dire.

---

## 8. Plan de vérification

| Lot | Verdict |
|---|---|
| **L−1** | `migration:generate` rend **RIEN** — ligne de base, prise avant tout |
| L1 | Le banc « commerçant B » **refuse** sur les 3 routes, asserté sur le code · `pentest_dynamique.py` vert · une écriture de promo par agent **laisse une trace d'audit** (ou l'exemption est écrite) |
| L2 | **Un `POST /commercant/register` aboutit** (§3.0 — le premier point à éprouver) · banc de frontière : **14 ouvertes épinglées**, 0 surprise · `migration:generate` rend **RIEN** après M1 · `client_fiche.py` vert sur `adresse` |
| L3 | `dart run tool/check_all.dart` — bidirectionnel |
| L4 | `analyze` **0** · `flutter test` **14 verts** · `dart format --set-exit-if-changed` **0** · **plus aucune occurrence** de `commune`/`wilaya` dans `lib/` (⚠️ suppose `_centeredOnCommune` renommé, §5.1) |
| L5 | Deux agents distincts rendent la **même** liste, égale à celle de l'admin · `appartenance.py` prouve l'**acceptation** sur 14 routes · auto-tests bloquants à jour |
| L6 | Les 2 parcours à cascade passent sur appareil · plus aucun `TEST_COMMUNE_ID` |
| L7 | **Sauvegarde prise** (§6.5) · `COUNT(*) WHERE adresse` non vide **avant et après**, avec le delta attendu · `migration:generate` rend **RIEN** |
| L8 | — |

⚠️ **Le verdict de L7 ne se rejoue pas.** « Aucune ligne non vide écrasée » n'est
pas mesurable a posteriori : la colonne est détruite et la migration
irréversible. Le seul contrôle possible est le comptage avant/après, et il doit
être **écrit dans le journal** — c'est la seule preuve qui restera.

---

## 9. D5 mérite d'être rediscutée, pas seulement paramétrée

Les deux revues convergent, et le calcul n'avait pas été fait.

**Ce que D5 protège** : ~12 lignes d'une base de **développement**. Le journal la
qualifie lui-même de *« base de développement, pas le terrain »*, elle porte un
commerce de test à 1571 km, et **rien n'est publié**.

**Ce qu'elle coûte** :

| Coût | Où |
|---|---|
| une adresse fabriquée montrée aux clients | §4 |
| une clause CGU contredite (« exactes ») et une politique (« publique ») | §4 |
| un re-blocage de publication à la correction | §6.3 |
| une correction impossible à *effacer* dans l'app | §6.3 |
| une migration irréversible avec une fenêtre unique | §6.5 |
| un texte issu d'un référentiel dont le seed avertit qu'il n'est pas vérifié | §6.3 |

**Trois options**, à trancher :

1. **Maintenir D5** — et alors les corrections de §6.3 (effacement possible,
   exemption de `profilePendingReview`) et de §6.4 (borne) deviennent
   obligatoires, pas optionnelles.
2. **Abandonner D5** — la colonne tombe sans recopie. Douze fiches perdent une
   localité approximative sur une base de dev ; l'adresse reste vide et
   saisissable. **Supprime six coûts sur six.**
3. **Recopier ailleurs** — dans une colonne de travail ou un fichier d'export, pas
   dans un champ certifié et public.

Ce document ne tranche pas. Il note que la première version présentait D5 comme
un acquis en n'ayant chiffré ni son bénéfice ni son prix.

---

## 10. Questions ouvertes

1. **D5 : maintenir, abandonner, ou déplacer ?** (§9) — la seule qui bloque L7.
2. **Brancher l'audit** sur les écritures de promo par agent, ou **assumer par
   écrit** une exemption sans trace ? (§3.2)
3. **Que remplace la partition du travail de modération** — assignation, prise en
   charge, ou simple idempotence des trois résolutions ? (§3.4)
4. **Le rôle agent doit-il survivre à D4 ?** Les specs et `CLAUDE.md` prévoient
   déjà sa disparition, et D4 crée l'état qu'ils décrivent. (§3.6)
5. **L'agent doit-il garder plus de pouvoir d'écriture que l'admin ?** (§3.5)
6. `admin_agent_detail_screen` : son propre docstring dit qu'il existe pour ne pas
   tasser « e-mail et communes » dans un sous-titre. Vidé, il ne reste qu'un
   e-mail — **c'est une suppression que le fichier justifie tout seul**, plus une
   question produit.

Aucune ne bloque L−1 ni L1. La 1 bloque L7, la 2 est dans le périmètre de L1.

---

## 11. Ce que les revues adverses ont renversé

Consigné parce qu'une assertion fausse qu'on ne sait pas fausse coûte deux fois —
et parce que ce plan a été écrit avec la même méthode que celui qu'il remplace.

| Affirmation de la 1ʳᵉ version | Réalité |
|---|---|
| « Les créations passent grâce au `whitelist` » | **🔴 Elles rendent 500** de L2 à L7 : colonne `NOT NULL`. Casse le décor, donc L5 et L6 (§3.0) |
| « Dix écritures perdent leur garde » | **14** — et la 14ᵉ, manquée, est **l'IDOR fondateur de la règle 1**, seule route d'écriture de promo que l'app appelle (§3.1) |
| « On perd la vérification d'existence ⇒ 404 devient 500 » | **Faux** : chaque service revérifie. Aurait fait écrire des gardes inutiles |
| « Un seul écran affiche un nom de commune » | **Trois**, plus trois sélecteurs dont un non-admin (§4) |
| « Client : impact nul » | **Faux** : D5 fait apparaître « Djelfa, Djelfa » comme adresse publique (§4) |
| « Zéro impact légal » | **Faux** : les CGU font certifier l'adresse *exacte*, la politique la déclare *publique* (§4) |
| « Le §6.3 débat de la correction » | Le commerçant ne peut pas **effacer** : l'app n'envoie pas un champ vide (§6.3) |
| « Sans plafond ni trace » | Le plafond de **5 promos actives n'est pas exempté** ; deux autres limites le sont (§3.2) |
| « La seule garde d'appartenance survivante » | `assertPhotoKeysOwned` survit aussi (§3.3) |
| « sept sites » du cas dégénéré | **huit**, dont trois rendent une page vide et non `0` |
| « 12 clés + son bloc `@` » | Le bloc `@` existe dans **les trois** fichiers (§6.1) |
| « cinq bancs accusent le décor » | **six** — dont `client_rayon.py`, écrit la veille (§6.2) |
| « les 3 parcours à cascade » | **deux**. Les trois qui reçoivent `TEST_COMMUNE_ID` ne le lisent pas (§2) |
| « 7 DTO » | **10**, dont 3 emportés par L1 — un lecteur qui grep en trouve 10 |
| « L8 : specs, architecture, TEST_PROMO, CLAUDE (1/15/33), journal » | Omettait le **runbook de production**, le référentiel lui-même, les scripts npm, `highlight/`, et quatre passages de `CLAUDE.md` (§5.1) |
| « `parcours_espace_pro` devient incapable d'échouer » | **Faux** : il perd son motif, pas son pouvoir (§6.6) |
| « `admin_dashboard.py` §2/§3 : le docstring l'écrit déjà » | Ce docstring est celui du **§4** (§6.6) |
| « `concurrence_plafond.py` porte un cas devenu mort » | Il n'a **jamais** pu refuser : tout code inattendu est « non concluant » (§6.6) |
| « une app installée qui envoie encore `communeIds` » | **Aucune app n'est publiée.** Question sans objet, retirée (§6.2) |
| Réécrire `appartenance.py` : une ligne | Rend les 14 sondes **destructives** — refonte du banc (§6.8) |
| D5 présentée comme acquise | Protège **12 lignes d'une base de dev** contre six coûts réels (§9) |

**Non renversé, et vérifié deux fois** : l'absence d'`AuditLogService` dans
`promo/` · `PROMO_NOT_OWNED_BY_COMMERCANT` jamais provoqué et zéro
`COMMERCANT_B` · les 12 clés `.arb` aux positions exactes, sans 13ᵉ oubliée · les
3 `ErrorCode` × 3 mappings · les 6 fichiers mobile · `communeIds`/`communeCible`
sans appelant · `main.ts` sans `forbidNonWhitelisted` · la sonde de décor sans
`--fail` · `profilePendingReview` et l'exception de première pose · les trois
décomptes 36/35/35 et l'avertissement du seed · la prémisse fausse du dashboard ·
les noms de contraintes et l'ordre de `DROP` · la caducité de
`PLAN_BASCULE_GEO.md` §4.3.
