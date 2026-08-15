# Spécification — alimentation d'EchangoCrm par echango Promo

**Statut** : spécification d'échange, **v2 du 2026-08-15**, après deux
relectures adverses (code backend Promo, dépôt Odoo `echangoCrm` + sources
Odoo 19.0). Aucune ligne de code écrite à ce jour.
**Périmètre** : le suivi commercial des commerçants d'echango Promo depuis
l'instance Odoo 19 Community `EchangoCrm` (`https://echangocrm.echango.com`).
**Documents liés** : `SPECS_ECHANGO_PROMO_V0.md` (produit — ⚠️ voir §0),
`CLAUDE.md` (règles), et côté CRM `docs/REPORTING_KPI.md` /
`docs/CONFORMITE_DONNEES_APPELS.md`.

> ⚠️ **Ce document est le contrat entre deux dépôts.** Il n'existe qu'en un
> seul exemplaire, ici. `echangoCrm` doit y pointer, jamais en recopier un
> extrait — deux copies d'un contrat divergent au premier changement (règle 30).

---

## 0. Ce que la v1 disait de faux

Consigné parce qu'une correction non datée se relit comme un choix d'origine.

| v1 | Réalité mesurée |
|---|---|
| « 6 catégories (specs §5.6) » | **7** — `RESTAURATION` ajoutée le 2026-07-30 (`1783830000000`). **`SPECS_ECHANGO_PROMO_V0.md:295-302` est périmé** et doit être corrigé |
| « 04:00 pour passer après l'expiration de 01:00 » | Infondé : `promos_en_ligne` porte déjà `dateFin > now()`. 04:00 tient pour la charge, pas pour l'ordre |
| « la règle vit en quatre endroits » | **Cinq**, et le premier manquait (`assertAccountActive`) |
| « six motifs de blocage » | Il en manquait deux (§5) |
| « une fonction unique appelée par les gardes et par l'export » | **Irréalisable** : les gardes lèvent par ligne, le plafond dépend d'un agrégat (§5) |
| « une requête agrégée unique avec `GROUP BY` » | Produit cartésien garanti (§3) |
| « on stocke le numéro national tel que le commerçant le connaît » | Rien ne le garantit : les deux formes coexistent en base (§6) |
| « `plafond_promos` rend visible une dérogation » | Le `??` détruisait précisément cette information (§4) |
| « la vue carte est Enterprise (`REPORTING_KPI.md`) » | Vrai, mais **ce document ne le dit pas**. Source corrigée en §8.3 |
| « le géocodeur reste à arbitrer » | Odoo Community le fournit déjà (§8.4) |
| « la branche d'`echangoCrm` est inconnue » | `main`, seule branche. **La règle « jamais `main` » ne s'y applique pas** (décision du 2026-08-15) |

---

## 1. Objet

L'équipe commerciale suit les commerçants inscrits sur echango Promo : combien
de promos ils ont publiées, depuis quand ils n'ont rien publié, ce que la
plateforme leur rapporte, et ce qui les empêche éventuellement de publier.

Ce n'est pas du reporting produit — celui-là est servi par les écrans admin de
Promo. C'est un besoin de **relance** : savoir qui appeler demain matin, et
pourquoi.

**Hors périmètre, définitivement** : les clients finaux, anonymes par
conception (specs §3.1). Aucune donnée les concernant ne franchit cette
frontière, pas même un identifiant d'appareil — seuls des agrégats.

---

## 2. Cinq principes

1. **Le CRM ne réplique pas la base Promo.** Un objet par commerçant, aucune
   promo transférée. Critère d'admission d'un champ : *si cette valeur change,
   est-ce que quelqu'un décroche son téléphone ?*
2. **Promo envoie des faits, Odoo dérive les états.** Les seuils et la
   segmentation sont commerciaux ; les faits (dates, compteurs, blocages) sont
   métier, calculés une seule fois côté Promo.
3. **Ce que Promo envoie vit dans un modèle à part.** Pas sur `res.partner`,
   sauf à la création — voir §8.1, le verrou par `write()` ne peut pas tenir
   cette frontière et il ne faut pas prétendre le contraire.
4. **Un instantané complet, pas un flux d'événements.** Une nuit ratée n'a
   aucune conséquence : la nuit suivante rétablit l'état exact.
5. **`0` et « inconnu » ne sont pas la même chose.** Un lot non reçu ne doit
   jamais se lire comme un commerçant inactif — c'est l'appel absurde qui
   détruit la confiance dans l'outil. Ce principe exige un organe (§7.4), pas
   une intention.

---

## 3. Architecture de l'échange

```
echango Promo (NestJS)                     EchangoCrm (Odoo 19 Community)
@Cron 04:00                                POST /echango_promo/merchants/sync
  4 agrégations + LEFT JOIN     ─────────► contrôleur dédié, jeton dédié
  pages de 200, en-tête de lot              readonly=False, savepoint/fiche
  jeton en en-tête                          upsert par promo_uuid
                                            → echango.promo.account (+ res.partner)
```

**Promo pousse ; Odoo ne tire pas.** `call_tracker/__manifest__.py` porte une
doctrine explicite : pas d'API générique Odoo (une clé API hérite de **tous**
les droits de son utilisateur), mais un contrôleur maison avec son propre
jeton, révocable, sans aucun droit Odoo. On reprend ce patron.

**04:00 pour la charge, pas pour l'ordre.** Les quatre tâches existantes
occupent 01:00 (expiration), 02:00 (purge des photos), 03:00 (purge des
notifications), 09:00 (relance avant expiration). ⚠️ **Aucun `@Cron` du dépôt
ne porte de fuseau** et `ScheduleModule.forRoot()` n'en configure aucun :
« 04:00 » est l'heure du processus — 05:00 à Alger sur un serveur en UTC. À
poser explicitement plutôt qu'à subir.

**Instantané complet, et non incrémental.** Un curseur `updatedSince` sur
`Commercant.updatedAt` ne peut pas fonctionner : cette colonne ne bouge ni à la
publication d'une promo, ni à l'enregistrement d'une vue, ni à l'arrivée d'un
signalement — **vérifié sur les trois chemins**. Le curseur raterait exactement
les fiches dont les indicateurs ont changé.

### 3.1 La requête : quatre agrégations, pas une jointure

⚠️ **Une seule requête plate joignant `promo`, `promo_view`, `report` et
`commercant_view` multiplie les lignes.** Pour un commerçant à 20 promos ×
400 vues × 3 signalements × 150 vues de fiche : 3,6 millions de lignes avant
agrégation, et **tous** les compteurs gonflés du produit des autres branches.

Ce qui rend le défaut vicieux : `MAX(publishedAt)` **survit** au fan-out.
`date_derniere_publication` — le champ le plus important du contrat — serait le
**seul juste** d'un lot entièrement faux.

**À écrire** : quatre CTE, chacune groupée sur `commercantId` (promos, vues de
promo, vues de fiche, signalements), puis `LEFT JOIN` sur `commercant`. C'est
toujours un aller-retour, ce n'est pas un `GROUP BY` unique.

⚠️ **Aucun index ne sert les fenêtres 30 j / 90 j** : rien sur
`promo.publishedAt`, `promo_view."createdAt"`, `commercant_view."createdAt"`,
`report."createdAt"`. Indolore au pilote ; à poser **avec leur migration**
avant toute montée en volume (règle 12 — un `@Index()` sans migration est un
commentaire).

### 3.2 Le lot est une unité, pas une suite de pages

Chaque envoi porte un **en-tête de lot** : identifiant de passage, horodatage
de génération, **nombre total de fiches attendues**, numéro de page. Le dernier
envoi est suivi d'un **acquittement de fin de lot**.

Sans ça, §8.5 (archiver ce qui n'est plus envoyé) devient un piège : si
l'export casse à la page 3 pendant trois nuits, **tous les commerçants des
pages suivantes sont archivés** — le principe 5 retourné contre lui-même.
Odoo n'archive que sur un lot **acquitté complet**.

### 3.3 Les comptes supprimés

Un commerçant supprimé (`deletedAt`) continue d'être envoyé **pendant 30 jours
après sa suppression**, avec sa date. Pas « une dernière fois » : une requête
sans état ne sait pas ce qu'elle a déjà envoyé, et faire dépendre la
propagation d'une suppression de la réussite d'**une** nuit précise, c'est
perdre en silence le seul chemin par lequel un effacement (loi 18-07) atteint
le CRM.

### 3.4 Le coût pour le module voisin

⚠️ **C'est le seul endroit où cette intégration dégrade l'existant.** Le Call
Tracker rapproche un appel entrant par
`regexp_replace(coalesce(col,''),'\D','','g') LIKE '%clé'` sur **trois
colonnes** de `res_partner` — **sans index possible**, le dépôt le documente
deux fois comme « le premier endroit à revoir si le rapprochement ralentit ».

Déverser un parc illimité de commerçants dans `res_partner` fait payer ce
balayage séquentiel **à la sonnerie du téléphone d'un commercial**. À mesurer
dès le premier millier de fiches — pas au-delà de 100 000.

---

## 4. Le contrat de données

Un objet JSON par commerçant.

### 4.1 Champs

| Champ | Type | Source | Sémantique exacte |
|---|---|---|---|
| `promo_uuid` | uuid | `Commercant.id` | **Clé de rapprochement. Immuable.** |
| `nom` | string ≤120 | `nom` | |
| `adresse` | string ≤200 \| null | `adresse` | Texte libre **indicatif**, jamais un critère géographique |
| `categorie` | enum | `categorie` | **7 valeurs** : alimentation, restauration, vêtements/textile, électroménager, beauté/hygiène, maison/ameublement, autre |
| `telephone_e164` | string | `telephone` | **La colonne elle-même depuis le 2026-08-15** : la base stocke l'E.164, il n'y a plus rien à dériver |
| `pays` | ISO-2 | `pays` | ⚠️ **Colonne inexistante à ce jour** — livrée par le lot 1 |
| `latitude`, `longitude` | float \| null | `latitude`/`longitude` | `null` fréquent (obligatoire seulement à la publication) |
| `origine` | enum | `originVerification` | `auto_inscrit` \| `confirme_agent` |
| `agent_createur_id` | uuid \| null | `createdByAgentId` | `null` si auto-inscription |
| `date_creation` | datetime | `createdAt` | |
| `suspendu_le` | datetime \| null | `suspendedAt` | **Deux colonnes, pas un enum** : elles sont orthogonales et un compte suspendu **puis** supprimé les porte toutes les deux (règle 8) |
| `supprime_le` | datetime \| null | `deletedAt` | |
| `consentement_le` | datetime \| null | `consentedAt` | **`null` pour tous les comptes créés par un agent** — voir §10 |
| `est_active` | bool | `EXISTS(promo WHERE publishedAt IS NOT NULL)` | A publié au moins une fois |
| `date_derniere_publication` | datetime \| null | `MAX(promo.publishedAt)` | **Le champ le plus important du contrat** |
| `promos_sans_publication` | int | `COUNT(publishedAt IS NULL)` | ⚠️ **Ce n'est pas « les brouillons » de l'écran commerçant** : `suspend` et `resolveAvertir` renvoient des promos en `BROUILLON` **en gardant `publishedAt`**. Le commerçant verra 3 brouillons, le commercial 0 |
| `promos_deja_publiees` | int | `COUNT(publishedAt IS NOT NULL)` | Promos **ayant été publiées au moins une fois** — pas un nombre de publications |
| `promos_en_ligne` | int | `PUBLIEE AND dateFin > now()` | Ce qui compte dans le plafond |
| `promos_visibles` | int | `applyVisibleConditions` | ⚠️ **Réutiliser la fonction existante, ne pas réécrire ses conditions** : elle en porte **cinq**, dont `commercant.deletedAt IS NULL` et `suspendedAt IS NULL`. Le dépôt a déjà produit trois copies partielles de cette règle |
| `promos_publiees_30j` | int | `publishedAt > now() - 30j` | Promos dont la **dernière** publication tombe dans la fenêtre |
| `promos_masquees` | int | `moderationStatus = masquee` | |
| `signalements_90j` | int | `Report` joint aux promos | |
| `nouveaux_visiteurs_fiche_30j` | int | `CommercantView` | **Portée, pas trafic** (§4.2) |
| `nouveaux_visiteurs_promos_30j` | int | `PromoView` | idem |
| `plafond_effectif` | int | `promoActiveCap ?? PROMO_ACTIVE_CAP` | Ce que le serveur applique |
| `plafond_propre` | int \| null | `promoActiveCap` | **`null` = suit le défaut.** Deux champs, parce qu'un `??` détruit la distinction entre une dérogation à 5 et le défaut à 5 (règle 29, principe 5) |
| `registre_statut` | enum \| null | `registreStatus` | `null` \| `en_attente` \| `valide` \| `rejete` — **trois responsables différents**, voir §5 |
| `peut_publier` | bool | §5 | |
| `motif_blocage` | enum \| null | §5 | |
| `genere_le` | datetime | en-tête de lot | |

**`promos_en_ligne` et `promos_visibles` sont deux nombres différents, et
l'écart est un signal.** Un commerçant à `5 / 5` avec `promos_visibles = 0` est
au plafond, croit publier, et personne ne le voit.

**Chaque champ est borné côté récepteur** (longueur des chaînes, plage des
entiers, horodatages bornés des deux côtés). `call_tracker` borne jusqu'aux
valeurs unitaires ; une route publique sans bornes est une route ouverte.

### 4.2 Ce que ces champs ne disent pas

- **Les compteurs de vues mesurent la portée, pas le trafic.** `PromoView` et
  `CommercantView` portent un index unique `(objet, deviceId)` et
  l'enregistrement passe par `.orIgnore()` : une ligne naît à la **première**
  consultation d'un appareil, jamais ensuite. Une fenêtre de 30 jours compte
  des **appareils nouveaux**. Un commerce très connu paraîtra en déclin.
- ⚠️ **Et ces compteurs sont manipulables.** `X-Device-Id` est un en-tête
  client jamais vérifié (règle 7), et `GET /promo/:id` est public. Le chiffre
  est **gonflable** par rotation de l'en-tête et **dégonflable** par un
  effacement des données de l'app. Il n'a aucune valeur probante.
- **`promos_publiees_30j` compte des promos, pas des publications.**

### 4.3 Ce qui n'est pas calculable, et pourquoi

| Indicateur | Obstacle |
|---|---|
| **Délai d'activation** (création → 1ʳᵉ publication) | `Promo.publishedAt` est une colonne unique, **réécrite** : `promo.service.ts:737` (1ʳᵉ publication) et `:804` (republication) posent tous deux `publishedAt: new Date()`. Aucune autre écriture, aucune colonne compagnon, aucun compteur |
| **Taux de republication** | Même cause. `AuditLog` ne trace **que** les gestes agent/admin : `auditStaffWrite` sort immédiatement pour un `commercant` |
| **Dernière connexion** | `Commercant` n'a pas de `lastLoginAt`. « Ne publie plus » et « n'ouvre plus l'app » appellent deux gestes opposés, et rien ne les distingue |
| **Ancienneté d'un blocage** | `profilePendingReview` est un booléen **sans date**, et rien n'enregistre la **soumission** d'un registre (`registreValidatedAt` ne couvre que l'issue positive). « Bloqué par notre propre validation depuis 12 jours » — le seul tri utile de l'écran « À débloquer » — est hors d'atteinte |

**Aucune requête ne récupère une valeur qui n'a jamais été écrite.** Ce n'est
pas une difficulté de calcul, c'est une absence de donnée.

Ce qu'on perd est secondaire : `est_active` répond à « s'est-il activé ? »,
`date_derniere_publication` à « publie-t-il encore ? ». Les quatre remèdes sont
petits (`firstPublishedAt`, `publicationCount`, `lastLoginAt`,
`blockedSince`) mais **aucun n'est rétroactif** : le compteur démarrera le jour
où on le posera. Rien ne justifie de les poser avant que le besoin soit réel.

---

## 5. La règle « peut publier »

C'est le champ qui distingue **« ne veut plus »** de **« ne peut pas »**. Un
commerçant bloqué ressemble trait pour trait à un commerçant qui se désengage ;
l'appeler pour le motiver alors que c'est une validation interne qui le bloque,
c'est le perdre.

`motif_blocage` prend la première valeur applicable, dans l'ordre d'exécution
réel du serveur :

| Motif | Condition | Garde | Qui débloque |
|---|---|---|---|
| `compte_supprime` | `deletedAt` | `assertAccountActive` | personne — état terminal |
| `compte_suspendu` | `suspendedAt` | `assertAccountActive` | admin/agent Promo |
| `registre_absent` | `auto_inscrit` **et** `registreStatus IS NULL` | `assertRegistreValidated` | **le commerçant** — il n'a rien envoyé |
| `registre_en_attente` | `auto_inscrit` **et** `en_attente` | idem | **nous** — c'est notre file |
| `registre_rejete` | `auto_inscrit` **et** `rejete` | idem | le commerçant — renvoyer |
| `profil_en_revue` | `profilePendingReview` | `assertProfileValidated` | admin/agent Promo |
| `position_absente` | `latitude` ou `longitude` `null` | `assertPositionSet` | le commerçant |
| `plafond_atteint` | `promos_en_ligne ≥ plafond_effectif` | `assertUnderCap` | le commerçant (arrêter une promo) |
| `quota_creation_24h` | 5 créations sur 24 h | `assertUnderDailyCreationCap` | personne — attendre |

⚠️ **`assertAccountActive` rend un seul code** (`COMMERCANT_ACCOUNT_INACTIVE`)
pour supprimé et suspendu : la distinction vient des colonnes, pas de la garde.

⚠️ **Le cooldown de republication (24 h) n'est PAS un motif de blocage.** Il
porte sur **une promo**, pas sur le commerçant, qui peut en publier une autre.
Il est envoyé comme information (`republication_possible_le`), jamais comme un
refus global — sans quoi le CRM déclarerait bloqué quelqu'un qui ne l'est pas.

⚠️ **`registreStatus = null` et `en_attente` ne sont pas le même appel.** Dans
un cas le commerçant doit agir, dans l'autre c'est notre file qui traîne. Les
fondre en un `registre_non_valide` rendrait l'écran « À débloquer » inutilisable
— et c'est exactement la question laissée ouverte au §11.1.

### 5.1 Comment tenir l'invariant, puisqu'une fonction unique est impossible

Les gardes prennent une entité chargée et **lèvent** ; `plafond_atteint` dépend
d'un **agrégat** que seule la requête produit. Aucune fonction n'est à la fois
un `throw` par ligne et un `CASE WHEN` dans une agrégation. **Le lot 0 de la v1
était irréalisable.**

Ce qui est unique, c'est **la table ordonnée des motifs** — une donnée, pas du
code — dont on tire deux rendus minces : les gardes d'un côté, l'expression SQL
de l'autre. Et puisqu'un commentaire ne peut pas échouer (règle 30),
l'équivalence est tenue par **un contrôle exécuté** : pour un échantillon de
commerçants, ce que l'export annonce et ce que `publish()` refuse doivent
coïncider — motif par motif, y compris dans l'ordre.

---

## 6. Le téléphone

⚠️ **Le défaut n'est pas l'absence de colonne `pays`. C'est l'absence de
normalisation, et il existe aujourd'hui.**

Les trois DTO portent `@IsPhoneNumber('DZ')`, qui accepte **aussi bien**
`0555000101` que `+213555000101`. Rien ne normalise avant stockage
(`selfRegister` stocke `dto.telephone` brut). Et l'app **demande** la forme
internationale : `telephoneHint` vaut `"+213..."` dans les trois `.arb`.

**Conséquence, déjà vraie sans le CRM** : les deux formes du même numéro sont
deux chaînes différentes. `UQ_commercant_telephone_active` ne les rapproche pas,
`findVivantByTelephone` ne trouve que la forme exacte saisie — **le même
commerçant peut avoir deux comptes actifs**. Et la dérivation E.164 appliquée à
une valeur déjà en E.164 produirait `+213+213555000101`.

**Ordre des travaux** (lot 1) — ✅ **backend fait le 2026-08-15**, mobile à
faire (voir §11.4) :

1. **Migration de normalisation** — préalable à tout le reste. Toutes les
   lignes existantes en une forme unique, avec relevé des collisions
   éventuelles (deux comptes actifs qui deviennent un doublon).
2. **Colonne `pays`** (ISO-2, défaut `DZ`) et stockage en **E.164**
   (`1783900000000`, décision produit du 2026-08-15 — la première migration
   avait posé la forme nationale). La **saisie** reste nationale : le zéro de
   tête est retiré à la conversion, `0555000101` devient `+213555000101`.
3. **Unicité composite `(pays, telephone)`** — l'index partiel actuel porte sur
   le seul numéro (`WHERE "deletedAt" IS NULL`).
4. **Validateur personnalisé** : `@IsPhoneNumber('DZ')` est **codé en dur dans
   les trois DTO, dont `login-commercant.dto.ts`**, et ne sait pas prendre sa
   région d'un autre champ du même DTO. Sans ce travail, la colonne `pays`
   existe et **aucun numéro non algérien ne peut ni s'inscrire ni se
   connecter**.
5. **La connexion porte le pays** (défaut `DZ`, mémorisé).

**Ce que le plan de la v1 oubliait** : les fichiers mobile portant `telephone`,
les 3 `.arb` où `telephoneHint` code `"+213..."` (règle 27 : les trois dans le
même commit), **`phone_launcher.dart`** — le `tel:` que le *client* compose,
seul endroit où l'E.164 sert à un utilisateur —, `promo.controller.ts:232` et
`admin.controller.ts:209,404` qui servent le numéro, `audit-log.service.ts:194`
qui l'affiche en libellé, la recherche admin `ILIKE`, et les ~8 scripts de banc.

**Ce qui a été livré le 2026-08-15** : `commercant/telephone.ts` (le seul
endroit qui sait à quoi ressemble un numéro ici), le validateur
`EstTelephoneDuPays` qui lit le pays voisin dans le DTO, la colonne `pays`,
l'unicité composite sous **le même nom d'index** (`saveNewAccount` traduit son
`23505` en « numéro déjà pris » — le renommer aurait rendu ce refus en `500`),
la normalisation à l'inscription **et** à la connexion, et la migration
`1783890000000`, qui **lève sur collision** plutôt que d'arbitrer un doublon à
notre place. La recherche admin `ILIKE` n'a pas eu à bouger : la forme stockée
reste la forme nationale, celle qu'on tape.

⚠️ **Le pays déclaré fait autorité, et ce n'était pas acquis.**
`parsePhoneNumberFromString('+971551234567', 'DZ')` rend un numéro **valide** —
l'indicatif explicite l'emporte sur l'indication de pays. Sans le contrôle
`country === pays`, un numéro émirati saisi sous « Algérie » aurait été accepté
et stocké sous un pays qu'il n'a pas : la colonne serait décorative et
l'unicité composite ne voudrait plus rien dire. Éprouvé par mutation.

### 6.1 Côté Odoo : `country_id` est obligatoire, pas recommandé

`phone_sanitized` vient du module **`phone_validation`** (`auto_install`, mais
à **déclarer** en dépendance — un auto-install n'est pas une dépendance).
`_phone_get_country` suit cet ordre : argument explicite → `country_id` de la
fiche → pays d'un partenaire lié → **`self.env.company.country_id`**.

⚠️ Un commerçant étranger sans `country_id` recevrait donc un `phone_sanitized`
fabriqué avec l'indicatif de la société Odoo — **un E.164 faux**, et le
garde-fou pays du Call Tracker mordrait dans le mauvais sens. `country_id` est
posé à la création, toujours.

Pourquoi cela compte : le rapprochement d'appel compare les **9 derniers
chiffres**, avec un garde-fou pays qui ne mord que si les deux numéros portent
un indicatif. Le README du module cite la collision Algérie / Dubaï —
`+213 555 12 34 56` et `+971 55 512 3456` donnent tous deux `555123456`.

---

## 7. Transport

### 7.1 Route

`POST /echango_promo/merchants/sync`, module `echango_promo_crm`.

- `type='http'` et non `type='json'` : le second impose l'enveloppe JSON-RPC
  (erreurs en HTTP 200). *(En 19.0, `type='json'` est de surcroît un alias
  déprécié de `type='jsonrpc'`.)*
- `auth='public'` et **non** `auth='none'` : avec `none`, `env.uid` vaut `None`
  et `sudo()` ne le répare pas — le défaut surgit au *flush* sous la forme d'un
  `ValueError: Expected singleton: res.users()` dont la trace ne mentionne ni
  authentification ni contrôleur.
- ⚠️ **`readonly=False`, sans quoi chaque lot est traité DEUX FOIS.** Odoo 19
  sert d'abord chaque requête sur un curseur en lecture seule et ne rejoue en
  écriture qu'après avoir vu l'`INSERT` échouer. L'upsert étant idempotent,
  **le lot passe** : validation, liste blanche, recherche et écriture
  s'exécutent deux fois, avec une exception au journal à chaque page. Ça ne
  plante pas — c'est pire.
- Tous les accès base en `sudo()` : le jeton ne porte **aucun** droit Odoo.

### 7.2 Le jeton

Patron repris de `call_tracker`, **en entier** :

- seule l'**empreinte SHA-256** est stockée, sur un champ réservé à
  `base.group_system` ;
- le clair n'existe qu'une fois, dans un `TransientModel` à
  `_transient_max_hours = 0.1` — un transient est une vraie ligne en base, qui
  traîne dans les sauvegardes ;
- régénérer révoque ; `active = False` révoque ; l'authentification revérifie
  `active` **à chaque requête, sans cache**, donc la révocation est immédiate.

⚠️ **Une différence structurelle avec le patron.** `call.tracker.device.user_id`
est `required=True` et c'est de lui que viennent l'attribution des appels **et**
le cloisonnement des règles d'enregistrement. Une source « echango Promo » n'a
pas d'utilisateur : il faut un **modèle distinct** (`echango.promo.source`),
sans `user_id`, et le cloisonnement de nos modèles ne peut donc pas s'appuyer
dessus (§8.6).

Côté Promo, le jeton vit dans le `.env` — donc dans **les trois endroits** de
la règle 36. **Son absence empêche le cron de tourner**, avec un journal
explicite : ni envoi sans authentification, ni échec muet chaque nuit
(règle 29). Tout réglage numérique passe par `configNumber`, jamais
`get<number>`.

### 7.3 Format et robustesse

- **Liste blanche stricte** : un champ inattendu fait **rejeter** le lot. Un
  champ inconnu signale un désaccord de version, et l'ignorer produirait des
  fiches amputées que personne ne remarquerait.
  ⚠️ **Conséquence directe sur le déploiement** : le jour où le contrat gagne
  un champ, **Odoo se déploie AVANT Promo**. L'ordre inverse fait tomber 100 %
  des lots.
- **Idempotence par `promo_uuid`**, avec les deux garde-fous du dépôt : la
  recherche préalable **et** un index unique SQL posé dans `init()` — pas en
  `_sql_constraints`, dont l'API déclarative a bougé entre versions récentes.
- **Un `savepoint` par fiche** : sur 200 objets, un seul invalide ne doit ni
  perdre le lot ni passer inaperçu. La réponse dit combien de fiches ont été
  prises, combien refusées, et lesquelles.
- **Jamais de rapprochement par téléphone.** *(Rappel du défaut réel : P10
  n'était pas une fusion mais l'inverse — `login` retrouvait la ligne
  supprimée et enfermait dehors le repreneur du numéro.)*
- **Pages de 200**, bornées **côté serveur** : 200 est une décision de
  l'émetteur, pas une limite.

### 7.4 Journal et détection du silence

**Un modèle d'audit, comme `call.tracker.audit`** : chaque lot, accepté ou
refusé, laisse une ligne — IP, jeton résolu ou non, motif, nombre de fiches —
écrite dans un `try/except` qui **n'échoue jamais l'appel**, et purgée à la
même durée que les données qu'elle décrit. Sans lui, le banc du lot 5 prouve
qu'un lot refusé est refusé… et personne ne peut le constater en production.

**Un organe de silence.** `genere_le` stocké *sur chaque fiche* ne suffit pas :
si aucun lot n'arrive, **aucune fiche ne bouge** et rien n'alerte tant qu'un
humain n'ouvre pas une fiche. Le dépôt a l'organe exact — un `last_seen` sur la
source, un champ calculé `silencieux`, et un écran ouvert au responsable, parce
que « aucun commerçant n'a publié » et « le lot n'est pas arrivé » produisaient
sinon le même écran.

---

## 8. Côté Odoo

### 8.1 Modèles et propriété des champs

| Modèle | Rôle |
|---|---|
| `res.partner` | le commerçant, vue 360°, **semé à la création** |
| `echango.promo.account` | les faits du §4, **écrits à chaque lot** |
| `echango.promo.source` | la source et son jeton (§7.2) |
| `echango.promo.suivi` | **vue SQL** (`_auto = False`) : faits dérivés |

**La frontière de propriété passe par le modèle, pas par un verrou.** Le verrou
`write()` de `call_tracker` teste `if not self.env.su` : **`sudo()` passe,
délibérément**, puisque c'est par là qu'écrit le contrôleur. Transposé tel quel
il protégerait l'humain et jamais le lot. Donc :

- `echango.promo.account` porte **toujours** la valeur Promo courante, et est
  en lecture seule pour les humains ;
- `res.partner` est **semé à la création** (nom, adresse, ville, `country_id`,
  tag) puis **jamais réécrit**, à une exception : le **téléphone**, qui est la
  clé de rapprochement des appels et appartient à Promo ;
- un indicateur **divergence** signale un écart entre les deux. Une correction
  commerciale n'est ni perdue ni silencieuse — elle est visible.

**La position reste sur `echango.promo.account`**, pas sur
`partner_latitude`/`partner_longitude`. ⚠️ `base_geolocalize` **remet ces deux
champs à `0.0`** dès que `street`/`zip`/`city`/`state_id`/`country_id` change :
écrire la ville géocodée effacerait la position qui vient de la produire.

**La provenance est un tag** (`res.partner.category_id` « echango Promo »),
posé à la création, jamais un critère mutable. ⚠️ **Vérifié sur les sources
Odoo 19.0** (arbre complet, 126 classes étendant `res.partner` scannées) :
`res.partner` **n'a plus** de champ `team_id` — disparu dès la 18.0.
`addons/sales_team/models/` ne contient que `crm_tag`, `crm_team`,
`crm_team_member`, `res_users`. Une équipe sur la fiche client n'est pas
exprimable ; l'estampille a été écartée le 2026-08-15.

⚠️ **La fusion de contacts casse l'appariement.** Le module `contacts` est
installé et apporte la déduplication : une fusion laisserait deux
`echango.promo.account` sur un partenaire, ou un compte orphelin. La clé
étrangère est portée par `echango.promo.account`, avec une contrainte d'unicité
sur `partner_id` et un traitement explicite du cas.

### 8.2 Les six états sont des filtres, pas une colonne

Décision : la vue SQL n'expose que des **faits** — `jours_depuis_derniere_publication`,
`peut_publier`, `promos_en_ligne`, `est_active`. Les six états sont des
**filtres de recherche Odoo**, avec leur ordre de précédence :

| Rang | État | Condition |
|---|---|---|
| 1 | **Bloqué** | `peut_publier = false` — action interne, **jamais** une relance |
| 2 | **Non activé** | `est_active = false` |
| 3 | **Actif** | `promos_en_ligne > 0` |
| 4 | **En pause** | dernière publication < 7 j |
| 5 | **À risque** | 7 à 21 j |
| 6 | **Dormant** | > 21 j |

⚠️ **La précédence n'est pas décorative** : « Actif » et « En pause » sont
simultanément vrais pour qui a publié avant-hier. Sans ordre écrit, la vue en
choisit une.

⚠️ **Et la v1 se contredisait** : un `CASE WHEN … 7 … 21` dans le `init()`
d'une vue SQL exige `--update` + restart, donc un redéploiement — ce n'est pas
« réglable sans redéploiement ». En filtres, changer un seuil reste une mise à
jour de module, mais l'équipe peut créer ses propres filtres et favoris sans
toucher au code. C'est ce qui a été demandé.

⚠️ **« Bloqué » est un instantané de la nuit.** Un commerçant débloqué à 08:00
reste affiché bloqué jusqu'au lendemain 04:00, et l'activité créée par le batch
porte sur une situation résolue. L'écran affiche la fraîcheur (`genere_le`) à
côté du motif.

### 8.3 Écrans

Greffés sous `crm.crm_menu_root`, comme le reste du dépôt.

1. **Non affectés** — badge en tête. ⚠️ **Obligatoire** : la Couverture du
   portefeuille filtre sur `WHERE compte.user_id IS NOT NULL` (figé par
   `test_couverture.py`). Un commerçant fraîchement synchronisé n'apparaît
   nulle part : ni dans les appels (jamais appelé), ni dans la couverture (pas
   de commercial).
2. **Suivi des commerçants** — la vue SQL, triée dernière publication
   `asc nulls first`.
3. **À débloquer** — groupé par motif, avec les trois cas de registre séparés.
4. **Par ville** — vue pivot.

**Pas de vue carte** : `web_map` **n'existe pas** dans l'arbre 19.0 (classé
Enterprise). *La v1 attribuait ce fait à `REPORTING_KPI.md`, qui n'en parle
pas ; ce document n'établit que Community et l'absence d'éditeur Spreadsheet.*
Nuance à assumer : Leaflet et les tuiles OSM **sont livrés en Community** (le
module `delivery` en fait un usage), donc l'absence de carte est une décision
de coût, pas une impossibilité.

Et sans rien développer : la **Couverture du portefeuille** et les **appels** du
Call Tracker se branchent sur ces fiches. Le croisement utile — *« n'a pas
publié depuis 14 j » × « jamais appelé »* — sort de l'existant.

### 8.4 Géocodage inverse

**Rien à arbitrer : `base_geolocalize` est en Community** et embarque le client
Nominatim avec son endpoint inverse (`/reverse`), deux fournisseurs déjà
déclarés (`openstreetmap`, `googlemap`).

- **Une fois par commerçant**, à la découverte ; re-géocodage uniquement si la
  position reçue a bougé de plus de ~200 m.
- Le résultat renseigne `city` / `state_id` / `country_id` sur `res.partner`.
- ⚠️ La position **source** reste sur `echango.promo.account` — voir le piège
  du `0.0` en §8.1.
- Trois états à distinguer, surtout pas à confondre en une case vide : « pas de
  position », « géocodage non encore fait », « géocodage sans résultat ».

### 8.5 Rétention

Patron de `CALL_TRACKER_RETENTION_DAYS` : réglage d'environnement, cron
quotidien, **repli `0` = aucune purge**, journalisé dans les deux branches.
*(Précision : 1 095 jours est la valeur du `.env.production.example` ; le défaut
du compose est `0`.)*

- **Point de départ de l'horloge : la date du fait**, comme le module voisin
  compte sur `started_at` et non sur `create_date`. Ici, la date d'archivage.
- **Commerçant toujours envoyé** → relation vivante, aucune purge.
- **Commerçant `supprime_le` renseigné** → `active = False` **immédiatement**
  (décision du 2026-08-15), puis purge de `echango.promo.account` au terme de la
  durée. Le `res.partner` n'est pas supprimé s'il porte de l'activité
  commerciale (appels, notes, activités) : l'effacement d'un correspondant est,
  chez le voisin, une **procédure manuelle sur trois modèles** — elle le reste.
- ⚠️ **Conséquence assumée** : un commerçant archivé sort de la Couverture du
  portefeuille (`AND compte.active`), donc de l'écran qui montre ce qui ne
  s'est pas passé. Décision prise, pas découverte.

### 8.6 Sécurité

**Rien n'est lisible sans droits déclarés** — un modèle sans
`ir.model.access.csv` est invisible pour tout le monde, admin compris.

- `ir.model.access.csv` pour les trois modèles ; pour la vue SQL,
  `perm_write/create/unlink = 0`.
- Deux niveaux via `res.groups.privilege` + `res.groups`, greffés par
  `implied_ids` sur `sales_team.group_sale_salesman` et `group_sale_manager` —
  sans quoi **personne** n'a accès après installation.
- **Ordre dans le manifeste** : groupes → `ir.model.access.csv` → règles →
  data → vues → menus.
- **Périmètre de visibilité** : par défaut, **tout le parc est visible** au
  groupe echango Promo. Le cloisonnement éventuel est une **configuration
  Odoo** (règles d'enregistrement), décision du 2026-08-15 — et il ne peut pas
  s'appuyer sur `user_id` de la source, qui n'existe pas (§7.2).

### 8.7 Conventions Odoo 19 du dépôt

- `res.groups.category_id` **n'existe plus** — c'est `privilege_id`. ⚠️ Mais le
  `category_id` vers `ir.module.category` existe toujours **sur
  `res.groups.privilege`**, et c'est ce que fait le dépôt : l'omettre range les
  groupes nulle part dans la fiche utilisateur. Contrainte associée :
  `UNIQUE (privilege_id, name)`.
- **Pas de `noupdate="1"` sur les groupes** (appliqué à l'installation, ignoré
  à la mise à jour — le dépôt y a perdu tous les accès en silence). Le cron, lui,
  le garde délibérément.
- Vue SQL ⇒ `flush_model()` **sur les modèles sources que la vue lit**, pas sur
  le modèle `_auto = False` lui-même, qui n'a rien à écrire. Un
  `self.flush_model()` serait un correctif inopérant.
- **`aggregator` se décide champ par champ**, pas par une règle globale :
  `promos_en_ligne` en somme a un sens, `plafond_effectif` en somme n'en a
  aucun et affichera un total absurde dans le pivot « Par ville »
  (`aggregator=False`). Un champ nommé `sequence` prend `None` d'office.
- Extensions de `res.partner` en `position="inside"` sur `button_box`, jamais
  `position="replace"`.
- `tests/__init__.py` : **un fichier de test non importé ne s'exécute jamais et
  ne produit aucune erreur.**

### 8.8 Brancher le module — trois fichiers, sinon rien ne se passe

- **`--init=` dans les DEUX composes** (`docker-compose.yml` et
  `docker-compose.crm.yml`) : un addon posé dans `addons/` ne s'installe
  **pas** tout seul — le dépôt l'a constaté sur `call_tracker` lui-même.
  *(Au passage : le commentaire de `docker-compose.yml` affirmant que
  `call_tracker` n'est pas dans la liste de production est faux aujourd'hui.)*
- **`.github/workflows/tests.yml`** : la CI lance `--init=call_tracker
  --test-tags=/call_tracker`. Sans modification, notre suite **ne tourne pas et
  la CI reste verte**. ⚠️ Son garde-fou est un `grep -q "0 failed, 0 error(s)"`
  — parce qu'Odoo rend 0 même quand des tests échouent : ajouter un second
  module change la ligne de bilan, et reprendre le `grep` sans y penser rend la
  CI verte sur une suite rouge.
- **Mise à jour** : `--update=echango_promo_crm --stop-after-init` puis
  `restart`, et une version de manifeste incrémentée.
- ⚠️ `echangocrm_bootstrap` **lève** si `ODOO_ADMIN_PASSWORD` est absente, dans
  la transaction qui installe tous les modules : sur un environnement mal
  renseigné, le CRM ne monte pas et le message ne parlera pas de notre module.

---

## 9. Ce qui est exclu, et pourquoi

| Exclu | Raison |
|---|---|
| Toute donnée de client final | Anonymat par conception ; le CRM ne doit pas être la porte dérobée qui l'annule |
| Les promos, une par une | Le CRM n'en a pas besoin |
| L'écriture depuis Odoo vers Promo | Dupliquerait les écrans admin ; l'équipe CRM n'a aucun accès à Promo |
| Les prospects non inscrits | Décision produit |
| Une vue carte | `web_map` absent de Community — décision de coût, voir §8.3 |
| Un tableau de bord Spreadsheet | Éditeur Enterprise ; pivot et graphe natifs suffisent |
| `team_id` sur la fiche | N'existe plus en Odoo 19 (§8.1) |
| Un dossier `i18n/` | **Cohérent avec le dépôt** : `call_tracker` n'en a pas, les libellés sont en français via `_()`. Ce n'est pas un oubli |
| Un flux temps réel | Un batch nocturne suffit à un suivi commercial |
| `Highlight` (mise en avant) | Levier commercial réel, mais hors périmètre V1 — à rouvrir si la mise en avant devient négociable |

---

## 10. Conformité (loi 18-07)

> ⚠️ Ce paragraphe décrit un dispositif technique, il ne vaut pas avis
> juridique.

**Le versement des données commerçant dans un CRM de suivi commercial est une
extension de finalité.** Le commerçant a communiqué son numéro pour utiliser
echango Promo, pas pour être prospecté.

| Emplacement | Contenu | Durée |
|---|---|---|
| `echango.promo.account` | les faits du §4 | vivante tant que Promo l'envoie ; purge après archivage |
| `res.partner` | nom, téléphone, adresse, ville | **indéfinie** — donnée commerciale |
| `echango.promo.audit` | lots reçus et refusés, IP | même durée que les données décrites |
| Fil de discussion, activités | notes commerciales | **indéfinie** |

Deux faits à poser noir sur blanc :

1. **`consentedAt` est `null` pour tous les comptes créés par un agent** — par
   conception (`createByAgent` ne le pose jamais ; `CreateCommercantByAgentDto`
   n'a pas de champ d'acceptation, et la route est réservée aux agents). Sur le
   pilote, c'est la majorité des fiches. Le champ est exporté et affiché pour
   que la décision se prenne les yeux ouverts.
2. Les CGU sont notées « à traiter avant toute ouverture publique »
   (specs §7.4). **Cette intégration est ce qu'elles devront couvrir.**

**Procédure d'effacement** : manuelle, sur `echango.promo.account`,
`res.partner` et le fil `mail.message` associé — comme chez le module voisin,
et pour la même raison : effacer une donnée commerciale supprimerait
l'historique d'une relation en cours.

---

## 11. Points ouverts

1. **La file « à débloquer » est acheminée automatiquement, pas résolue
   automatiquement.** Un registre se valide en regardant une photo. Le batch
   crée l'activité et notifie ; **le destinataire côté Promo n'est pas nommé**.
   Le §5 sépare désormais `registre_absent` (le commerçant) de
   `registre_en_attente` (nous) — c'est la donnée qui tranche la question.
2. **Le fuseau des tâches planifiées de Promo** (§3) : à poser, pas à subir.
3. **Le seuil de mesure du §3.4** — à partir de combien de fiches le
   rapprochement d'appel se dégrade réellement. Personne ne l'a mesuré.
4. ~~**Quels pays le sélecteur mobile propose.**~~ **Fermé le 2026-08-15** :
   les **245** pays connus de libphonenumber, table générée par
   `apps/mobile/tool/generer_pays.mjs` depuis la **même bibliothèque** que le
   serveur. Les trois écrans de saisie envoient désormais le code ISO.
5. ~~**Le lien `tel:` du client n'est pas internationalisé.**~~ **Fermé le
   2026-08-15** par la bascule en E.164 : `GET /commercant/:id/public` sert
   désormais `+213555900201`, donc `phone_launcher.dart` compose un numéro
   valide depuis n'importe quel pays. Mesuré, pas déduit.

---

## 12. Ordre de mise en œuvre

| Lot | Contenu | Dépôt |
|---|---|---|
| **0** ✅ | Table ordonnée des motifs + deux rendus + le contrôle d'équivalence (§5.1) — *fait le 2026-08-15, `publication-eligibility.ts`, 41 cas dont 2 mutations* | Promo |
| **1** ✅ | Migration de normalisation → colonne `pays` → unicité composite → validateur → connexion → **sélecteur mobile 245 pays + `.arb`** — *fait le 2026-08-15* | Promo |
| **2** | Quatre CTE + `@Cron(04:00)` avec fuseau + en-tête de lot + jeton + refus si jeton absent | Promo |
| **3** | Module : `security/` **livré avec** les modèles, contrôleur `readonly=False`, jeton haché, savepoint, audit, tag | CRM |
| **4** | Vue SQL, filtres des six états, quatre écrans, géocodage, rétention | CRM |
| **5** | **Brancher** : `--init` dans les deux composes, `tests.yml` et son `grep`, `--update` documenté | CRM |
| **6** | Tests des deux côtés, dont un banc qui prouve qu'un lot refusé **est** refusé, et le contrôle d'équivalence du lot 0 | les deux |

Les lots 0 et 1 ont une valeur propre, indépendante du CRM — le lot 1 corrige
un défaut qui existe aujourd'hui. Le lot 3 ne peut pas livrer les modèles sans
les droits : les écrans du lot 4 s'ouvriraient en erreur d'accès. Le lot 6
n'est pas une finition : un contrôle qu'on n'a jamais vu refuser n'a montré que
sa capacité à dire oui.
