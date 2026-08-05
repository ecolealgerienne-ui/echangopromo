# Statut d'implémentation — echango Promo V0.1

**Ce fichier est le suivi vivant du projet à partir du 2026-08-04.** Il doit
être mis à jour à chaque implémentation importante — nouvelle fonctionnalité,
correction d'audit, changement d'architecture, décision produit — et pas
seulement en fin de session.

Dernière mise à jour : **2026-08-04**

---

## Rapport aux autres documents

| Document | Rôle | État |
|---|---|---|
| `docs/status_v0.md` | journal de la V0 | **figé** — dernière entrée 2026-07-12 |
| **`docs/status_v0.1.md`** *(ce fichier)* | **journal courant** | actif |
| `docs/METHODE_TEST.md` | la méthode de test, générique à la stack Echango | référence |
| `docs/TEST_PROMO.md` | son instanciation sur ce produit, avec les valeurs réelles | référence |
| `CLAUDE.md` | les 27 règles à respecter | référence |
| `docs/AUDIT_V0.md`, `AUDIT_V1.md` | findings détaillés, fichier:ligne | historique |

> ⚠️ **Un trou de journal existe entre le 2026-07-12 et le 2026-08-04.** Les
> 42 commits des 29–31 juillet (parcours de premier lancement, carte « autour de
> moi », refonte visuelle, bandeau Top promos, préparation à la publication, CI
> Codemagic) **ne figurent dans aucun journal**. Ils sont dans l'historique git
> et dans la PR #13, rien de plus. Ce document ne les reconstitue pas
> rétroactivement — une reconstitution de mémoire serait une donnée d'appui
> fausse en puissance. Il en prend acte et repart d'un état **mesuré**.

---

## État mesuré au 2026-08-04

Mesuré, pas estimé. La méthode et les commandes sont dans `docs/TEST_PROMO.md` §1.

| Composant | État |
|---|---|
| Branche de référence | `main` = `77e788a` (merge PR #13) |
| Branche de travail | `claude/echango-promo-suite-2026-08-04` |
| Backend | 11 contrôleurs, **62 routes** dont 14 ouvertes, 42 codes d'erreur |
| Backend — build | ✅ 0 erreur TypeScript, démarre, migrations à jour |
| Mobile — `flutter analyze` | ✅ **1 avertissement** (import inutilisé) — première analyse par un vrai SDK |
| Mobile — build Android | ✅ compilé et exécuté sur émulateur, connecté au backend local |
| Tests backend | 5 fichiers `.spec.ts` |
| Tests unitaires mobile | 5 fichiers |
| Tests d'écran | **0** — `integration_test/` n'existe pas |
| Écrans | 34 `*_screen.dart` |

**Ce qui a changé dans la connaissance du projet** : le code mobile avait été
« relu statiquement mais jamais compilé » depuis le début du projet (consigne de
`CLAUDE.md`). Ce n'est plus vrai depuis le 2026-08-04 — il compile, tourne, et
`flutter analyze` ne remonte qu'un import inutilisé.

---

## Points ouverts

Classés par ce qu'ils coûtent s'ils restent ouverts. Chacun porte ce qui le
débloque.

### P1 — Un code d'erreur sans décision écrite 🔽 *revu à la baisse le 2026-08-04*

> ⚠️ **Ce point a été formulé, puis corrigé le même jour.** Première version :
> « cinq codes servis et jamais traduits », présentés comme cinq défauts
> visibles par l'utilisateur. **C'était faux pour quatre d'entre eux.**

**Ce qui est établi.** L'en-tête de `error_messages_fr.dart` documente que
`PROMO_DATE_FIN_EXCEEDS_MAX`, `PROMO_ACTIVE_CAP_REACHED`,
`PROMO_DAILY_CREATION_CAP_REACHED` et `PROMO_REPUBLISH_TOO_SOON` sont
**volontairement absents** : leur message backend interpole une valeur (plafond,
durée, délai restant) qu'un mapping statique perdrait.
`ApiException.displayMessage` retombe alors sur le message brut
(`api_exception.dart:52`). Arbitrage assumé, pas oubli.

**Ce qui reste ouvert** : `HIGHLIGHT_CAP_REACHED` (`highlight.service.ts:222`)
n'est **ni traduit, ni épinglé** comme exclusion. Son message interpole lui
aussi une valeur, il appartient donc probablement à la même famille — mais rien
ne le dit. Une exclusion non écrite est indiscernable d'un oubli.

**Le prix de ces exclusions, à garder conscient** : le message backend est
toujours en français. Un commerçant arabophone qui atteint le plafond de
5 promos voit une phrase en français. Si ce prix devient inacceptable, la sortie
n'est pas un mapping statique — il reperdrait la valeur — mais des paramètres
portés par la réponse serveur, l'app composant la phrase.

**Pourquoi l'erreur a été commise, et ce qu'elle a produit de bon.** Les
exclusions vivaient dans un **commentaire**, qu'aucun outil ne peut lire. Le
vérificateur les a donc toutes signalées, et j'ai conclu trop vite à cinq
défauts. La liste vit désormais **en donnée**, dans
`apps/mobile/tool/check_error_codes.dart`, chaque entrée portant sa raison, et
l'auto-test **refuse une exclusion sans justification**. C'est le mode M5 du
générique appliqué à une liste d'exceptions — et l'illustration qu'**un contrôle
peut aussi mentir en disant non**.

**✅ Fermé le 2026-08-04.** Décision : `HIGHLIGHT_CAP_REACHED` **traduit** dans
les 3 tables. ⚠️ **Sans recopier le plafond** — le message backend interpole
`HIGHLIGHT_MAX_SLIDES`, et reproduire ce nombre côté app dupliquerait une
constante serveur (règle 7). La formulation porte le **geste à faire**, qui ne
dépend pas du nombre. Le vérificateur est vert : 38 clés par table.

**Reste ouvert, mineur** : le commentaire d'en-tête de `error_messages_fr.dart`
décrit toujours les exclusions, alors que la liste fait foi dans
`tool/check_error_codes.dart`. Deux sources de vérité tant que le commentaire
ne pointe pas vers le vérificateur. ⚠️ Modification d'un fichier existant —
voir A1.

### P2 — Aucun contrôle exécuté ne tient les couples serveur ↔ app

Six couples doivent rester d'accord ; **aucun n'est tenu par autre chose qu'une
consigne** (`docs/TEST_PROMO.md` §3). P1 est la démonstration que ça ne suffit
pas.

Le plus exposé après les codes d'erreur : `CommercantAccountState`, comparé par
**chaîne littérale** dans plusieurs écrans (règle 19). Un renommage backend ne
produirait aucune erreur de compilation.

**Débloqué par** : étape 2 de `docs/TEST_PROMO.md` — le squelette
`check-sync.dart` tourne déjà sur les vrais fichiers, il reste à le déplacer
dans `apps/mobile/tool/` et à l'éprouver par mutation.

### P3 — `PROMO_MAX_DURATION_DAYS` absente du `.env`

Huit clés présentes dans `.env.example` manquent au `.env` local :
`ANDROID_PACKAGE_NAME`, `ANDROID_SHA`, `IOS_TEAM_ID`, `IOS_BUNDLE_ID`,
`PLAY_STORE_URL`, `APP_STORE_URL`, `CORS_ORIGINS`, `PROMO_MAX_DURATION_DAYS`.

Aucune n'empêche le démarrage. Mais la dernière **pilote une règle métier**
(`PROMO_DATE_FIN_EXCEEDS_MAX`) : un banc qui l'éprouve sans elle teste la valeur
par défaut du code, pas celle de production — et conclut juste sur le mauvais
nombre. `CORS_ORIGINS` mérite d'être fixée aussi.

> **Règle qui en découle** : tout banc qui éprouve une borne configurable
> **imprime la valeur qu'il a effectivement utilisée**. Une borne lue depuis
> l'environnement est une donnée d'entrée du banc, pas une constante.

### P10 — Un numéro recyclé enferme son repreneur dehors 🔴 **défaut réel, ouvert**

**Trouvé le 2026-08-04** par `test-cycle-commercant.sh`. Reproduit sur un numéro
neuf, avec témoin positif :

```
1. Premier inscrit       → connexion OK          ← témoin
2. Premier supprimé      → numéro libéré
3. Second inscrit        → accepté
4. Connexion du Second   → AUTH_INVALID_CREDENTIALS   ❌
```

**Cause, à la ligne près.** `CommercantService.login` (`commercant.service.ts:125`)
cherche par téléphone **sans** filtrer les comptes supprimés :

```ts
const commercant = await this.commercants.findOne({ where: { telephone } });
```

alors que `assertPhoneAvailable` (`:59`), lui, applique bien le filtre :

```ts
where: { telephone, deletedAt: IsNull() }
```

La suppression étant **douce**, la ligne reste en base : un numéro recyclé a
plusieurs lignes. `findOne` en attrape une supprimée, la ligne 130 voit son
`deletedAt` et refuse. Le nouveau propriétaire du numéro **ne peut jamais se
connecter**.

**Portée.** Le défaut n'apparaît qu'après un cycle suppression → réinscription
— c'est-à-dire exactement le cas que la libération du numéro (décision produit
2026-07-13/14) existe pour permettre. La fonctionnalité est donc inutilisable
dans les faits, sans que rien ne le signale : l'inscription réussit, seule la
connexion suivante échoue, avec un message qui accuse les identifiants.

**C'est la règle 5 de `CLAUDE.md` à la lettre** : deux endroits doivent
appliquer le même filtre, un seul l'applique. Le commentaire
d'`assertPhoneAvailable` dit même « même filtre que l'index partiel posé en
base » — la phrase existe, elle ne tient rien.

**Correctif proposé** — une ligne, non appliquée (code source non modifié) :

```ts
findOne({ where: { telephone, deletedAt: IsNull() } })
```

⚠️ À vérifier dans le même geste : les autres recherches par téléphone
(`resetPin`, `findByPhone`…) appliquent-elles le filtre ? Une seule corrigée
laisserait la règle 5 ouverte ailleurs.

### P9 — `S3_ENDPOINT` sert deux rôles incompatibles 🆕 *contourné en local*

**Trouvé le 2026-08-04** en instrumentant le banc de concurrence : une création
de promo prenait **plus de 300 secondes**.

```
WARN [PromoService] Échec de génération de la miniature :
     TimeoutError: connect ETIMEDOUT 10.0.2.2:9000
```

`S3_ENDPOINT` valait `http://10.0.2.2:9000` — l'alias de l'hôte **vu depuis
l'émulateur Android**, choisi pour que le mobile puisse charger les images. Mais
la même variable est le point d'accès du **client S3 du serveur**
(`storage.service.ts:72`), et `10.0.2.2` n'est pas routable depuis WSL. Chaque
création attendait donc un timeout TCP.

**Une valeur juste dans un contexte, fausse dans l'autre** — et le `.env`
documentait même le choix sans voir qu'il servait deux consommateurs.

**Contourné en local** : les deux rôles sont désormais séparés, avec le
mécanisme qui existait déjà.

```
S3_ENDPOINT=http://localhost:9000                     # ce que le SERVEUR appelle
S3_CDN_BASE_URL=http://10.0.2.2:9000/echango-promo    # ce que le CLIENT reçoit
```

Création de promo : **300 s → 88 ms**.

⚠️ **Ce n'est qu'un contournement local** (`.env`, non versionné). Deux
questions restent ouvertes pour l'équipe : le `.env.example` devrait-il porter
cette séparation, et la génération de miniature — best-effort, mais **dans le
chemin de création** — mérite-t-elle un timeout court plutôt que celui du SDK ?

### P4 — Le verrou du plafond de 5 promos ✅ *fermé le 2026-08-04*

**Fermé** par `scripts/test-plafond-promos.sh` : **5 tours × 4 créations
simultanées, 1 seul gagnant à chaque tour, 5 actives après**.

**Prouvé par mutation** — le verrou rendu non sérialisant
(`hashtext($1 || clock_timestamp())`, donc un verrou différent par
transaction) : **4 créations sur 4 réussissent**, sur les 3 tours. C'est le
défaut d'origine reproduit à l'identique.

⚠️ **Ma première mutation était invalide** et mérite d'être notée : remplacer la
requête par `SELECT 1` cassait le paramètre lié et rendait `INTERNAL_ERROR`. Le
banc a dit « non concluant » — correctement — mais **mon harnais** avait conclu
« ✅ » sur le seul code de sortie non nul. Une mutation qui **casse** au lieu de
**dégrader** ne prouve rien, et un harnais qui juge sur le code de sortie plutôt
que sur le motif attendu se trompe de question.

<details><summary>Le constat d'origine</summary>

La race condition sur `MAX_PROMOS_ACTIVES` (`promo.service.ts:43`) a été
corrigée par un `pg_advisory_xact_lock` scopé au commerçant. **La correction n'a
jamais été rejouée sous charge.** Un banc de concurrence est probabiliste : un
passage au vert ne prouve rien, il en faut plusieurs tours.

**Débloqué par** : étape 4 de `docs/TEST_PROMO.md`, banc `test-plafond-promos`.

</details>

### P5 — L'IDOR agent → promo ✅ *fermé le 2026-08-04*

**Fermé** : rejoué et prouvé par mutation — voir T1 et le journal. Le périmètre
couvert va bien au-delà de la promo d'origine : les **14 routes** à identifiant
accessibles à un agent.

<details><summary>Le constat d'origine</summary>

La faille critique de l'audit V0 (un agent authentifié pouvait modifier les
promos de n'importe quel commerçant) a été corrigée par
`CommercantService.assertZoneMatches`. Rien ne garantit aujourd'hui qu'elle
n'est pas revenue — et la polarité de protection du projet (garde posé **route
par route**) fait que **la route qu'on oublie est ouverte**.

**Débloqué par** : étape 1 de `docs/TEST_PROMO.md`, banc d'appartenance.

</details>

### P7 — Cinq miroirs d'enum avalent une valeur inconnue 🆕

**Trouvé le 2026-08-04** par `tool/check_enums.dart`, qui le signale sans
bloquer.

Cinq `fromValue` sur huit portent un `orElse` : **Catégorie**, **Cycle de vie
promo**, **Modération promo**, **État de compte commerçant**, **Motif de
signalement**. Une valeur ajoutée côté serveur y devient silencieusement autre
chose — sans erreur, sans journal.

Le cas le plus lourd : `PromoLifecycleStatus.fromValue` retombe sur
**`expiree`**. Un nouveau statut serveur ferait donc disparaître les promos
concernées de l'affichage client, et le diagnostic partirait chercher une
panne de données.

Les trois autres (`RegistreStatus`, `AuditActorType`,
`CommercantOriginVerification`) lèvent — comportement plus bruyant, donc plus
sûr.

**C'est un choix à rendre, pas un défaut à corriger d'office** : un repli peut
être délibéré. Mais aujourd'hui rien ne dit lequel l'est.

### P8 — La règle 19 est contournée dans les écrans 🆕

Les vérificateurs garantissent que les *valeurs* des miroirs sont justes ; ils
ne garantissent pas que les écrans **s'en servent**. Plusieurs comparent encore
`CommercantAccountState` par **chaîne littérale** (`status == 'autonome'`) : le
miroir existe, il est correct, et il est contourné.

**Débloqué par** un contrôle du même esprit — refuser une comparaison littérale
portant sur une valeur d'enum connue. Reste à écrire.

### P6 — Dette mineure, non bloquante

- `apps/mobile/lib/features/commercant/screens/commercant_login_screen.dart:4` —
  import inutilisé, seul avertissement de `flutter analyze`.
- ~~`apps/mobile/pubspec.lock` non versionné~~ — **fermé le 2026-08-04**
  (`1c1bf1d`). Il n'était ignoré nulle part, il n'avait jamais été ajouté.
  Versionné pour que la machine de développement et Codemagic résolvent le même
  graphe de dépendances.
- `npm install` backend signale **4 vulnérabilités** (1 modérée, 3 hautes), non
  examinées.
- Upload S3/MinIO **jamais éprouvé de bout en bout** contre un vrai bucket —
  dette héritée de l'audit V0, toujours ouverte.
- Aucun mécanisme de **backup** de la base — dette identifiée le 2026-07-12
  après l'incident de corruption, toujours ouverte.

---

## Trous de couverture

Relevés le **2026-08-04** en mesurant la surface réelle par profil (`@Roles` de
chaque route, écrans par dossier) et en la confrontant au plan de test. Le plan
d'alors prévoyait 8 bancs choisis par défaut historique : ils couvraient
**15 routes sur 62**, et le déséquilibre entre profils ne se voyait pas.

`docs/TEST_PROMO.md` §6 a été repris en conséquence : **27 bancs, 62 routes sur
62**.

| Profil | Routes | Écrans | Couvert par le plan d'alors |
|---|---|---|---|
| Admin | **35** | **13** | 3 bancs partiels |
| Agent | **26** | 3 | 1 banc |
| Commerçant | 17 | 7 | 1 banc + 1 parcours |
| Client | 14 (ouvertes) | 4 + 4 onboarding | 3 bancs |

*(les routes partagées comptent par profil, d'où un total supérieur à 62)*

### T1 — L'agent cumule le plus de pouvoir et la plus faible couverture ✅ *fermé le 2026-08-04*

**Fermé** par `scripts/test-appartenance.sh` : **14 sondes, 0 échec**. Les 14
routes à identifiant accessibles à un agent — dont suspendre, **supprimer**,
valider un registre, réinitialiser un PIN et modérer — rendent toutes
`403 COMMERCANT_NOT_IN_AGENT_COMMUNES` face à un agent d'une autre commune.

**Prouvé par mutation** : condition de `assertAgentOwnsCommercant`
(`commercant.service.ts:529`) neutralisée → l'agent intrus obtenait **201** sur
une action de modération. Le banc l'a vu.

Avec témoin positif restauré (l'agent légitime suspend puis réactive) et
contrôle de projection (la liste est filtrée par commune).

<details><summary>Le constat d'origine</summary>

**14 des 26 routes de l'agent sont sous `/admin/*`** : il suspend un commerçant,
le **supprime**, valide ou rejette son registre, réinitialise son PIN, modère
des promos. Le plan ne prévoyait qu'un banc d'appartenance **centré sur la
promo**.

La question « un agent hors de ses communes peut-il suspendre *ce* commerçant ? »
n'était posée nulle part. C'est la forme exacte de l'IDOR critique de l'audit
V0, sur une surface **sept fois plus grande** que celle qui avait été corrigée.

**Traité dans le plan** par `test-agent-appartenance`, étendu aux 16 routes
concernées et remonté en priorité 4 du §9.

</details>

### T2 — L'admin : plus grande surface, trois bancs partiels

Non couvert avant reprise : le module **highlight** (5 routes, livré fin
juillet, jamais éprouvé, et porteur du `HIGHLIGHT_CAP_REACHED` de P1), la
**gestion des agents** (6 routes dont `transfer-communes` — précisément ce que
l'`AuditLogModule` devait tracer), l'**audit-log** lui-même, le **dashboard**
(historique de surcompte).

**Traité** par `test-admin-highlight`, `test-admin-agents`,
`test-admin-audit-log`, `test-admin-dashboard`.

### T3 — Le module notifications n'était couvert nulle part

5 routes, partagées par les 3 profils authentifiés, 1 écran. Zéro banc, zéro
parcours. **Traité** par `test-notifications`.

### T4 — `DELETE /commercant/me` n'est éprouvé par rien 🔶 *partiellement traité*

⚠️ **Toujours ouvert.** `test-cycle-commercant.sh` éprouve la suppression **par
l'admin** (`POST /admin/commercant/:id/delete`), pas l'**auto-suppression** par
le commerçant lui-même. Le code dit que les deux ont le même effet
(`deleteAccount` ≡ `deleteCommercant`) — mais c'est une lecture, pas une mesure,
et la règle 5 dit précisément ce que valent deux implémentations censées
s'accorder. Une sonde de plus dans le banc existant suffirait.

<details><summary>Le constat d'origine</summary>

Un commerçant peut supprimer son propre compte. Action **irréversible**, aucun
test. **Traité** par `test-commercant-autosuppression`, en priorité 3.

</details>

### T5 — La carte client n'était pas couverte

`GET /promo/map` porte deux nombres explicites — **300 commerces**, **180
req/min** — et c'est la fonctionnalité client la plus récente. `GET /commune`
non plus, alors qu'elle porte le piège de pagination de la règle 15.
**Traité** par `test-client-carte` et `test-client-commune`.

### T6 — L'onboarding n'était couvert par rien

4 écrans (splash, choix de rôle, localisation ×2), premier contact, et ils
conditionnent l'accès à tout le reste. **Traité** dans l'étape 3.

### T7 — Trois profils sur quatre n'avaient aucun parcours écran

Le seul prévu était commerçant. **Traité** : un parcours minimal par profil,
plus l'onboarding (§6 étape 3).

> ⚠️ **T1-T7 sont « traités dans le plan », pas résolus.** Aucun de ces bancs
> n'est écrit. Ils ne se ferment qu'une fois le banc écrit **et prouvé par
> mutation**.

---

## Arbitrages en attente

### A1 — Corriger P1 impose de modifier des fichiers existants

**La tension.** La règle de travail posée le 2026-08-04 est **« on ajoute, on ne
modifie pas »**, pour éviter les conflits de merge entre branches et entre les
deux clones (Windows / WSL). Or corriger P1 demande d'éditer trois fichiers
existants.

**Ce qui est réellement en jeu** : 5 lignes ajoutées dans chacun des 3 fichiers,
sans reformatage, sans toucher aux entrées existantes. Le risque de conflit est
faible — un conflit ne surviendrait que si une autre branche ajoutait des
entrées **au même endroit** de la même table.

**En attente de décision.** Trois issues possibles : corriger dans un commit
isolé et minimal ; attendre un moment où aucune autre branche ne touche ces
fichiers ; ou laisser P1 ouvert et documenté jusqu'à un lot i18n dédié.

> **Le cas général vaut d'être tranché une fois** : certains ajouts ne peuvent
> pas être 100 % additifs — brancher un module NestJS suppose une ligne dans
> `app.module.ts`, un écran une entrée dans `router.dart`, un `ErrorCode` une
> ligne dans 3 mappings. La règle a besoin d'une clause pour ces cas, sinon elle
> s'applique mal ou pas du tout.

### A2 — Ordre d'attaque du plan de test

`docs/TEST_PROMO.md` §9 propose : corriger P1 → étape 2 → étape 1 → étape 3 →
étape 4. L'étape 2 avant l'étape 1 parce qu'elle est statique, instantanée, sans
base ni émulateur — et qu'elle a **déjà trouvé un défaut réel**.

**En attente de confirmation.**

---

## Avancement du plan de test

Le détail de chaque étape, avec son critère de sortie, est dans
`docs/TEST_PROMO.md` §6.

| Étape | Objet | État |
|---|---|---|
| — | Méthode générique + 5 squelettes | ✅ écrits, auto-tests au vert (16/16 et 13/13) |
| — | Plan spécifique Promo | ✅ écrit |
| **1** | Banc de refus (48 routes, par construction) | ✅ **PASSÉ** — 138 sondes, 0 échec, décor posé, **prouvé par mutation sur les deux phases** |
| **2** | Vérificateurs de synchronisation | ✅ **CLOSE** — 3 vérificateurs, **10 couples sur 10**, **14 mutations sur 14 refusées**. Une commande : `dart run tool/check_all.dart` |
| **3** | Décor + 4 parcours écran + onboarding | 🔶 **décor fait**, parcours écran non commencés |
| **4** | Bancs, couverture d'usage complète (**27 bancs, 62/62 routes**) | 🔶 **4 bancs sur 27** écrits et éprouvés |

**Couverture actuelle**, décomposée (`docs/TEST_PROMO.md` §4) — trois
couvertures distinctes, trois cibles :

| Couverture | État | Cible |
|---|---|---|
| **Accès** (qui a le droit d'appeler quoi) | ✅ **62 / 62** — 48 sondées, 14 ouvertes épinglées | **100 %** atteint |
| **Appartenance** (la ressource est-elle à vous) | ✅ **14 / 14** routes à identifiant | 14 |
| **Usage** (chaque route appelée au moins une fois) | ~20 / 62 | **100 %** — bornée à 62 routes |
| **Comportement** (chaque règle fait ce qu'elle doit) | **3 / 8** règles chiffrées | **piloté par le risque** — non bornée |
| Couples serveur ↔ app | ✅ **10 / 10** — tous éprouvés par mutation | 10 |
| Écrans | 0 / 34 | 33 (`dev_profile_switcher` exclu, outil de développement) |

### Ce qui existe, et comment le rejouer

Tout est dans `scripts/`. Chaque banc lance son auto-test avant de conclure, et
**tous ont été prouvés par mutation** — le vert seul n'a jamais suffi.

| Script | Ce qu'il fait | Verdict au 2026-08-04 |
|---|---|---|
| `provision-decor.sh` | pose admin, 2 agents (communes disjointes), commerçant, promo — et **imprime le bloc `export`** | — |
| `seed-demo.sh` | peuple pour *regarder* l'app : 10 commerces, 44 promos, 3 mises en avant, modération à deux états | — |
| `test-frontiere-http.sh` | 48 routes × 3 sondes de refus | ✅ 138 sondes, 0 échec |
| `test-appartenance.sh` | 14 routes à identifiant, agent d'une autre commune | ✅ 14 sondes, 0 échec |
| `test-plafond-promos.sh` | 5 actives sous course, plusieurs tours | ✅ 5/5 tours, 1 gagnant chacun |
| `test-cycle-commercant.sh` | suspension ≠ suppression | 🔴 **7 ✅ / 1 ❌ — voir P10** |
| `apps/mobile/tool/check_all.dart` | les 3 vérificateurs statiques | ✅ 3/3 |

```bash
# WSL, backend démarré
./scripts/provision-decor.sh      # coller le bloc export imprimé
./scripts/test-frontiere-http.sh  # ~3 min · --only=<motif> pour une seule route
./scripts/test-appartenance.sh
./scripts/test-plafond-promos.sh  # TOURS=5 SIMULTANEES=4
./scripts/test-cycle-commercant.sh
```

⚠️ **Attendre une minute entre deux bancs** : connexions et inscriptions sont
plafonnées à 5/min/IP, et un 429 se déguise en « identifiants incorrects ».

~~⚠️ **`test-cycle-commercant.sh` sort en échec, légitimement**, sur P10.~~
**Périmé — P10 est corrigé.** `CommercantService.login` passe par
`findVivantByTelephone`, qui filtre `deletedAt IS NULL`
(`commercant.service.ts:148`), et `assertPhoneAvailable` emprunte la **même
méthode** : l'invariant est tenu par du code partagé, plus par un commentaire.
Ce banc doit être rejoué pour confirmer qu'il repasse au vert.

### Par où reprendre

1. **Rejouer les cinq bancs** — la revue multi-agents du 2026-08-05 a modifié
   des chemins qu'ils traversent (visibilité des promos, plafond de 5, file de
   modération, décor), **et changé le contrat sur trois points** : `POST /promo`
   reçoit `dureeJours`, `GET /notifications` rend `promoDescription` au lieu
   d'une phrase, `GET /promo/me/slots` est neuf. Rien n'a été exécuté depuis :
   c'est le premier geste. Trois vérifications rapides à faire au passage —
   `migration:generate` à sec (le diff destructeur sur `Notification` doit avoir
   disparu), `strings base.apk` (quels binaires portent encore les identifiants
   admin), et `countPendingModeration` qui doit rendre **2** là où il rendait 6.
2. **Trancher P9** (séparation S3 dans `.env.example`) et **P7** (les replis
   silencieux des miroirs). ~~**P8** (les comparaisons littérales)~~ — sans
   objet, mesuré à zéro le 2026-08-05.
3. **Étape 3** — les parcours écran. La base est désormais assez peuplée pour
   qu'ils aient quelque chose à montrer, et `harness.dart` attend dans
   `docs/methode-test/`.
4. **Étape 4** — les 23 bancs restants, matrice complète en `TEST_PROMO.md` §6.
   Les plus rentables d'abord : `test-admin-highlight` (livré fin juillet,
   jamais éprouvé) et `test-notifications` (module entier sans couverture).

---

## Journal

### 2026-08-05 (suite) — Le plafond de 5 sort du binaire, et un piège de configuration

**La question posée** : « le plafond de 5 promos est figé dans l'app, si je le
change demain je dois recompiler ?». Inventaire fait — la réponse était *à
moitié*, et la moitié restante était pire que prévu.

**Ce qui allait déjà.** `GET /promo/me/slots` sert `plafond` depuis la revue de
la veille : le **calcul** (`auPlafond`, `restants`, les barres d'emplacements)
suivait donc le serveur.

**Ce qui n'allait pas.** Le chiffre était écrit en toutes lettres dans les trois
`.arb` — `« Plafond de 5 promos atteint »`, `« {count} / 5 promos actives »`.
Le calcul suivait le serveur, le **texte** non : passer le plafond à 8 aurait
autorisé 8 publications en affichant « 7 / 5 ». Corrigé par un placeholder
`{plafond}` alimenté par `slots.plafond` (règle 32, amendée).
Au passage, `my_promos_screen` gardait les replis `?? 0` que `_QuotaCard` avait
déjà écartés : il annonçait « 0 / 5 » et cinq barres vides — des emplacements
libres — quand `slots` n'avait pas répondu. Le décompte n'est plus affiché du
tout tant que la mesure manque (règle 29).

**Côté serveur**, `MAX_PROMOS_ACTIVES` était le seul de sa famille à exiger un
redéploiement, alors que ses quatre voisines immédiates (durées, plafond
quotidien, cooldown) se règlent par variable d'environnement. Devenu
`PROMO_ACTIVE_CAP`.

**Le piège découvert en chemin, et c'est le vrai butin.**
`configService.get<number>('CLE', 5)` **ne convertit rien** : le `<number>` est
une assertion TypeScript, effacée à la compilation — le même piège que le
`@Body` typé en ligne, transposé à la configuration. `ConfigModule` est monté
sans conversion, donc les cinq lectures numériques de `PromoService` recevaient
`'5'`, `'7'`, `'30'`… depuis `.env`. Invisible parce que tous les usages étaient
arithmétiques et que JavaScript coerce. Le masque serait tombé exactement sur
le changement du jour : `plafond` **sort en JSON**, et `{"plafond":"5"}` fait
planter le `as int` du mobile. Toutes les lectures passent désormais par
`configNumber`, qui vérifie le type avant `Number()` — celui-ci acceptant
`true` (→ 1), `[5]` (→ 5) et `''` (→ 0), il ne peut pas servir de garde.

**Ce qui le tient** : `config-number.spec.ts`, 10 cas dont 6 refus ;
`check_server_rules.dart` mis à jour pour lire la nouvelle forme d'appel, avec
un cas d'auto-test qui **refuse explicitement l'ancienne** (22 cas, 11 refus) ;
et une mutation réelle de `promoMaxDureeJours` (7 → 9) vérifiée : `exit=1`,
« serveur 7, app [9] ».

**Vérifications** : `flutter analyze` 0 · `flutter test` 14 · `check_all` 4/4 ·
`dart format` 0 · `tsc` propre · `npx jest` **43 tests** (33 avant). Les 13
erreurs eslint et la suite `highlight.service.spec.ts` qui ne charge pas restent
les défauts préexistants de `node_modules` sous Windows (`sharp`,
`@aws-sdk/s3-request-presigner`, `compression`).

**Ce qui n'est pas fait, et c'est délibéré** — le reste de l'inventaire des
valeurs recopiées, chiffré mais non traité :
- `maxPhotos = 3` (`multi_photo_picker_field.dart`) ↔ `@ArrayMaxSize(3)` :
  recopié, tenu par rien ;
- `_pageSize = 100` (`admin_api`, `commune_api`, `promo_api`) ↔ `MAX_PAGE_SIZE` :
  **couplage dur, pas une divergence** — baisser `MAX_PAGE_SIZE` ferait partir
  chaque appel de liste en `400`. Le remède n'est pas de descendre la borne
  jusqu'à l'app mais qu'elle cesse de demander le maximum autorisé ;
- un `GET /config/client` pour ce qui doit être connu *avant* la requête
  (longueurs de champ, nombre de photos, motif de PIN) — à trancher après le
  rejeu des bancs, pas avant.

Faussement suspectes, à ne pas recompter : `maxLength: 12` sur les téléphones
(le serveur valide par `@IsPhoneNumber('DZ')`, ce n'est pas une copie) et
`_targetBytes = 250 Ko` vs `MAX_UPLOAD_BYTES = 500 Ko` (volontairement
différents, documentés).

**⛔ ACTION HORS DÉPÔT, NON FAITE — `PROMO_ACTIVE_CAP` dans le `.env` de WSL.**
La clé n'existe que dans les deux `.env.example`, qui ne sont lus par aucun
processus. Le `.env` réel vit dans `~/projects/echangopromo` et n'est pas
versionné : **le plafond n'est réglable dans aucun environnement tant que
personne ne l'y ajoute à la main.** Le backend tourne quand même (repli sur 5),
et c'est bien ça le problème — on croira le réglage cassé en le changeant,
alors qu'il n'aura jamais été branché. Devenu la **règle 36** de CLAUDE.md.

Le repli est désormais **journalisé au démarrage** (« PROMO_ACTIVE_CAP absente
de la configuration — valeur retenue : 5 »), une fois par clé et non par
requête : sans ça, une clé absente reste indiscernable d'une clé présente
valant exactement le défaut. Éprouvé — `config-number.spec.ts` monte à 16 cas,
et la mutation qui rend ce repli silencieux fait tomber 3 tests.

---

### 2026-08-05 — Revue multi-agents par spécialité, et ses correctifs

**La revue.** Six spécialistes (sécurité, architecture, métier, mobile, qualité,
contrat d'erreur) sur le code à HEAD, chaque lot passé à un sceptique chargé de
le **réfuter**. 34 constats, **34 retenus** — taux de survie de 100 %, qui est
en soi un signal : au moins un faux positif a traversé la réfutation (voir plus
bas). Synthèse complète : `docs/REVUE_MULTIAGENTS_2026-08-05.md`.

**Le faux positif, et ce qu'il enseigne.** Un constat affirmait « `@Param('id')`
non-UUID → 500, 0 `ParseUUIDPipe` dans tout le backend ». Faux : `UuidParam`
existe (`common/decorators/uuid-param.decorator.ts`), est appliqué à la ligne
citée, et sa doc référence un pentest du 2026-08-05. Le sceptique l'a confirmé
sans ouvrir le fichier. **Une preuve citée n'est pas une preuve vérifiée** — les
correctifs n'ont été écrits qu'après relecture de chaque fichier visé.

**Corrigé (22 constats).** Deux critiques : les clés S3 venues du client sont
désormais rattachées à leur uploadeur (`StorageService.assertKeyOwnedBy`,
branchée dans `PromoService.create`/`update` et `CommercantService.updateProfile`
— la suppression croisée d'objets d'un tiers était ouverte à tout commerçant
inscrit) ; les identifiants du pilote ne sont plus des littéraux Dart et
`/dev/profiles` n'est plus construite hors `kDebugMode`. **Le mot de passe
`superadmin` reste à faire tourner côté serveur** : retirer le code ne rappelle
pas les APK déjà installés.

Trois causes racines traitées d'un geste : `applyVisibleConditions` devient
l'unique définition de « promo visible » (elle vivait en cinq exemplaires, dont
une à une condition sur cinq sur la route publique de lien partagé) ;
`aliveAccountWhere` réunit les quatre compteurs de dashboard (le bug de
`countActive` corrigé le 2026-07-14 subsistait sur les trois autres) ; les cinq
outils qui « rassuraient » savent maintenant refuser.

**Les outils, éprouvés par mutation** — c'est le seul verdict qui compte :
`check_enums` couvre `NotificationType` (9 couples, refus prouvé) ;
`check_error_codes` exige les codes client-seuls (retirer `NETWORK_ERROR` de
l'arabe échoue désormais, contre « ✅ accord complet » avant) ;
`check_server_rules` sait lire un défaut de configuration et une constante
serveur, refuse les motifs ambigus (l'interversion titre/sous-titre est
attrapée) ; `appartenance.py` distingue « ne le voit pas » de « on n'a rien
reçu » (23 cas, 16 refus) ; `provision-decor.sh` et `seed-demo.sh` n'avalent
plus l'échec.

**Les trois changements de contrat, faits ensuite.** Ils demandaient de modifier
ce qui circule entre l'app et le serveur, pas seulement de corriger du code :

- **Les notifications sont localisées.** Le serveur n'envoie plus une phrase
  française mais le couple (`type`, `promoDescription`) — extrait explicitement
  de `metadata`, qui reste `@Exclude()` ; `notificationLabel` compose la phrase
  côté app, 7 clés × 3 `.arb`. Le `message` serveur ne sert plus que de dernier
  recours, pour un type que le miroir Dart ne connaît pas encore. Le `switch`
  Dart étant exhaustif, **le compilateur tient la couverture** : un type ajouté
  sans libellé ne compile pas.
- **Le décompte d'emplacements vient du serveur** (`GET /promo/me/slots`, posé
  sur `PromoController` — `CommercantController` n'injecte pas `PromoService` et
  l'y injecter fermerait un cycle de modules). `kMaxPromosActives = 5` et
  `countActivePromos` sont supprimés : le plafond voyage avec la mesure. Tant
  qu'elle n'est pas là, **rien n'est affiché** — un « 0 / 5 » de repli
  annoncerait des emplacements libres sans rien en savoir.
- **L'app envoie une durée, plus une date.** `dureeJours` remplace la `dateFin`
  absolue calculée sur l'horloge du téléphone : le calcul se fait sur l'horloge
  qui valide. `dateFin` reste accepté côté serveur pour les clients déjà
  installés, marqué historique dans le DTO, `dureeJours` l'emportant quand les
  deux arrivent.

**Reste ouvert : les angles morts.** Rien n'a été exécuté — voir « Par où
reprendre ».

**Vérifié.** `flutter analyze` 0, `flutter test` 14 verts, `dart format` 0
différence, `check_all.dart` 4/4, `tsc` backend propre, `eslint` sans erreur
imputable. `npx jest` : 21 tests verts sur 4 suites — la 5ᵉ ne charge pas,
`@aws-sdk/s3-request-presigner` et `sharp` étant absents du `node_modules`
**Windows** (le backend tourne depuis WSL). **Aucun banc de bout en bout n'a été
rejoué** : la revue est statique, les correctifs ne le sont pas.

### 2026-08-04 — Reprise, mise à niveau et outillage de test

**Synchronisation.** Le dépôt local (Windows) et le clone WSL étaient tous deux
en retard : HEAD au 2026-07-14 côté Windows, au 2026-07-06 côté WSL. `main`
contenait déjà tout, plus la PR #13 mergée le jour même. Les 18 fichiers
modifiés non commités du clone WSL se sont révélés être **du reformatage
Prettier pur** (vérifié en neutralisant espaces et virgules : zéro changement de
logique) — écartés sans perte. Les deux clones sont désormais sur
`claude/echango-promo-suite-2026-08-04`, poussée sur `origin`.

**Backend remis en service.** `npm install`, puis un mois de migrations en
retard appliquées — dont `CreateHighlight` (table du bandeau, contraintes et
index) et `AddCategorieRestauration` (7ᵉ valeur d'enum sur `commercant` et
`promo`). Démarre sans erreur, répond 200 sur `/commune`, `/promo`, `/promo/map`,
`/highlight`.

**Mobile compilé pour la première fois.** `flutter pub get` + `flutter analyze`
sur Flutter 3.35.7 → **1 seul avertissement** sur tout le projet. Le build
Android a d'abord échoué sur `PKIX path building failed` : **l'analyse HTTPS
d'AVG** réémet les certificats avec sa propre autorité racine, présente dans le
magasin Windows mais absente du truststore Java. Débloqué en désactivant
l'analyse HTTPS le temps du build.

**⚠️ Le piège qui a coûté le plus, et qui doit être connu.** L'app a d'abord
tourné **contre la production** alors qu'elle était censée viser le backend
local. Cause : `flutter run` lancé via `Start-Process` (PowerShell), qui perd
silencieusement le `--dart-define` — le build part alors avec la valeur par
défaut de `Env.apiBaseUrl`, c'est-à-dire `https://promo.echango.com`. Aucune
erreur, aucun message : l'app fonctionne parfaitement, sur les mauvaises
données. Diagnostiqué en capturant le trafic TCP de l'émulateur (0 connexion
vers `10.0.2.2:3000`, 57 vers l'IP du VPS), puis confirmé en cherchant la chaîne
dans le `kernel_blob.bin` de l'APK installé. **Appeler `flutter` directement**,
et vérifier le kernel en cas de doute (`docs/TEST_PROMO.md` §7).

**Méthode de test.** Étude du dépôt `echango-delivery` (26 bancs de scénarios,
3 fichiers de parcours écran, 6 vérificateurs statiques), puis extraction en
`docs/METHODE_TEST.md` — 11 modes de défaillance, un lexique, un ordre
d'adoption, cinq squelettes exécutables dans `docs/methode-test/`. Instancié sur
ce produit dans `docs/TEST_PROMO.md`.

**Les squelettes ont trouvé leurs propres défauts, et c'est le point.** Trois
défauts dans mon propre code de vérification, **aucun repéré à la relecture** :
un enum sur une seule ligne dont seul le premier membre était lu ; un décorateur
en commentaire compté comme une vraie route ; et surtout un analyseur qui
cherchait `@UseGuards` **après** `@Controller` alors que l'ordre NestJS habituel
le place avant — six routes d'administration annoncées « ouvertes » alors
qu'elles étaient gardées trois lignes plus haut. Ce dernier n'a été trouvé qu'en
faisant tourner l'outil sur le dépôt réel. Les trois sont désormais des cas
d'auto-test.

**Résultats de la première passe** : 62 routes, 14 ouvertes — toutes légitimes,
**aucun garde manquant**. Et P1, ci-dessus.

### 2026-08-04 (suite) — Étape 2, premier vérificateur en place et éprouvé

`apps/mobile/tool/check_error_codes.dart` compare le registre serveur
(42 codes) aux trois tables de traduction. Auto-test **14/14, dont 7 refus** ;
et surtout **5 mutations des vrais fichiers, 5 refus** :

| Mutation | Attendu | Obtenu |
|---|---|---|
| membre bidon ajouté à l'enum serveur | 3 manques | ✅ |
| clé retirée d'**une seule** table | 1 manque | ✅ |
| doublon dans une table | 1 doublon | ✅ |
| clé inconnue du serveur | 1 « en trop » | ✅ |
| table renommée (`_ar` → `_arabe`) | **échec sur source introuvable** | ✅ sortie 2 |

La cinquième est la plus importante : un contrôle qui **conclut à l'accord**
quand il ne trouve pas sa source est le mode de panne le plus dangereux de
cette famille.

> ⚠️ **Une leçon d'exploitation, apprise en se brûlant.** Le lanceur de
> mutations restaure par `git checkout -- .`, ce qui **balaie aussi le travail
> non commité**. Lancé sur un arbre sale, il a effacé les trois traductions qui
> venaient d'être écrites. L'ordre est donc : **committer d'abord, muter
> ensuite** — et un lanceur de mutations devrait refuser de démarrer sur un
> arbre sale, ou ne restaurer que les fichiers qu'il a lui-même touchés.

**Ce que ce vérificateur a coûté en confiance, et pourquoi c'est instructif.**
Sa première version a produit un faux positif à quatre entrées (voir P1) parce
que les exclusions volontaires vivaient dans un commentaire. Un contrôle qui
accuse à tort se paie plus cher qu'un contrôle absent : c'est ainsi qu'ils
finissent désactivés. La correction n'a pas été de désactiver le contrôle mais
de **déplacer la liste d'exclusions du commentaire vers la donnée**, avec
obligation de justification — l'auto-test refuse une exclusion sans raison.

### 2026-08-04 (fin) — Étape 2 quasi close, deux constats de conception

`tool/check_enums.dart` tient les **8 enums miroirs**, 29 valeurs, comparés sur
la **valeur réseau** et non sur le nom du membre — les deux langages nomment
différemment (`VETEMENTS_TEXTILE` / `vetementsTextile`). Tous d'accord.

Auto-test 11 cas dont 6 refus, et **4 mutations sur 4 refusées** : valeur
ajoutée côté serveur, valeur retirée du miroir, valeur changée d'un seul côté,
fichier de miroir renommé (→ sortie 2, jamais « tout est d'accord »).

**Le piège d'extraction, qui est devenu un cas d'auto-test** : le corps d'un
enum Dart amélioré s'arrête au premier `;`. Au-delà vivent le constructeur, les
champs et les méthodes — sans cette borne, les chaînes de `fromValue` seraient
comptées comme des valeurs d'énumération.

**Le lanceur de mutations refuse désormais de démarrer sur un arbre sale**, et
ne restaure que les fichiers qu'il a touchés — correction directe de la leçon
apprise plus haut dans la journée.

Deux constats sont sortis du contrôle sans qu'on les cherche : **P7** (cinq
miroirs avalent une valeur inconnue) et **P8** (la règle 19 est contournée dans
les écrans). Aucun des deux n'est traité : ce sont des décisions, pas des
corrections évidentes.

### 2026-08-04 (clôture) — Étape 2 terminée

`tool/check_server_rules.dart` tient les **6 bornes numériques** et **2 motifs
réguliers** que l'application recopie du serveur : description de promo (140),
titre et sous-titre de mise en avant (60/100), mot de passe agent (8, dans
3 écrans), et les deux motifs de PIN (`^\d{6,12}$` pour le fixer,
`^\d{4,12}$` pour le vérifier). Tous d'accord.

**Choix de conception** : il lit les **vrais** fichiers des deux côtés, sans
fichier de constantes intermédiaire. Un tel fichier, que les écrans
n'utiliseraient pas, aurait donné une fausse impression de couverture — c'est
le défaut « le serveur savait, l'app ignorait » appliqué à nos propres outils.

**Il a refusé de conclure au premier essai**, sur un chemin de DTO erroné de ma
part (`admin/dto` au lieu de `agent/dto`) : il a dit « introuvable » plutôt
qu'annoncer l'accord sur les bornes qu'il avait pu lire. C'est exactement le
comportement voulu, obtenu sans l'avoir cherché.

`tool/check_all.dart` donne le point d'entrée unique qui manquait : les trois
vérificateurs, auto-test d'abord, sans arrêt au premier échec. L'étage 1 est
donc le seul lot qui pourrait tourner à chaque commit — statique, instantané,
sans base ni émulateur.

**Bilan de l'étape 2** : 3 vérificateurs, **10 couples sur 10** tenus par un
contrôle exécuté (contre 0 le matin même), et **14 mutations des vrais fichiers,
14 refus**.

### 2026-08-04 (soir) — Étape 1, le banc de refus est écrit

`scripts/lib/frontiere_http.py` + son lanceur. 62 routes énumérées depuis la
source, 14 ouvertes épinglées avec leur justification, 48 protégées.

**Ce qui est déjà prouvé, et sans un seul identifiant.** La vérification de
l'épinglage s'exécute **avant le premier appel réseau** — c'est elle qui
attrape un garde oublié, donc la propriété la plus importante du banc dans un
projet où la protection est posée route par route. Quatre mutations, quatre
comportements attendus : garde retiré d'un contrôleur → refus immédiat avec les
5 routes nommées ; route ouverte devenue protégée → avertissement ; source
introuvable → sortie 2 sans verdict ; arbre propre → passe l'épinglage et
s'arrête faute d'identifiants.

**Ce qui bloque la phase réseau, et ce n'est pas du code** : la base locale a
1 admin, 1 commerçant et **0 agent**. Les ~140 sondes attendent que l'étape 3
pose ces comptes. Le banc le dit et s'arrête plutôt que de conclure sur ce
qu'il a pu lire.

**Trois pièges d'analyse rencontrés**, tous devenus des cas d'auto-test : les
décorateurs forment un bloc contigu **autour** de la méthode (`@Roles` peut
suivre `@Get`, et ne lire que ce qui précède décale les rôles d'une route) ;
l'en-tête de classe ne commence pas au `@Controller` ; les paramètres d'URL
doivent être remplacés par un identifiant **bien formé**, sinon on mesure la
validation du format et un 400 passe pour un refus.

**Deux limites nommées plutôt que tues** : la sonde « mauvais rôle » est
impossible sur les routes ouvertes aux 3 rôles (notifications) — comptée non
applicable ; les 3 routes App Links sont host-scopées et répondent 404 sur
localhost par conception.

Aucune modification du code source : les mutations sont transitoires et
restaurées dans la seconde, `git status` vide après coup.

### 2026-08-04 (nuit) — Étape 1 passée, la frontière tient

Décor posé de zéro par `scripts/provision-decor.sh` : admin aux identifiants
connus, agent rattaché à **Ain Chouhada** (il n'y en avait aucun en base),
commerçant actif au registre validé.

**Banc de refus : 138 sondes, 0 échec.** Les 48 routes protégées refusent les
trois sondes — sans jeton, avec le jeton d'un rôle qui n'y a pas droit, avec un
jeton révoqué — chacune avec le bon statut **et** le bon code.

**La preuve par mutation, sur les deux phases.** Le vert ne prouve rien seul :

- *épinglage* (avant le réseau) : garde retiré → refus immédiat ; route ouverte
  devenue protégée → avertissement ; source introuvable → sortie 2 ;
- *réseau* : `@Roles('admin')` retiré des routes `/admin/highlight` → **un jeton
  commerçant obtenait `GET /admin/highlight` en 200**. Le banc l'a vu sur les
  cinq routes, puis est repassé au vert après restauration.

**Deux défauts trouvés dans mes propres scripts, tous deux de la même famille**
— une donnée mal câblée ne casse pas, elle disparaît :

- le jeton se nomme `accessToken`, pas `token`. La connexion réussissait en
  HTTP 201, le jeton ressortait vide, et le décor concluait « connexion
  impossible » : le message accusait les identifiants pour un contrat de
  réponse mal lu ;
- le lanceur ne transmettait pas `"$@"` : `--only` et `--list` étaient avalés,
  et la commande documentée ne faisait pas ce qu'elle annonçait, en silence.

**Un garde-fou corrigé** : le lanceur de mutations refusait de démarrer à cause
d'un `..env.production.swp` non suivi. Or la restauration (`git checkout --
<fichier>`) ne peut atteindre que des fichiers **suivis** : le contrôle porte
désormais sur `--untracked-files=no`. Un garde-fou trop large devient pénible,
donc contourné.

⚠️ **Ce fichier d'échange vim traîne toujours** dans le clone WSL (voir P6).

### 2026-08-04 (fin de nuit) — Appartenance : T1 fermé, P5 fermé

`scripts/test-appartenance.sh` — **14 sondes, 0 échec, 0 non concluante**. Les
14 routes à identifiant accessibles à un agent rendent toutes
`403 COMMERCANT_NOT_IN_AGENT_COMMUNES` face à un agent d'une autre commune.
La faille critique de l'audit V0 est enfin rejouée, sur une surface sept fois
plus large que celle qui avait été corrigée.

**Le piège central, mesuré avant d'écrire les assertions.** Avec un corps vide,
deux routes rendent `400 VALIDATION_ERROR` : la requête meurt à la validation,
**avant** le contrôle d'appartenance. Compter ce 400 comme un refus aurait fait
conclure juste **par accident** — et resterait vert le jour où l'appartenance
disparaît. Les sondes envoient donc un corps valide, et un `VALIDATION_ERROR`
est déclaré **non concluant**, jamais réussi.

**Prouvé par mutation** : condition de `assertAgentOwnsCommercant`
(`commercant.service.ts:529`, passage unique des 14 routes) neutralisée →
l'agent intrus obtenait **201** sur une action de modération. Retour au vert
après restauration.

⚠️ **Sous mutation, le filtre de liste tenait toujours.** Le contrôle par route
et le filtrage de liste sont **deux mécanismes indépendants** : un banc qui ne
testerait que la liste conclurait à tort. Les deux sont désormais couverts.

**Quatre défauts trouvés dans le décor, tous du même repli complaisant** — et
c'est la répétition qui est instructive :

| ce que j'avais écrit | ce que ça a produit |
|---|---|
| `\|\| true` sur la validation du registre | « registre validé » annoncé sur un refus, échec 3 étapes plus loin |
| un argument en trop dans l'appel | `AUTH_TOKEN_MISSING` sur une requête authentifiée dans l'intention |
| `limit=200` au-delà du plafond | 400 avalé par `(.items // .)`, jq plantant loin de la cause |
| `dateFin` à +20 jours | `PROMO_DATE_FIN_EXCEEDS_MAX` (plafond réel : 7 jours) |

Aucun n'a levé au bon endroit. C'est exactement ce que la méthode reproche aux
valeurs par défaut, appliqué à des expressions `jq` et à des arguments de
fonction — **le pire endroit pour un repli reste un script de décor**.

### 2026-08-04 (fin) — Concurrence prouvée, base peuplée

**Banc de concurrence** : `test-plafond-promos.sh`, 5 tours × 4 créations
simultanées, **1 seul gagnant à chaque tour**. Prouvé par mutation — verrou
rendu non sérialisant → **4 créations sur 4 réussissent**. Voir P4.

**`scripts/seed-demo.sh`** peuple la base pour qu'on puisse *regarder*
l'application, là où `provision-decor.sh` ne pose que le minimum des bancs.
Les deux sont séparés : un banc doit tourner sur un décor prévisible, pas sur
vingt promos de démonstration.

État après peuplement :

| | |
|---|---|
| Commerces actifs | **10** — 4 communes, 7 catégories |
| Promos publiées | **44** |
| Mises en avant | **3** |
| Modération | 1 promo masquée (3 signalements), 1 à 2 signalements |
| Carte | 8 commerces géolocalisés, `truncated: false` |

**Tout passe par l'agent**, et c'est ce qui rend le script praticable : un
commerçant créé par un agent est `confirme_agent` — il échappe à la garde du
registre — et l'agent est un `trustedActor` exempté des plafonds anti-abus. Par
l'inscription directe, il aurait fallu deux gestes admin et une connexion par
commerçant, contre un plafond de 5 connexions par minute.

**Deux défauts de ma part, tous deux du même genre que ceux déjà consignés :**

- **la cadence.** Toutes les écritures partagent un seau de 20/min ; à 0,3 s
  d'intervalle le peuplement mourait sur `RATE_LIMITED`. L'enrobage `ecrire`
  nomme désormais le 429 et patiente, au lieu de le confondre avec un refus
  métier ;
- **la file de modération restait vide.** Je posais deux signalements « pour la
  peupler », alors que le seuil est à **3** et que la file n'affiche que ce qui
  l'a atteint. Le tableau de bord le disait — `signalementsEnAttente: 0` — sans
  que je l'écoute. Les deux états sont désormais posés, parce que les deux
  existent en production. **Un décor qui n'illustre pas ce qu'il prétend
  illustrer est un décor qui rassure.**

### 2026-08-04 (très tard) — Cycle de vie : un défaut réel trouvé

`test-cycle-commercant.sh` éprouve la distinction suspension ≠ suppression. Le
vrai discriminant est le **numéro de téléphone** : c'est la seule différence
observable de l'extérieur, et celle qui casse en silence.

**7 contrôles au vert**, puis un huitième ajouté en cours de route qui a trouvé
**P10** : un numéro libéré par une suppression est bien réattribuable, mais son
repreneur **ne peut jamais se connecter**.

**Prouvé par mutation** : suspension et suppression confondues (`suspend` posant
aussi `deletedAt`) → le banc voit le numéro réattribué après une simple
suspension, et la cascade qui suit (l'usurpateur ayant pris le numéro, la
suppression n'a plus rien à libérer).

**Trois défauts dans mes propres outils, tous de la même famille — et c'est
cette répétition qui est l'enseignement du jour :**

| ce que j'ai écrit | ce que ça a produit |
|---|---|
| `if jeton:` autour d'un contrôle | le contrôle disparaissait du rapport, total de 7 à 6 sans explication |
| reproduction lisant `.id` sur une réponse qui rend `{accessToken}` | suppression d'un identifiant vide, puis **« ✅ pas de défaut »** sur un scénario qui n'avait pas eu lieu |
| harnais de mutation jugeant sur le code de sortie | « ✅ » sur un `INTERNAL_ERROR` qui ne prouvait rien |

Les trois **rassuraient**. Aucun ne levait. C'est exactement ce que la méthode
reproche aux replis, appliqué cette fois à mes propres vérifications : **un
contrôle qui ne peut pas dire non finit par dire oui à tort**.

### 2026-08-04 — Clôture de la session, mise en pause du chantier de test

**Ce qui existe** : 4 bancs écrits, éprouvés par mutation et rejouables ; 3
vérificateurs statiques derrière une commande unique ; un décor et un
peuplement. Le tableau « Ce qui existe, et comment le rejouer » ci-dessus donne
les commandes.

**Ce que ça a rapporté** — quatre points fermés (P1 revu, P4, P5, T1) et **trois
défauts réels trouvés**, dont un critique :

| | |
|---|---|
| **P10** 🔴 | un numéro recyclé enferme son repreneur dehors — correctif d'une ligne proposé, **non appliqué** |
| **P9** | `S3_ENDPOINT` sert deux rôles ; création de promo à 300 s, contournée en local (→ 88 ms) |
| `HIGHLIGHT_CAP_REACHED` | non traduit — **corrigé** |

**Ce qui n'a pas été fait, et pourquoi c'est écrit** : les parcours écran
(étape 3), 23 bancs sur 27 (étape 4), et la vérification de l'auto-suppression
(T4). Aucun n'est bloqué — ils n'ont simplement pas été atteints.

**Le fil rouge de la journée, pour qui reprendra** : la moitié des défauts
trouvés étaient dans **mes propres outils**, et tous **rassuraient** au lieu de
lever — un contrôle silencieusement sauté, une reproduction concluant « pas de
défaut » sur un scénario qui n'avait pas eu lieu, un harnais jugeant sur un code
de sortie, quatre replis `jq` avalant des erreurs. C'est la démonstration
pratique de la règle qui fonde la méthode : **un contrôle qui ne peut pas dire
non finit par dire oui à tort.** Prouver chaque banc par mutation n'est pas une
formalité — c'est ce qui a rattrapé chacun de ces cas.

⚠️ **Chantier mis en pause à la demande de l'utilisateur**, pour passer à autre
chose. Rien n'est en cours : arbre propre, tout poussé, `test-cycle-commercant`
rouge sur un vrai défaut et non sur un travail inachevé.

---

## Audit de conformité aux 35 règles — 2026-08-04/05

**Méthode** : 4 vérificateurs statiques, 2 bancs, et 14 mesures ciblées. Tout ce
qui suit est **mesuré**, pas lu.

**Résultat : 26 règles conformes, 5 écarts — tous corrigés.**

| Écart | Correction |
|---|---|
| **P10** — `login` sans filtre `deletedAt` 🔴 | `findVivantByTelephone`, **un seul endroit** au lieu du filtre recopié. Banc de cycle de vie : 8/8 |
| **R31** — `POST /admin/me/revoke-token` sans appelant | menu compte du tableau de bord admin, avec déconnexion enchaînée. Audit R31 : ne restent que les 3 App Links |
| **R35** — `Colors.redAccent` | champ `favorite` dans `AppSemanticColors`, variante sombre incluse |
| **P7** — 5 replis silencieux | helper `fromApiValue` : le repli **reste** mais se signale en développement |
| **P8** — comparaisons littérales | **ne se reproduit pas** — voir ci-dessous |

### ⚠️ P8 était une fausse alerte de ma part

Je l'ai signalé en recopiant la justification de la **règle 19** du `CLAUDE.md`
(*« `PromoStatus` et `CommercantAccountState` sont comparés par chaîne littérale
dans plusieurs écrans »*) sans la vérifier. Mesuré : **zéro** comparaison
littérale, et **tous** les champs d'état des modèles sont typés en enum
(`Categorie`, `PromoLifecycleStatus`, `PromoModerationStatus`,
`CommercantAccountState`, `RegistreStatus`).

Le défaut a été corrigé à une date que je n'ai pas cherchée ; c'est le **texte
de la règle** qui est resté au passé. **J'ai fait exactement ce que la méthode
reproche** : traiter une documentation périmée comme une donnée d'appui. Deux
fois en deux jours, après avoir écrit la mise en garde moi-même.

### Trois défauts trouvés en chemin, hors des 35 règles

- **Les tests unitaires mobile étaient cassés depuis trois semaines.** Cinq
  tests de `promo_test.dart` échouaient : `Promo.fromJson` caste `createdAt`
  sans repli depuis le commit `publishedAt` du 2026-07-14, et le helper du test
  datait du 2026-07-05. Personne ne pouvait le voir — le SDK Flutter n'était
  pas installable. **Premier `flutter test` réel du projet.**
- **Le code de localisation généré était périmé** depuis le merge d'`apqp5r` :
  `flutter analyze` rendait une **erreur** sur `promoDensityTooltip`. Les trois
  `.arb` avaient bien la clé — règle 27 respectée — c'est `gen-l10n` qui n'avait
  pas tourné.
- **Cinq fichiers Flutter générés apparaissaient modifiés en permanence** alors
  que `git diff` ne rendait rien : seules les fins de ligne changeaient. Réglé
  par un `.gitattributes` de portée étroite.

### État final

`flutter analyze` **0** · `flutter test` **14 verts** · `check_all` **4/4** ·
banc de cycle de vie **8/8**.

---

## Comment tenir ce fichier

- **Une entrée de journal par session**, datée, qui dit ce qui a été fait **et
  ce qui a été appris** — un piège rencontré vaut plus qu'une liste de commits,
  qui est déjà dans git.
- **Les points ouverts se ferment explicitement**, avec la date et ce qui les a
  fermés. Un point qui disparaît sans un mot est indiscernable d'un oubli.
- **Ne rien reconstituer de mémoire.** Si un fait n'est pas mesuré, l'écrire
  comme non mesuré. Une donnée d'appui fausse coûte plus cher qu'une absence.
- **Les chiffres portent leur date**, parce qu'ils vieillissent.
