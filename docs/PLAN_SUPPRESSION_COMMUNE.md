# Plan — suppression de `wilaya`/`commune`, agent global, adresse libre

**Ouvert le 2026-08-13.** Fait suite à `PLAN_BASCULE_GEO.md`, dont il consomme
les acquis : le point GPS est déjà l'ancre du produit, le client n'utilise plus
aucun toponyme, la position du commerçant est déjà obligatoire à la publication.

Ce chantier retire ce qui reste : le découpage administratif comme **modèle de
données** et comme **frontière d'autorisation**.

---

## 1. Décisions (arrêtées par le produit, non rediscutées ici)

| # | Décision |
|---|---|
| D1 | **`Commune` et `wilaya` disparaissent entièrement** — table, colonne, relation, référentiel, sélecteurs, filtres |
| D2 | **`Commercant.adresse` devient le seul texte de lieu**, et il est **optionnel** |
| D3 | **Tout repose sur la position sur la carte** — capture GPS ou choix d'un point, par l'agent ou par le commerçant |
| D4 | **L'agent devient global** : plus de territoire, plus de rattachement, plus de cloisonnement |
| D5 | **Recopie `« commune, wilaya » → adresse`** avant le `DROP`, **uniquement si l'adresse est vide**, sur **toutes** les lignes y compris supprimées en douceur, migration **non réversible** |

D4 est un **élargissement de privilèges assumé**, pas un nettoyage. Le §3 le
traite comme tel.

---

## 2. Ce qui est mesuré, et ce qui ne l'est pas

**Mesuré le 2026-08-13**, sur ce dépôt :

| Fait | Valeur |
|---|---|
| Routes protégées / total / ouvertes épinglées | **51 / 66 / 15** (banc de frontière, 147 sondes, 0 échec) |
| Clés `.arb` devenues orphelines | **12**, × 3 fichiers = **36 entrées** |
| `ErrorCode` retirés | **3**, × 3 mappings mobile = **9 entrées** |
| Fichiers mobile supprimés entièrement | **6** |
| `AuditLogService` importé par `promo/` | **0 occurrence** — voir §3.2 |
| Bancs sondant `PROMO_NOT_OWNED_BY_COMMERCANT` | **0** — voir §3.3 |
| `communeIds` de `promo_api.dart` : appelants | **0** (mort depuis le lot 3 de la bascule) |
| `communeCible` de `harness.dart` : appelants | **0**, alors que le shell passe encore `TEST_COMMUNE_ID` à 3 parcours |
| Autres fichiers suivis et vides dans le dépôt | **0** (hors deux `.gitkeep` voulus) |

⚠️ **Non mesuré, et à ne pas présenter comme acquis** :

- **Le nombre de lignes que la recopie D5 touchera.** Les chiffres qui circulent
  (78 commerçants actifs, 66 avec adresse, 34 avec position) datent du
  2026-08-13 sur la base WSL ; ceux du 2026-08-12 (« 44 sans position sur 53 »)
  viennent d'un autre état. **Deux dates, deux bases — ne pas les mélanger.**
  Le compte réel se mesure au moment de la migration, pas avant.
- **Que `migration:generate` rende actuellement vide.** C'est la mesure de la
  règle 12 et elle n'a pas été prise.
- **Que l'ordre de `DROP` proposé s'exécute.** Il est raisonné, pas éprouvé.

---

## 3. Les trois trous que ce chantier ouvre ou révèle

Ce ne sont pas des tâches parmi d'autres : ils décident de la forme du chantier.

### 3.1 🔴 Dix écritures perdent leur seule garde d'appartenance

`assertCommuneMatches` est aujourd'hui la garde de la **règle 1** sur :

- `admin.controller.ts` → `masquer`, `verifier-ok`, `avertir` (via
  `assertCanModerate`) ;
- `admin.controller.ts` → `suspend`, `reactivate`, `delete`, `registre/valider`,
  `registre/rejeter`, `profile/valider`, `reset-pin` (via
  `assertCanManageCommercant`) ;
- `promo.controller.ts` → `PATCH /promo/:id`, `publish`, `stop` (branche agent
  de `assertCanManage`).

Après D4, il ne reste que `@Roles('admin','agent')`. **C'est l'IDOR critique de
l'audit V0 rouvert par décision produit.** Assumé — mais il doit être **écrit à
chacun des endroits**, avec la date et le motif, sinon la prochaine relecture le
lira comme l'oubli qu'il a été la première fois (règle 10 prise à l'envers :
une garde retirée sans un mot est indiscernable d'une garde jamais branchée).

⚠️ **Effet de bord à ne pas manquer** : `assertCommuneMatches` faisait aussi
`findByIdOrFail(commercantId)`. En la retirant, on retire la **vérification
d'existence** qui précédait chaque action. Vérifier que chaque service appelé
derrière lève `COMMERCANT_NOT_FOUND` de lui-même — sinon un `suspend` sur un
UUID inexistant passe de 404 à 200 ou 500.

⚠️ **Le cas dégénéré s'inverse.** Un agent **sans aucune commune** est
aujourd'hui arrêté net (`if (communeIds && communeIds.length === 0) return 0`,
sept sites). Il voit **zéro**. Demain il voit **tout**. Le retournement le plus
complet possible, sur le compte le plus mal configuré du parc.

### 3.2 🔴 La traçabilité qui justifie les privilèges de l'agent n'existe pas

`promo.controller.ts:284-290` exempte agent et admin du plafond anti-abus avec
ce motif : *« agent/admin agissent via un canal audité »*.

**Vérifié le 2026-08-13 : `AuditLogService` n'apparaît nulle part dans
`promo/`, ni contrôleur, ni module.** Le canal n'est pas audité. Un agent peut
créer et modifier des promos pour n'importe quel commerçant, **sans plafond et
sans trace**.

Aujourd'hui la commune borne le trou. **D4 le rend national.** C'est le cas
fondateur de la règle 11 dans sa forme la plus coûteuse : le module existe, il
est branché ailleurs, et un commentaire affirme qu'il couvre ce qu'il ne couvre
pas.

⇒ **Non négociable** : le lot qui élargit l'agent branche `AuditLogService` sur
les écritures de promo par agent, **ou** retire le commentaire et assume par
écrit une exemption sans trace. Les deux sont des décisions ; le statu quo n'en
est pas une, il est une affirmation fausse dans le code.

⚠️ Et le journal d'audit, là où il existe, ne se filtre que par `actorType` et
n'affiche que des UUID — exploitable pour un agent de commune, illisible pour un
agent national. À regarder si D4 doit être auditable en pratique et pas
seulement en principe.

### 3.3 🔴 La dernière garde d'appartenance survivante n'est probée par personne

Après D4, la branche `commercant` de `assertCanManage`
(`PROMO_NOT_OWNED_BY_COMMERCANT`) devient **la seule garde d'appartenance de
tout `PromoController`**.

**Vérifié : aucun banc ne la déclenche.** Le code n'apparaît qu'une fois dans
`scripts/`, comme code *accepté* dans `CODES_APPARTENANCE`, jamais provoqué —
et **aucun second commerçant n'existe dans les décors** (`COMMERCANT_B` :
0 occurrence).

⇒ **Non négociable** : le lot qui touche `assertCanManage` porte un banc
« commerçant B sur la promo de A », trois sondes (`PATCH`, `publish`, `stop`),
**asserté sur le code, pas sur le statut** — là où plusieurs gardes partagent un
même statut, le statut ne mesure rien.

---

## 4. Ce que le chantier ne coûte presque rien

À l'inverse, trois surfaces sont beaucoup plus légères qu'attendu, et il faut le
dire pour ne pas les sur-traiter :

- **Le client : impact nul.** Plus un seul toponyme dans son parcours depuis le
  lot 3 de la bascule.
- **Un seul écran de tout le produit affiche un nom de commune**
  (`admin_commercant_detail_screen`) — et il affiche déjà l'adresse deux lignes
  plus haut.
- **Zéro impact légal.** CGU et politique de confidentialité ne contiennent ni
  « commune », ni « wilaya », ni découpage administratif, dans les trois
  langues.

⚠️ **`PLAN_BASCULE_GEO.md` §4.3 est caduc.** Il protégeait
`commune_multi_select_field.dart` comme « partagé client ↔ admin » : le client
ne l'utilise plus, seuls deux écrans admin le tiennent, et ils partent.

---

## 5. Ordre des lots

**L0 est fait** (`47b5474`, 2026-08-13) : `scripts/lib/frontiere_http.py` était
**vide depuis 24 h** et le banc rendait 0 sans rien mesurer. Il fallait le
restaurer avant tout, puisque L2 doit dépingler `GET /commune` et qu'il n'y
avait rien à modifier. Détail dans le journal.

| Lot | Contenu | Règles |
|---|---|---|
| **L1** | Gardes backend : `scopedCommuneIds`, `assertCanModerate`, `assertCanManageCommercant`, `assertCommuneMatches`, branche agent de `assertCanManage`, refus de `agent.controller.ts`. **+ §3.2 (trace d'audit) et §3.3 (banc commerçant B) dans le périmètre du lot.** **+ `pentest_dynamique.py` et `admin_dashboard.py` §4 dans le MÊME commit** | 1, 10, 11, 38 |
| **L2** | Endpoints et DTO : 3 routes, 7 DTO, filtres wilaya, `apply-wilaya-scope.ts`, `moderation.service.queue`. **+ dépinglage de `GET /commune` + les 3 décomptes** (module, `CLAUDE.md`, journal) **+ `client_fiche.py`** | 15, 33, 38 |
| **L3** | `ErrorCode` (3) **+ les 9 entrées des 3 `error_messages_*.dart`** — non sécable, `check_error_codes.dart` refuse sinon | 26 |
| **L4** | **Mobile, un seul commit** : 6 suppressions, ~20 modifications, **12 clés × 3 `.arb`**, `gen-l10n` + `analyze` + `check_all.dart` | 21, 27, 31 |
| **L5** | Décor et bancs : `provision-decor.sh`, `seed-demo.sh`, les 11 sites `communeId`, réécriture d'`appartenance.py` / `agent_creation.py` / `admin_agents.py` / `admin_dashboard.py`, suppression de `client_commune.py`. **+ la sonde « deux agents voient la même chose » (§7)** | 28, 29, 31, 38 |
| **L6** | Parcours : `harness.dart`, les 3 parcours à cascade, `test-parcours-ecran.sh` (`lire_zone`, `TEST_COMMUNE_ID`), 6 commentaires périmés | 23, 38 |
| **L7** | **La migration**, en dernier — après que plus rien ne lise la colonne. Recopie + 3 `DROP`, verdict = `migration:generate` **vide** | 12 |
| **L8** | Documentation : specs, architecture, `TEST_PROMO.md`, `CLAUDE.md` (règles 1, 15, 33), `PLAN_BASCULE_GEO.md`, journal | 23 |

**Le seul ordre rigide** : L2 avant L4 — le serveur cesse d'exiger avant que
l'app cesse d'envoyer, et le `whitelist` rend ce sens indolore tandis que
l'inverse ferait rejeter les inscriptions. **L7 en dernier.** L1 et L5 sont
**imbriqués**, pas séquentiels.

### Ce qui doit impérativement partager un commit

| A | ↔ | B | Sinon |
|---|---|---|---|
| retrait de `GET /commune` | ↔ | dépinglage + les 3 décomptes | une entrée épinglée fantôme n'**avertit** que ; rien ne la rattrape (c'est arrivé à `/promo/config` le 2026-08-12) |
| retrait d'un champ de réponse | ↔ | le banc qui l'exige **et** le modèle Dart | `commercant.dart` et `admin_commercant_item.dart` lisent `communeId` en **non nullable** : l'écran plante à la désérialisation |
| retrait d'une garde | ↔ | les bancs qui prouvaient son refus | ils accusent un produit correct (règle 38) |
| un `ErrorCode` | ↔ | ses 3 mappings | `check_error_codes.dart` refuse — **le seul angle tenu par un outil** |
| une clé `.arb` | ↔ | ses 3 fichiers | **tenu par rien** — voir §6.1 |

---

## 6. Pièges

### 6.1 Les `.arb` sont le point le plus probable de défaillance du chantier

**36 entrées à retirer, et aucun vérificateur ne couvre les `.arb`.** Une clé
retirée de `app_fr.arb` mais laissée dans `_en`/`_ar` ne fait échouer rien. Le
seul filet est `gen-l10n` puis `analyze` — et il ne joue que dans le sens
**code → arb**, jamais **arb → arb**.

Les 12 clés (positions `app_fr.arb`) : `wilayaLabel` 45, `communeLabel` 46,
`filterAllOption` 47, `communeRequired` 48, `assignCommunesLabel` 341,
`assignedCommunesLabel` 342, `noCommunesAssignedLabel` 343,
`transferCommunesLabel` 348, `fromAgentLabel` 349, `toAgentLabel` 350,
`selectAllInWilayaLabel` 351, `communesSelectedCount` 352 (+ son bloc `@`).

Les trois dernières du premier groupe (`filterAllOption`, `fromAgentLabel`,
`toAgentLabel`) sont des **dommages collatéraux** : elles ne parlent pas de
commune, mais leurs uniques porteurs disparaissent.

### 6.2 🔴 `whitelist` sans `forbidNonWhitelisted` coupe dans les deux sens

`main.ts` monte `ValidationPipe({whitelist: true, transform: true})` **sans**
`forbidNonWhitelisted`. Conséquences opposées :

- **Il sauve** les 11 sites de bancs qui posteront un `communeId` mort : aucune
  erreur, les créations passent. Ce n'est pas une bonne nouvelle — **ils
  n'auront plus aucun effet et ne le sauront jamais.** Les nettoyer, ne pas se
  contenter de « ça passe ».
- **Il cache** le retrait de `ListPromoQueryDto.communeIds` à une app installée.
  Le paramètre est retiré en silence, `perimetreExplicite` devient faux, et la
  même requête passe de « toutes les promos de mes 4 communes » à « les promos
  dans 5 km du point par défaut » — **sans une ligne de journal**. À décider
  explicitement, pas par omission.

⚠️ **La vraie source du problème n'est pas le `communeId` posté, c'est sa
provenance.** Onze bancs le *lisent* quelque part, et ces lectures échouent
franchement : `GET /commune` disparu ⇒ crash Python dans `cycle_commercant.py` ;
`GET /agent/me` → `d["communes"]` vide ⇒ **cinq bancs qui accusent le décor sur
un produit sain**, et `position_publication.py` qui annonce « référentiel
commune injoignable — décor absent ? ». Règle 38, cinq fois.

### 6.3 🔴 La recopie D5 rebloque les commerçants qu'elle sauve

Tout champ modifié via `PATCH /commercant/me` pose `profilePendingReview = true`,
et la publication appelle `assertProfileValidated`. Un commerçant qui corrige la
localité auto-remplie — « Djelfa, Djelfa » n'est pas une adresse — tombe dans une
file d'attente admin et **ne peut plus publier**.

C'est l'impasse A1 de `PLAN_BASCULE_GEO.md`, **refabriquée par la migration
censée l'éviter**. Deux issues, à trancher : documenter le prix, ou étendre le
précédent de `PATCH /commercant/me/position` à une correction d'adresse.

⚠️ Argument supplémentaire pour la rendre corrigeable : **le référentiel n'était
pas fiable**. `ARCHITECTURE.md` dit 36 communes, le seed et `TEST_PROMO.md` en
disent 35, et l'en-tête du seed avertit lui-même que la liste n'a pas été
vérifiée. C'est de **là** que vient le texte qu'on va recopier.

### 6.4 `adresse` devient le seul texte de lieu — et n'a aucune borne haute

Les trois DTO portent `@IsOptional() @IsString() @MinLength(2)`, **jamais de
`@MaxLength`**, face à un `varchar` non borné. Règle 34 : une borne manquante,
pas un choix. Tolérable tant que le champ est accessoire — **D2 le rend
central**.

### 6.5 L'ordre de la migration n'a qu'une seule fenêtre

```
1. UPDATE commercant SET adresse = commune.nom || ', ' || commune.wilaya
     FROM commune WHERE commercant."communeId" = commune.id
      AND (commercant.adresse IS NULL OR btrim(commercant.adresse) = '');
2. DROP TABLE "agent_communes";          -- emporte ses 2 index et 2 FK
3. ALTER TABLE "commercant" DROP CONSTRAINT "FK_c017a3a877de774baf103f4c0b8";
4. DROP INDEX "public"."IDX_c017a3a877de774baf103f4c0b";
5. ALTER TABLE "commercant" DROP COLUMN "communeId";
6. DROP TABLE "commune";
```

- **1 après 6** ⇒ la donnée est détruite définitivement. C'est la seule fenêtre.
- **6 avant 2 ou 3** ⇒ Postgres refuse (deux FK), et TypeORM enveloppant
  **toutes** les migrations en attente dans **une seule transaction**, un lot
  légitime appliqué dans le même `run` serait annulé avec.
- **`btrim`, pas `IS NULL` seul** : `@MinLength(2)` n'interdit `''` que sur les
  écritures récentes.
- **`down()` non réversible**, à déclarer **dans l'en-tête** : recréer une
  colonne `NOT NULL` exigerait une valeur inventée, et rien ne distinguera plus
  une localité recopiée d'une adresse saisie.

⚠️ **`migration:generate` ÉCRIT.** Une génération exploratoire oubliée
annulerait la migration de recopie **déjà appliquée dans le même `run`** —
c'est-à-dire détruirait la seule fenêtre de récupération.

⚠️ **L7 se lance depuis le clone WSL**, seul porteur du `.env` et de la base
réelle. Vérifier d'abord qu'il est à jour et qu'aucun `git stash` n'attend d'être
repris.

### 6.6 Deux bancs deviennent incapables d'échouer, et un troisième était déjà faux

- `admin_dashboard.py` §2 et §3 (cloisonnement, projection) deviennent des
  assertions qui ne peuvent plus refuser. Le docstring de
  `verdict_somme_disjointe` l'écrit **déjà** : *« c'est aussi le résultat qu'on
  obtient quand le périmètre a purement disparu »*. Les retirer, pas les laisser
  verdir.
- `parcours_espace_pro_test.dart` perd son pouvoir discriminant : agent et admin
  serviront les mêmes chiffres. Il doit le retrouver sur **ce qui reste
  différent** — l'agent n'a ni le journal d'audit ni l'écran agents.
- ⚠️ **`admin_dashboard.py` §1 repose déjà sur une prémisse fausse depuis la
  bascule géo** : il compare un compteur **global** à `GET /promo?limit=1`, qui
  reçoit désormais le point par défaut + 5 km. Les deux ne sont égaux que si tous
  les commerçants publiants sont dans ce cercle — le journal note un commerce de
  test à **1571 km**. Il est vert aujourd'hui **parce que la base est expirée**,
  et une liste vide satisfait n'importe quelle assertion. Ce chantier retire
  `communeIds` : c'est le moment de regarder cette sonde.

### 6.7 Une sonde de disponibilité qui ne peut pas échouer

`provision-decor.sh` teste la disponibilité de l'API par un
`curl -sS -o /dev/null "$API_URL/commune"` — **sans `--fail`**. Elle restera
verte sur un 404. Règle 29 : *un `curl -o /dev/null` dans un banc est un aveu*.
À rebrancher sur `GET /promo/config`, avec `--fail`.

---

## 7. Ce qui doit ÉPROUVER l'agent global

Trois exigences qui ne se déduisent d'aucun banc existant.

1. **La globalité est un fait, pas une absence.** L'inverse exact de
   `verdict_disjonction` : **deux agents distincts doivent voir la MÊME liste**,
   et cette liste doit égaler celle de l'admin.
   ⇒ **L'agent B du décor est conservé, et repurposé.** Sans un second agent,
   « l'agent voit tout » est indiscernable de « l'agent voit ce qu'il voyait » :
   la sonde ne pourrait pas refuser (règle 28). Un filtre résiduel oublié quelque
   part ferait diverger les deux listes — c'est le seul contrôle qui le verrait.

2. **`appartenance.py` se réécrit, il ne se supprime pas.** Il est le seul à
   exercer **14 routes** avec un jeton agent. Aujourd'hui il prouve « refusé » ;
   demain il doit prouver « accepté, partout ». Supprimé, plus rien ne dirait
   qu'un `@Roles('admin')` posé par erreur ferme une route à l'agent.

3. **La révocation devient le seul frein.** Un agent global compromis dispose de
   14 routes d'écriture sur tout le parc. `revocation_jwt.py` passe de « banc de
   conformité » à « banc de dernier recours ». **Ne pas y toucher**, et le dire
   dans la décision.

### Trois pertes de couverture à assumer explicitement

- `admin_dashboard.py` §3 était le seul contrôle de projection. Il n'a plus
  d'objet — mais la relation « compteur = liste » du §1 doit survivre **pour
  l'agent aussi**, pas seulement pour l'admin.
- `client_commune.py` était le seul à éprouver qu'un endpoint de référence n'est
  pas tronqué par la pagination. **C'est aussi la fin de l'exception nommée de la
  règle 15** : plus aucun endpoint n'est consommé comme liste complète.
  L'exception doit être retirée en même temps, sinon elle protège un fantôme.
- `concurrence_plafond.py` porte un cas d'auto-test devenu mort (il accepte un
  code supprimé).

---

## 8. Plan de vérification

Ce que chaque lot doit **mesurer**, pas cocher.

| Lot | Verdict |
|---|---|
| L1 | Le banc « commerçant B » **refuse** sur les 3 routes, asserté sur le code · `pentest_dynamique.py` vert · une écriture de promo par agent **laisse une trace d'audit** (ou l'exemption est écrite) |
| L2 | Banc de frontière : **14 ouvertes épinglées** (15 − `/commune`), 0 surprise · `client_fiche.py` vert sur `adresse` |
| L3 | `dart run tool/check_all.dart` — bidirectionnel, il refuse une clé orpheline dans les deux sens |
| L4 | `flutter analyze` **0 problème** · `flutter test` **14 verts** · `dart format --set-exit-if-changed` **0** · **plus aucune occurrence** de `commune`/`wilaya` dans `lib/` |
| L5 | Deux agents distincts rendent la **même** liste, égale à celle de l'admin · `appartenance.py` réécrit prouve l'**acceptation** sur 14 routes · auto-tests bloquants à jour |
| L6 | Les 3 parcours à cascade passent sur appareil · plus aucun `TEST_COMMUNE_ID` |
| L7 | `migration:generate` rend **RIEN** · la recopie est **comptée** (lignes touchées) et relue sur un échantillon · aucune ligne `adresse` non vide écrasée |
| L8 | — |

⚠️ **Le verdict de L7 est le seul qui ne se rejoue pas.** Compter les lignes
avant et après, et garder le compte dans le journal : c'est la seule preuve
qu'il restera que la recopie a eu lieu, la migration étant non réversible.

---

## 9. Risques

| Risque | Portée | Atténuation |
|---|---|---|
| **L'élargissement de l'agent est national et silencieux** | quatre écrans passent de « mes N » à « tous », sans erreur ni journal | §3.2 (trace) + §7.1 (sonde deux agents) |
| **Une clé `.arb` oubliée dans une seule langue** | le plus probable du chantier, **tenu par rien** | 36 entrées listées nommément au §6.1 |
| **La recopie détruit ou rebloque** | irréversible | §6.3 et §6.5, verdict compté |
| **Un banc accuse un produit sain** | crédible, donc coûteux (règle 38) | co-commits du §5 |
| **Les deux clones divergent** | L7 tourne sur la base réelle | vérifier le clone WSL avant L7 |

---

## 10. Ce que ce document n'a pas tranché

- **§6.2** : que fait-on d'une app installée qui envoie encore `communeIds` ?
  Silence ou refus explicite — c'est une décision produit.
- **§6.3** : documenter le prix de la correction d'adresse, ou l'exempter de
  `profilePendingReview` ?
- **§3.2** : brancher l'audit sur les écritures de promo par agent, ou assumer
  par écrit une exemption sans trace ?
- **`admin_agent_detail_screen`** garde-t-il une raison d'exister une fois les
  communes retirées ? Question produit, pas lecture de code.

Trois questions ouvertes, une quatrième cosmétique. Aucune ne bloque L1.
