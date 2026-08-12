# Plan de bascule géographique — de « wilaya/commune » vers « point GPS »

**Statut : à respecter pendant le développement. Pas encore approuvé pour exécution.**

Rédigé le 2026-08-12 à partir de deux analyses d'impact indépendantes (métier/UX et
technique), menées en lecture seule. **Relu le même jour par deux relecteurs
adversariaux** qui ont contrôlé ~70 et ~60 références `fichier:ligne` : la version
présente intègre leurs corrections. Aucun fichier applicatif n'a été modifié à ce jour.

**Les sept arbitrages du §3 sont tranchés**, ainsi que les deux risques laissés
ouverts (R7, R8). Il ne reste **aucune décision bloquante** — seulement **une mesure à
prendre avant le lot 4** (§12) : le nombre de commerçants sans position en base.

Ce document ne remplace ni `CLAUDE.md` (les règles), ni `docs/status_v0.1.md`
(le suivi vivant). Il décrit **un chantier** : ce qui est décidé, ce qui reste à
trancher, ce qui casse, et dans quel ordre travailler.

> ⚠️ **Rien ici n'a été exécuté** — ni build, ni test, ni banc, ni
> `migration:generate`, ni requête SQL. Les affirmations sont tirées de la lecture
> du code. Les trois points explicitement non vérifiables sont signalés en §12.

---

## 1. Objet

L'ancrage géographique du produit devient **le point GPS**. La hiérarchie
administrative wilaya → commune cesse d'être l'axe principal du parcours client.

**Motif** : ne plus maintenir un référentiel administratif saisi à la main
(`apps/backend/src/scripts/seed-communes.ts` — 35 communes reconstituées par
recherche web, avec un avertissement en tête du fichier disant que la liste n'est
pas vérifiée), et permettre un déploiement hors d'Algérie sans réécrire le modèle.

**Ce que le chantier n'est pas** : ce n'est pas la suppression de `Commune`. La
table est conservée (décision 9), et elle reste la frontière d'autorisation de
l'agent (§4.2).

---

## 2. Les décisions actées

Prises par le propriétaire du produit le 2026-08-12. Elles sont des **données
d'entrée** : ce document ne les rediscute pas.

| # | Décision |
|---|---|
| 1 | L'ancrage du produit devient le **point GPS**. Wilaya/commune cesse d'être l'axe principal. |
| 2 | La **publication** d'une promo est **bloquée** sans position du commerçant, avec un refus explicite qui lui explique pourquoi. L'inscription reste possible sans position. |
| 3 | **Client** : point par défaut = **Alger**, en configuration. Pas de GPS demandé au démarrage. Le client **enregistre lui-même** le point qui détermine ses promos — voir décisions 10 et 12. |
| 4 | **Liste client** : rayon par défaut **5 km**, configurable, plus un tri par distance. |
| 5 | `MAX_MAP_COMMERCANTS = 300` (`promo.service.ts:82`) passe en configuration. |
| 6 | Pour voir d'autres wilayas, le client **navigue sur la carte**. Pas de recherche de lieu par nom, pas de liste de villes, **pas de géocodeur** (ni direct ni inverse). |
| 7 | Le commerçant fournit **seulement sa position**. Pas d'adresse obligatoire. |
| 8 | Les commerçants déjà en base **sans position** : leurs promos deviennent **invisibles dès le basculement**. Pas de période de grâce. |
| 9 | La table `Commune` est **conservée**. Suppression ultérieure éventuelle, seulement si elle s'avère inutile. |
| 10 | Le point enregistré n'est transmis au serveur **qu'après consentement explicite**. Sans consentement, l'app **n'envoie aucune coordonnée** et le serveur applique son défaut. |
| 11 | Les valeurs de configuration (point par défaut, rayon, plafond de carte) vivent dans le **`.env` du serveur** et sont **servies à l'app**. Rien n'est compilé dans le binaire mobile. |
| 12 | 🔑 **L'app ne capte pas la position du client.** Ce qui détermine les promos affichées est **un point que le client enregistre lui-même**. Le capteur GPS, s'il est autorisé, sert **uniquement** à centrer la carte et à afficher les distances — **sur l'appareil, sans transmission**. |

**Décision 12 ajoutée le 2026-08-12**, après les décisions 10 et 11. Elle **précise
et allège** la décision 3 : ce qui part au serveur n'est pas une donnée de capteur,
c'est une **préférence saisie**. Toute la §2.1 en découle, et la gravité de A2 en est
divisée.

**Précision sur la décision 7** : « pas d'adresse obligatoire » n'est pas « pas
d'adresse ». `Commercant.adresse` existe déjà, est déjà facultatif
(`commercant.entity.ts:104`), et est déjà le **seul** texte de lieu affiché au
client (`promo_detail_screen.dart:462-465`, affiché uniquement s'il est non vide).
Il est **conservé tel quel** : coût zéro, et c'est le seul filet contre la dérive
GPS de 50 à 200 m d'un point capté à l'intérieur d'un local.

### 2.1 🔑 Quatre choses différentes, à ne jamais confondre (décisions 10 et 12)

C'est **la** distinction structurante du chantier. Elle doit être tenue dans le code,
dans les textes légaux et dans les fiches store — pas seulement ici. **Une seule** de
ces quatre données quitte l'appareil.

| # | Donnée | Nature | Quitte l'appareil ? |
|---|---|---|---|
| ① | Le **cadre visible de la carte** (bbox) | Ce que l'utilisateur *regarde*. Ne dit rien d'où il est — il peut naviguer sur Oran depuis Alger | **Oui**, et c'est déjà le cas aujourd'hui (`GET /promo/map`), sans consentement et sans grief |
| ② | Le **point par défaut de configuration** | Une constante du serveur, identique pour tous les clients | Ne quitte rien : **il vient** du serveur |
| ③ | Le **point que le client enregistre lui-même** | 🔑 Une **préférence saisie**, pas une mesure. Le client la choisit sur la carte ; **rien ne dit que c'est là où il se trouve, ni là où il habite** | **Oui, après consentement** (décision 10) |
| ④ | La **position du capteur GPS** | Donnée personnelle de localisation, lue sur l'appareil | **Jamais en continu, et jamais d'elle-même.** Elle sert à centrer la carte et à calculer les distances affichées, **sur l'appareil**. Elle ne quitte l'appareil que si le client s'en sert pour poser ③ — un geste, une fois (§2.1.1) |

**Comment le client pose ③ — deux chemins, un seul geste final.**

1. **Il navigue sur la carte** jusqu'à l'endroit qui l'intéresse (décision 6) ; ou
2. **il utilise le GPS pour se centrer** sur sa ville — ④ sert alors de *raccourci de
   cadrage*, pas de source de donnée.

Puis, **dans les deux cas**, il appuie sur « enregistrer ce point ». C'est ce geste, et
lui seul, qui crée ③ — et le point retenu est **celui qu'il a validé à l'écran**, jamais
une lecture de capteur faite en arrière-plan. Le point ainsi enregistré sert aux
**lancements suivants** de l'app.

⚠️ La nuance est mince à l'usage et **décisive juridiquement** : dans le chemin 2, ce
qui est transmis n'est pas « où était l'utilisateur » mais « quel point il a choisi
après s'être centré ». Un enregistrement automatique au moment où la permission est
accordée détruirait cette distinction — voir l'avertissement en fin de section.

**Ce que la décision 12 change, et c'est considérable** : le produit ne **capte** pas
la localisation du client, il reçoit un **point d'intérêt qu'il a saisi**. Trois
conséquences directes :

1. **Aucune permission système n'est requise** pour que la recherche fonctionne. Le
   GPS reste un confort facultatif, proposé **contextuellement sur la carte** — le
   placement, et lui seul, qui a levé le refus App Store 5.1.1(iv) du 2026-08-05.
2. **`ios/Runner/Info.plist:48-49` reste vrai et n'a pas à être réécrit** :
   « pour vous montrer les promotions les plus proches de vous » décrit exactement un
   calcul de distance sur l'appareil.
3. **Le commentaire `location_providers.dart:66-68` reste vrai** : « calculée sur
   l'appareil … le backend n'a pas besoin de connaître la position du client ». Il
   décrit ④, pas ③.

⇒ **Avant consentement, l'app n'envoie ni `latitude` ni `longitude`** sur `GET /promo` ;
le serveur applique alors ②. La carte, elle, continue à l'identique : elle envoie ①.

⚠️ **Le consentement se retire.** Au retrait : l'app cesse d'émettre ③, retombe sur ②,
et ce qui aurait été stocké côté serveur est effacé. Un consentement qu'on ne peut pas
reprendre n'en est pas un.

⚠️ **Le piège d'implémentation qui annulerait tout** : brancher ④ sur ③, c'est-à-dire
enregistrer automatiquement la position GPS comme point du client dès que la permission
est accordée. Ce serait *capter* la localisation en croyant offrir un raccourci — et
faire mentir d'un coup les CGU, l'`Info.plist` et les deux fiches store. **Le passage
de ④ à ③ n'existe que par un geste explicite de l'utilisateur** (« enregistrer ce point
comme mon point de recherche »), jamais par effet de bord.

### 2.2 Ce que les CGU, la politique de confidentialité et les fiches store doivent dire

Rédigé ici en **substance** — la formulation juridique définitive n'est pas du ressort
de ce document, mais **ces faits-là doivent y figurer**, sans quoi les vérifications
Google Play et App Store porteront sur une description fausse.

**Les cinq affirmations à écrire, dans les trois langues :**

1. *« L'application n'accède pas à la localisation de votre appareil pour vous montrer
   des promotions. »*
2. *« Vous choisissez vous-même un point sur la carte et vous l'enregistrez. Ce sont
   les commerces proches de **ce point** qui vous sont proposés. Il n'a pas à être
   votre domicile ni l'endroit où vous êtes. »*
3. *« Ce point est transmis à notre service uniquement pour construire la liste des
   promotions, après votre accord. »* — et, selon l'arbitrage A2.1, préciser s'il est
   **conservé** ou seulement utilisé le temps de la requête.
4. *« Vous pouvez le modifier ou le supprimer à tout moment. »*
5. *« Si vous autorisez l'accès à votre position, elle sert uniquement à centrer la
   carte et à afficher les distances. Elle est calculée sur votre appareil et n'est pas
   transmise. »*

**Fiches store — ce qui doit être déclaré, et ce qui ne doit pas l'être :**

| | Google Play « Sécurité des données » | App Store « Confidentialité » |
|---|---|---|
| Le point enregistré ③ | À **déclarer** comme localisation collectée, finalité « fonctionnalité de l'app », **non partagée**, **non utilisée pour le suivi** | Idem — catégorie *Location*, liée à l'identifiant d'appareil, usage « fonctionnalité de l'app », **pas de suivi** |
| La position du capteur ④ | **Couverte par la même déclaration**, puisqu'elle peut alimenter ③. Ce qu'on ne déclare pas, c'est un **suivi** : aucune lecture continue, aucun envoi en arrière-plan, aucun historique | Idem |

⚠️ **Correction du 2026-08-12.** Une version antérieure de ce document disait
« ne pas déclarer ④ comme collectée, elle ne quitte pas l'appareil ». **C'était
faux dès lors que le client peut poser ③ depuis sa position GPS** — le parcours
le plus naturel des deux. Des coordonnées dérivées du capteur et transmises
restent de la localisation collectée, même envoyées une seule fois et sur un
geste explicite. Sous-déclarer est le seul risque réellement coûteux ici : la
déclaration « collectée, sans suivi » n'ôte rien au produit, une déclaration
fausse coûte un refus.

**Ce qui reste vrai, et qui est l'essentiel** : pas de suivi, pas de lecture en
arrière-plan, pas d'historique de positions, et **l'app reste utilisable sans
jamais accorder la permission** — le client peut poser son point sur la carte.
C'est cette phrase-là qui doit figurer dans les CGU et qui tient devant une
revue.

⚠️ **Deux fichiers manquent et bloqueront la soumission, indépendamment de ce
chantier** : il n'existe **aucun `PrivacyInfo.xcprivacy`** dans `apps/mobile/ios`
(obligatoire côté Apple), et **aucun `InfoPlist.strings`** — la justification de
localisation est en **français uniquement** dans une app trilingue.

⚠️ Et la déclaration store passe de « localisation non collectée » à « localisation
fournie par l'utilisateur, collectée ». **C'est un changement de fiche publique**, à
faire au même moment que la mise en ligne, pas après.

---

## 3. Arbitrages — **tous tranchés le 2026-08-12**

Aucun n'était tranché par les décisions du §2 ; chacun bloquait un lot précis, et tous
menaient à un défaut silencieux si on les laissait se décider par omission. Ils sont
désormais clos. Le raisonnement est conservé sous chaque décision : il dit **pourquoi**,
donc il dit aussi quand la décision cesserait d'être valable.

### A1 — ✅ TRANCHÉ : route dédiée, et position obligatoire côté agent

**Le fait** : `CommercantService.updateProfile` pose `profilePendingReview = true`
dès qu'**un seul** champ est modifié (`commercant.service.ts:314-316`). Or
`profilePendingReview` bloque déjà la publication pour tout le monde, y compris
`confirmé_agent` (`promo.service.ts:474-475` et `:553-554`, via
`assertProfileValidated`, `commercant.service.ts:712-719`).

**Le parcours réel après la bascule** : « je ne peux pas publier, il me manque ma
position » → il la capte via le seul écran qui existe (`edit_profile_screen.dart:297`
→ `PATCH /commercant/me`) → « je ne peux toujours pas publier, un administrateur
doit valider votre profil » → attente humaine indéterminée. **Deux refus successifs
pour un seul geste correctif**, le second plus long que le premier.

Ce n'est pas une hypothèse : le décor de test s'est saboté exactement ainsi le
2026-08-05 (commit `aa7154a`, `docs/status_v0.1.md:2708-2712` : « un décor qui
répare un profil se sabote donc lui-même »).

**Trois issues :**

1. **`PATCH /commercant/me/position`** — route dédiée, protégée, qui écrit
   uniquement `latitude`/`longitude` et **ne touche pas** `profilePendingReview`
   quand il n'y avait aucune position auparavant. Précédent :
   `resolveRegistreVerification` remet déjà `profilePendingReview = false` dans un
   cas comparable (`commercant.service.ts:429`).
2. **Exception dans `updateProfile`** : ne pas mettre en revue un profil dont le
   seul champ modifié est la position alors qu'il n'y en avait aucune.
3. **Assumer le double blocage** et le dire : régularisation par validation admin,
   compte par compte.

✅ **Décision : l'issue 1**, et **elle ne suffit pas seule**.

L'issue 3 ferait de l'admin le goulot du produit le jour J — la file vaudrait
exactement le nombre de commerçants sans position. L'issue 2 modifie une méthode
traversée par tous les champs du profil, donc elle porte un risque de régression sur
un mécanisme qui marche ; la route dédiée ne touche à rien d'existant.

**Et parce qu'A1 ne traite que l'aval, on ferme aussi la source (§5.11) :**

| Écran | Position | Motif |
|---|---|---|
| **Création par l'agent** (`create_commercant_screen.dart:149`) | 🔴 **Obligatoire** | L'agent est **physiquement dans le commerce** — c'est la seule capture juste par construction, et **les 9 sites de `scripts/lib` passent tous par cette route** |
| **Auto-inscription** (`commercant_register_screen.dart:168`) | Facultative (inchangé) | Le commerçant peut s'inscrire de chez lui. La décision 2 garde l'inscription ouverte ; c'est la publication qui bloque |

Sans le premier, on répare un robinet qui coule : chaque tournée d'agent
reconstituerait le parc sans position qu'on vient de régulariser.

### A2 — ✅ TRANCHÉ : le volet légal, en quatre modalités

**Deux principes sont tranchés.** Décision 10 : rien ne part sans consentement
préalable, et le consentement se retire. **Décision 12** : ce qui part n'est pas une
donnée de capteur mais **un point saisi par l'utilisateur** (§2.1). Restent les
**modalités**.

⚠️ **La décision 12 divise la gravité de ce volet.** La première version de ce
document listait quatre affirmations « contredites » par la bascule. Avec la
décision 12, **trois d'entre elles restent vraies** :

| Où | Ce qui est affirmé | Après décision 12 |
|---|---|---|
| Politique de confidentialité, §1 (`app_fr.arb:367`, `legalPrivacyContent`, + `_en`, `_ar`) | « Client : aucune donnée personnelle ni compte requis » | 🟠 **À compléter** — le point enregistré doit y figurer comme donnée fournie par l'utilisateur. C'est un ajout, plus une contradiction |
| Justification iOS (`ios/Runner/Info.plist:48-49`) | « pour vous montrer les promotions les plus proches de vous » | ✅ **Reste vraie** — elle décrit ④, un calcul de distance sur l'appareil. **Ne pas la réécrire** |
| Onboarding (`app_fr.arb:379`, `onboardingLocationPerkPrivacy`) | « Aucune donnée partagée avec les commerçants » | ✅ **Reste vraie** |
| Le code (`location_providers.dart:66-68`) | « Calculée sur l'appareil … le backend n'a pas besoin de connaître la position du client » | 🟡 **À préciser.** Vraie pour le **calcul de distance**, qu'elle décrit. Trompeuse comme énoncé général, puisque le point enregistré — éventuellement issu du GPS — part bien au serveur. À restreindre explicitement à `distanceTo` |

⇒ Le seul texte à modifier est la **politique de confidentialité**, et c'est un
**ajout**, pas un démenti. La justification iOS — celle qui a coûté le refus 5.1.1(iv)
du 2026-08-05 (`status_v0.1.md:806-851`) — n'est **pas** à toucher.

⚠️ **Mais cette bonne nouvelle est conditionnelle** : elle ne tient que si le code
respecte réellement la séparation ③/④ du §2.1. Si l'implémentation enregistre la
position GPS comme point du client par commodité, les trois « ✅ » ci-dessus
redeviennent des 🔴 d'un seul coup, et cette fois avec un antécédent de refus au
dossier.

**Le trou de fond** : `consentedAt` n'existe que sur `Commercant`
(`commercant.entity.ts:261`), est écrit en `commercant.service.ts:151` et **jamais
relu** — aucun `SELECT`, aucun DTO de sortie (valeur écrite et morte, règle 31) ;
**aucune version de CGU n'est stockée** (recherche
`cguVersion|termsVersion|legalVersion|consentVersion` sur tout le dépôt : 0
résultat) ; **le client n'a accès à aucun document légal dans l'app** (les deux
seuls liens `/legal/*` sont dans l'espace commerçant,
`commercant_register_screen.dart:239,243` et `edit_profile_screen.dart:345,349`).

**Les quatre modalités — toutes tranchées :**

**A2.1 — ✅ Transmise seulement, jamais stockée.** Le point ③ vit dans le stockage
local de l'app (au même endroit que `selected_commune_ids` aujourd'hui) et voyage
comme **paramètre de requête** de `GET /promo`. **Rien n'est écrit côté serveur.**

C'est ce que « faciliter la recherche » demande, ça réduit la déclaration store au
minimum défendable, et c'est **réversible** : stocker plus tard sera un ajout.

⚠️ **Deux conséquences à assumer, pas à découvrir** : pas de notification « nouvelle
promo près de chez vous », et **aucune analyse de couverture** (« où manque-t-on de
commerçants ? »). ⚠️ **Et une vérification à faire** : une URL complète journalisée
suffirait à faire mentir « rien n'est écrit ». Contrôler la configuration des journaux
d'accès avant de l'affirmer dans les CGU.

**A2.2 — ✅ Le geste d'enregistrement EST le consentement. Pas d'écran dédié.**
Le client choisit un point et l'enregistre : c'est un acte explicite, dont la finalité
est évidente au moment où il le pose. On y attache **une phrase** (« ce point sera
envoyé à notre service pour construire votre liste ») et **un réglage pour le retirer**
dans les paramètres.

Un écran de consentement séparé serait de la friction pour une donnée que
l'utilisateur vient de saisir lui-même dans ce but précis.

**Stockage** : `{point, acceptéLe, versionDuTexte}` dans le stockage local — pas de
compte, donc rien à rattacher côté serveur (cohérent avec A2.1). ⚠️ **La version est
obligatoire** : sans elle, aucun re-consentement n'est possible quand le texte change,
alors que le §7 des CGU annonce lui-même qu'ils évolueront. C'est aujourd'hui un trou
complet du produit — recherche `cguVersion|termsVersion|legalVersion|consentVersion`
sur tout le dépôt : **0 résultat**.

**A2.3 — ✅ Coupé en deux.** L'**ajout à la politique de confidentialité** part dans
**le lot 3**, même commit que la porte de consentement — le texte qui décrit un
comportement voyage avec lui (règles 23 et 27). Les **fiches store**, le
`PrivacyInfo.xcprivacy` et l'`InfoPlist.strings` partent dans un **lot 8 séparé**,
avant soumission : ils ne bloquent aucune ligne de code.

**A2.4 — ✅ Les textes restent dans le bundle pour l'instant.** Les héberger est un
chantier à part, sans rapport avec la bascule géographique. **Une exception, dans le
lot 3** : `legalCguContent` (`app_fr.arb:366`) contient **« quartier pilote
(Djelfa) »** écrit en dur, en trois langues — dans les CGU. Cette phrase devient fausse
avec la bascule, elle sort maintenant.

### A3 — ✅ CLOS : `.env` du serveur, valeurs servies à l'app (décision 11)

**Question posée** : la décision 3 disait « en `.env` », or **le mobile n'a pas de
`.env`** — `lib/config/env.dart` n'expose que trois `String.fromEnvironment`
(`--dart-define`), compilés dans le binaire, et `CLAUDE.md` § Environnement
documente qu'ils **se perdent silencieusement** selon la façon dont `flutter` est
lancé.

**Réponse** : le `.env` **du serveur**. L'app va chercher ces valeurs.

**Ce que cela impose, à écrire dans le lot 1 :**

1. **Une route publique de configuration client** — position par défaut, rayon par
   défaut, rayon maximum. Route ouverte ⇒ **à épingler nommément avec sa
   justification** dans `scripts/lib/frontiere_http.py` (règle 33). ⚠️ Elle est
   **publique et non authentifiée** : rien d'autre que ces trois valeurs ne doit y
   figurer.
2. **Un repli au tout premier lancement hors ligne.** C'est le seul endroit où une
   coordonnée est écrite côté app : il doit être **unique** (§A4) et **jamais** relu
   par un vérificateur (§5.7).
3. **Le rayon effectif voyage dans la réponse**, comme `PromoSlots.plafond`
   (`promo.service.ts:989-1005`) — aucune valeur recopiée, et les chaînes
   d'interface le reçoivent par **placeholder** (§5.8).

**Bénéfice décisif** : le pilote est à Djelfa, le défaut est Alger. Un rayon de 5 km
autour d'Alger rendrait la liste **vide** pour tout client du pilote sans GPS. On
règle donc le défaut sur Djelfa pendant le pilote et sur Alger ensuite, **sans
republier l'app**.

`MAX_MAP_COMMERCANTS` reste purement serveur et n'est pas servi à l'app —
`client_carte.py:184-186` le **déduit déjà de la réponse**.

### A4 — ✅ TRANCHÉ : une seule cascade, et `_fallbackCenter` disparaît

`map_screen.dart:26` code **Djelfa en dur** (`_fallbackCenter = LatLng(34.6703,
3.2630)`). La décision 3 met Alger. En l'état, un client sans GPS verrait **une liste
autour d'Alger et une carte sur Djelfa**.

✅ **Décision : une cascade unique, à trois étages, lue au même endroit par la liste et
par la carte.**

1. **Le point enregistré par le client** ③, s'il existe ;
2. sinon **le point par défaut servi par le serveur** ② ;
3. sinon — et **uniquement** avant que le serveur ait jamais répondu (premier lancement
   hors ligne) — **une constante compilée unique**.

`_fallbackCenter` est **supprimé** de `map_screen.dart` : c'est le troisième étage,
et il ne doit exister qu'en un exemplaire pour toute l'app (règle 30).

⚠️ **La valeur configurée reste Alger** (ta décision 3). Rappel factuel, sans le
rediscuter : le pilote est à Djelfa, donc pendant le pilote un client sans point
enregistré verra une liste vide. C'est **une ligne de `.env` à changer**, sans
republication — c'est précisément pourquoi A3 a été tranché ainsi.

### A5 — ✅ TRANCHÉ : fusionner d'abord la définition de « visible », puis y ajouter la condition

La décision 8 dit « invisibles dès le basculement ». Deux façons de l'obtenir — et
**la recommandation initiale de ce document était fausse**, corrigée ici après
relecture :

- **(i)** Ajouter `commercant.latitude IS NOT NULL` à la définition de « visible ».
  ⚠️ **Mais `applyVisibleConditions` (`promo.service.ts:186-213`) n'est PAS unique** :
  `findActiveForMap` redéclare localement les cinq mêmes conditions dans
  `visiblePromoConditions` (`:681-691`). Le commentaire de `:186-196` proclame
  « l'unique définition » et le même fichier le dément 500 lignes plus bas — une
  duplication règle 30 **préexistante et jamais inventoriée**. L'option (i) ne
  toucherait donc pas la carte tant que cette duplication n'est pas résolue.
- **(ii)** Ne rien changer côté lecture : les deux gardes explicites
  `latitude IS NOT NULL` / `longitude IS NOT NULL` de `findActiveForMap`
  (`:698-699`) et le futur filtre au rayon les excluent déjà de fait.

**Pourquoi (ii), initialement recommandé, est le mauvais choix** :
`promo.service.ts:1292-1295` documente que la jointure de `countVisible` a été
rendue inconditionnelle **précisément parce que** « le dashboard annonçait des
promos publiées qu'aucun client ne voyait ». Avec (ii), un commerçant sans position
verrait « 3 en ligne » sur un stock invisible — le défaut fondateur de la règle 8,
refabriqué à l'identique.

✅ **Décision : (i), précédée de la fusion de `visiblePromoConditions` dans
`applyVisibleConditions`** — et la fusion est un lot à elle seule (lot 2a), livrée et
vérifiée **avant** qu'on y ajoute quoi que ce soit.

Ajouter une sixième condition à une définition qui n'est pas la seule produirait
exactement le défaut qu'on cherche à éviter : deux vérités sur « qu'est-ce qui est
visible », dont une seule à jour.

### A6 — ✅ TRANCHÉ : le repli « Top promos » est re-scopé par rayon

`topPromosProvider` passe `communeIds` (`promo_providers.dart:315`), et le repli
calculé côté serveur est scopé par commune (`highlight.service.ts:61`, `:75`,
`buildFallbackSlides(communeIds)`). Sans commune, **ce repli devient national** :
un client de Djelfa verrait en vitrine les meilleures réductions d'Alger.

✅ **Décision : re-scoper par rayon**, avec les mêmes paramètres que la liste.

Retirer le repli viderait la vitrine partout où la densité est faible — c'est-à-dire
dans la majorité du territoire visé. Et c'est la même forme de requête que la liste :
le coût est celui d'un paramètre, pas d'une fonctionnalité.

### A7 — ✅ TRANCHÉ : coordonnées du commerçant dans `toClientJson`, distance affichée par l'app

Découvert en relecture, **absent de la première version, et bloquant pour le §6**.

`GET /promo` sérialise via un DTO de sortie explicite — `toClientJson`
(`promo.controller.ts:55-82`) — qui ne porte **ni coordonnées du commerçant, ni
champ libre**. Et `getManyAndCount()`, la recette copiée du tri `DISCOUNT`,
**jette les colonnes brutes d'un `addSelect`**. Le précédent ne tient que parce que
`discount_ratio` sert uniquement à ordonner et n'est jamais rendu ; la distance, elle,
doit être **affichée** (R2).

⚠️ **Et la fusion naïve `{...promo, distanceKm}` est exactement le bug fondateur de
la règle 4** — le spread transforme l'instance en objet plain et désactive les
`@Exclude()`.

**Deux voies :**

- **(a) Exposer `latitude`/`longitude` du commerçant dans `toClientJson`, et laisser
  l'app calculer la distance affichée.** Le serveur ordonne, l'app affiche.
  `distanceTo` existe déjà (`location_providers.dart:66-73`). Pas de
  `getRawAndEntities`, pas de perte du `count`, pas de spread.
  ⚠️ Deux formules coexisteraient (règle 30) : elles doivent être **la même
  haversine**, et l'ordre affiché reste **celui du serveur**, jamais un re-tri local.
  Note : les coordonnées des commerçants sont **déjà publiques** via `/promo/map` —
  les exposer ici n'ouvre rien de neuf.
- **(b) `getRawAndEntities()` + un champ `distanceKm` dans le DTO de sortie**, avec
  une requête de comptage séparée. Sémantiquement plus propre, une requête de plus.

✅ **Décision : (a).** Moins de surface, réutilise `distanceTo` qui existe déjà, et évite
les deux pièges d'un coup (perte du `count`, règle 4).

⚠️ **Trois garde-fous non négociables** :
- **la même haversine des deux côtés** — le serveur ordonne, l'app affiche ; deux
  formules qui divergent donneraient une liste dont l'ordre contredit les distances
  affichées ;
- **jamais de re-tri local** : l'ordre affiché est celui du serveur, toujours ;
- **jamais `{...promo, distanceKm}`** — c'est le bug fondateur de la règle 4.

---

## 4. Ce qui ne change pas — et qu'il ne faut surtout pas « nettoyer »

### 4.1 `Commercant.communeId` reste `NOT NULL`

Le rendre nullable coûte immédiatement, pour un gain nul :
`assertCommuneMatches` fait `agentCommuneIds.includes(commercant.communeId)`
(`commercant.service.ts:670-682`) — sur `null`, la garde refuse **toujours**, et un
agent ne peut plus rien faire sur ce commerçant. `aliveAccountWhere` (`:488-494`),
`findAllForAdmin` (`:548-563`), `PromoService.findAllForAdmin` (`:895-899`),
`countVisible` (`:1302-1304`) et `ReportService.pendingModerationQueryBuilder`
(`:175-189`) cadrent tous l'agent par `communeId IN (...)` : un `null` sort
silencieusement du périmètre de tout agent.

⇒ **Décision séparée, à prendre le jour où le rôle agent disparaît.**

> ✅ **Prise le 2026-08-13 : l'agent devient GLOBAL.** ⚠️ Contrairement à ce
> qu'on pourrait lire ici après coup, **ce document ne l'avait pas décidé** — il
> avait seulement identifié la question et l'avait laissée ouverte. La décision
> est postérieure, et elle ouvre un chantier distinct : la suppression de
> `wilaya`/`commune`, avec une **adresse libre facultative** pour seul texte de
> lieu.
>
> ⚠️ **Ce que cela emporte, et qu'il faut regarder en face** : `scopedCommuneIds`
> et `assertCommuneMatches` disparaissent. Ce sont les gardes IDOR de la
> **règle 1**, nées d'un IDOR critique réel. Un agent global n'est plus un agent
> *mal* cadré, c'est un agent *non* cadré — c'est un choix produit assumé, pas un
> effet de bord, et il doit être écrit comme tel partout où ces gardes
> disparaissent.
>
> Corollaire : le décor et quatre bancs (`appartenance`, `admin_agents`,
> `agent_creation`, `admin_dashboard`) reposent sur « deux communes disjointes »
> pour éprouver l'isolation de l'agent. **Leur sujet disparaît** — ils ne se
> corrigent pas, ils se suppriment.
>
> ⚠️ **Et une perte irréversible à traiter AVANT la migration** : mesuré le
> 2026-08-13, 78 commerçants actifs, 66 avec une adresse. **Douze n'ont que leur
> commune** comme information de lieu. Supprimer la colonne la détruit
> définitivement, et l'adresse étant facultative, rien ne la reconstituera.
>
> ✅ **Tranché le 2026-08-13 : la recopie se fait.** `« commune, wilaya »` est
> versé dans `adresse` **uniquement quand celle-ci est vide**, dans la même
> migration que la suppression — écraser une adresse saisie par le commerçant
> par un nom de commune serait un recul, pas une préservation.
>
> Trois précisions qui font la différence entre une migration et une perte :
> - elle porte sur **toutes** les lignes, y compris les comptes supprimés
>   (`deletedAt IS NOT NULL`) : leur historique disparaîtrait aussi, et le coût
>   d'inclure est nul ;
> - elle s'exécute **avant** le `DROP`, dans la même transaction — TypeORM
>   enveloppe déjà toutes les migrations en attente dans une seule (règle 12) ;
> - ce qu'on écrit n'est **pas une adresse**, c'est une localité. Le commerçant
>   doit pouvoir la corriger : le champ reste libre et modifiable, et le `down()`
>   ne saura pas la distinguer d'une adresse saisie — **la migration n'est donc
>   pas réversible**, et ça doit être écrit dans son en-tête plutôt que découvert.

### 4.2 La commune est la frontière d'autorisation de l'agent

`AdminController.scopedCommuneIds` (`admin.controller.ts:267-273`) cadre quatre
endpoints (`:318`, `:404`, `:426`, `:704`), et `assertCommuneMatches` est la garde
IDOR née de la **règle 1**, elle-même née d'un IDOR critique réel.

> ✅ **Caduc depuis le 2026-08-13** (voir §4.1) : l'agent devenant global, cette
> frontière n'a plus d'objet. Ce qui suit décrit l'état **avant** cette décision,
> et reste la meilleure description de ce que sa suppression emporte.

⇒ La décision 9 se lit « **`communeId` reste rempli** ». La cascade wilaya → commune
reste à l'inscription, et `GET /commune` reste une route ouverte épinglée
(`frontiere_http.py:71`).

### 4.3 `commune_multi_select_field.dart` est partagé client ↔ admin

Il sert la sélection du client **et** l'assignation de communes à un agent
(`agent_list_screen.dart:67` et `:255`, `create_agent_screen.dart:109`). Le
supprimer avec la sélection client casserait l'écran admin.

### 4.4 La carte n'est pas filtrée par commune

`mapShopsProvider` interroge par cadre visible et ne lit jamais
`selectedCommunesProvider` (`map_providers.dart:85-95`, confirmé
`status_v0.1.md:2042-2047`). La bascule ne touche donc pas la carte, sauf par la
suppression du centrage par commune (lot 5).

### 4.5 Sans impact vérifié : le thème et la langue

Sondés, rien n'y touche. `check_theme.dart` n'est convoqué que pour un éventuel
**nouvel** écran (§9). Écrit ici pour éviter qu'on le revérifie.

---

## 5. Les pièges qui feront échouer une implémentation naïve

Chacun est un défaut **silencieux** : ni erreur de compilation, ni exception, ni
journal.

### 5.1 🔴 `configNumber` refuse toute valeur ≤ 0 — donc toute longitude ouest

`config-number.ts:115` est `if (!Number.isFinite(n) || n <= 0)`, et le plancher n'est
évalué qu'en `:127` : **`options.minimum` ne lève pas ce refus**. C'est délibéré et
éprouvé (`config-number.spec.ts:51-54` : « refuse zéro et le négatif — aucun plafond
nul n'a de sens ici »).

Conséquence : **une longitude négative retombe sur le défaut**, en silence (le
journal existe, mais le backend démarre et sert). Alger (+3.06) et Djelfa (+3.26)
passent par chance. Oran (−0.64), Tlemcen (−1.31), Sidi Bel Abbès (−0.63) : **tout
l'ouest algérien est en longitude négative.**

⇒ Lot 0, préalable strict à toute clé de coordonnée. Une option explicite qui,
lorsque `minimum < 0`, **remplace** le garde-fou au lieu de s'y ajouter, plus des cas
de banc dans les deux sens (règle 28) : −0.64 doit **passer**, −200 doit **refuser**,
et le refus doit rester actif pour les plafonds qui n'ont pas demandé de signe.

### 5.2 🔴 Le vrai piège de conversion : `?latitude=` vide vaut zéro, pas `NaN`

⚠️ **La première version de ce document se trompait de piège.** Elle annonçait un
`NaN` sur champ absent. C'est faux : `class-transformer@0.5.1` construit ses clés
depuis l'objet source, `@Transform` n'en ajoute pas, et **le callback n'est donc
jamais appelé pour une clé absente**. (Établi par lecture de
`node_modules/class-transformer/cjs/TransformOperationExecutor.js`, non par
exécution — §12.)

**Le piège réel est le miroir, et il est bien là** : `?latitude=` **présent mais
vide** donne `Number('')` → `0`, que `@IsLatitude()` **accepte**. Le client se
retrouve à l'équateur, sans un mot. C'est le jumeau du §5.10.

⇒ Ne pas réinventer le remède : le dépôt utilise déjà `@Type(() => Number)`
(`common/pagination/pagination-query.dto.ts:14,20`), qui préserve `null`/`undefined`
nativement (règles 21 et 30). Et refuser explicitement la chaîne vide.

### 5.3 🔴 `ValidationPipe` sans `forbidNonWhitelisted` : le DTO avant l'app, jamais l'inverse

`main.ts:40` monte `ValidationPipe({ whitelist: true, transform: true })` —
`forbidNonWhitelisted` est **absent**. Si l'app émet `latitude`/`longitude` avant que
le DTO ne les porte, ils sont **retirés en silence** : la liste « marche », le serveur
ignore le filtre, et rend tout. C'est la « liste fausse » corrigée le 2026-08-05.

⚠️ `transform: true` est ce qui fait tourner la transformation des DTO — donc le
pivot du §5.2.

⇒ Le lot 2 (backend) précède obligatoirement le lot 3 (mobile).

### 5.4 🔴 Le tri par distance a des ex æquo par construction

Toutes les promos d'un même commerçant partagent **exactement** la même distance.
Sans départage déterministe, `skip/take` fait réapparaître et disparaître des lignes
entre la page 1 et la page 2.

⇒ À la suite du `ORDER BY distance` : `promo.publishedAt DESC NULLS LAST`, **puis
`promo.id ASC`**.

⚠️ **Et ce n'est pas un travail neuf** : `DISCOUNT` porte déjà le `publishedAt`
(`promo.service.ts:637`) mais **pas** le départage final sur `id` — il est donc
lui-même instable. Règle 30 : corriger aux deux endroits, ou à aucun.

### 5.5 🔴 Neuf sites de banc créent des commerçants sans position (règle 38)

**Aucun module de `scripts/lib/` ne pose de coordonnées à la création** — 5 fichiers,
**9 sites** : `agent_creation.py:209,233` · `autosuppression.py:263,339` ·
`commercant_profil.py:225` · `cycle_commercant.py:204,261,286` · `registre.py:254`.
Ils alimentent 5 bancs (`test-agent-creation`, `-commercant-autosuppression`,
`-commercant-profil`, `-cycle-commercant`, `-registre`).

Dès que le blocage de publication existe, chaque promo publiée par ces bancs sera
refusée en 403 — **sur un produit parfaitement correct**. On partira corriger un code
qui n'a rien, et ce sera d'autant plus crédible que le message parlera bien de
position.

⇒ **Les coordonnées doivent être posées dans ces 9 sites dans le même commit que le
blocage.**

⚠️ **Correction importante** : `provision-decor.sh:257` (`latitude:34.6714,
longitude:3.2630`, motif en `:245-252`) et `seed-demo.sh:207-214` **posent déjà les
coordonnées** — c'est le commit `aa7154a` du 2026-08-05, « poser les coordonnées **à
l'inscription** et non après », précisément à cause de l'impasse A1. Le risque
résiduel est donc **plus étroit** que ce que la première version affirmait : il ne
concerne qu'une **base de décor créée avant le 2026-08-05**, que
`provision-decor.sh:241-262` (idempotent par la connexion) ne réinscrira jamais. Le
remède est alors `PATCH /commercant/me/position` (A1) ou une remise à zéro
documentée — pas une modification du script.

### 5.6 🔴 « Position absente » doit être décidé, et les consommateurs de `GET /promo` énumérés

`communeIds: []` signifie aujourd'hui « aucun filtre », pas « aucune commune »
(`promo.service.ts:600`) — sémantique qui a coûté un écran de commentaires et une
redirection dédiée. **Ne pas la reproduire.**

⚠️ **Et il faut la décider en connaissant la liste des appelants**, sinon elle se
prendra par défaut. `GET /promo` sert au moins :

| Appelant | Ce qu'il envoie | Effet si « absence ⇒ défaut serveur » |
|---|---|---|
| La liste client | position (post-consentement) ou rien | correct |
| L'onglet **Favoris** | rien de géographique — filtre **purement local** sur les pages chargées (`promo_providers.dart:224-225`, `:248-254`) | §10 L |
| « Autres promos du magasin » (`shopPromosProvider`, `promo_providers.dart:321-327`) | `commercantId` + `limit: 10`, **ni commune ni position** | 🔴 **section vide** pour tout commerce hors du rayon par défaut |
| Le repli `sort=discount` du bandeau | `communeIds` aujourd'hui | A6 |
| Les bancs | variable | §5.5 |

⇒ **Règle à écrire** : quand `commercantId` est fourni, **aucun filtre géographique
ne s'applique**. Sans cette exception, la fiche promo perd sa section « autres promos
du magasin » sans qu'aucune erreur ne le signale.

### 5.7 `check_server_rules.dart` ne sait pas lire un décimal

`borneConfigServeur` (`:123-128`, la capture `(\d+)` en `:125`) et `nombresApp`
(`:240-243`, `int.parse`). Sur `36.7538`, trois chemins possibles selon le motif :
lecture silencieuse de `36`, refus « motif ambigu » sur `{36, 7538}`, ou
`FormatException` non rattrapée. **Un seul des trois rend vert** — mais aucun ne lit
juste.

⇒ **Ne recopier aucune valeur géographique côté app.** Le rayon effectif voyage dans
la réponse serveur. Alors `check_server_rules.dart` n'a rien à recevoir.

### 5.8 Ne jamais écrire un chiffre dans une chaîne traduite (règle 32)

« dans un rayon de 5 km » écrit dans les trois `.arb` reproduirait le défaut
« Plafond de 5 promos atteint » : porter le rayon à 10 afficherait encore 5, et aucun
outil ne le verrait.

⇒ **Placeholder obligatoire**, alimenté par la valeur servie. Le précédent correct
existe : `maxCommunesHint` (`app_fr.arb:352-359`, paramétré par `{max}`).

⚠️ **Et le §5.8 de la première version ne citait que deux clés porteuses de règle en
prose. Il y en a une vingtaine.** Les plus coûteuses :

| Clé | Ce qu'elle porte |
|---|---|
| `legalCguContent` (`:366`) | **« quartier pilote (Djelfa) »** en dur, dans les CGU, en 3 langues |
| `onboardingLocationPerkNearby` (`:377`) | « Les commerces **les plus proches** d'abord » — une promesse de tri, jumelle de `Info.plist:49`, que rien ne tient ensemble |
| `noCommuneSelectedBody` (`:135`) | « les promos dépendent des communes que vous suivez » |
| `mapLocationInvite` (`:382`) | « vous verrez toutes les promos **de la commune** » |
| `:497` et `:504` | **la même phrase sous deux clés** (règle 30) |
| `:80` vs `:134` | « votre **commune** » (singulier) contre « vos **communes** » (pluriel) |

### 5.9 Ne pas poser la garde de position hors du `if (!dto.asDraft)`

`promo.service.ts:467-472` documente la régression exacte qu'on refabriquerait : des
gardes posées pour tout le monde refusaient aussi « Enregistrer comme brouillon »,
« avec un message parlant de publier, sur un geste qui ne publie pas ». **Un
commerçant sans position doit pouvoir préparer ses promos.** Le `if (!dto.asDraft)`
est en `:473`, les gardes en `:474-475`, et `publish` les rappelle en `:553-554`.

### 5.10 Tester `=== null`, pas la véracité

`if (!commercant.longitude)` refuserait une longitude à **0**, méridien légitime.
Écrire `commercant.latitude === null || commercant.longitude === null`.

### 5.11 🔴 La source du parc sans position est en amont, dans deux écrans

`LocationCaptureField` est posé par `commercant_fields_form.dart:120`, partagé par
**`commercant_register_screen.dart:168`** (auto-inscription) **et
`create_commercant_screen.dart:149`** (création par l'agent). La position y est
facultative des deux côtés, et **les 9 sites de `scripts/lib` passent tous par
`POST /agent/commercant`**.

⇒ L'agent est **physiquement dans le commerce** : rendre la position obligatoire sur
son écran tarit la source, là où A1 ne fait qu'écoper. À trancher avec A1, dans le
même lot.

### 5.12 Le rate-limiting n'est jamais gratuit

- `PATCH /commercant/me/position` (lot 4) est une écriture ⇒ seau
  `SENSITIVE_ACTION_THROTTLE`, **20/min/IP et partagé** — un commerçant qui corrige sa
  position consomme le même seau que ses publications.
- Le lot 2 transforme la route **publique** `GET /promo` en requête géographique avec
  bbox. `/promo/map` a reçu `MAP_THROTTLE` (`common/throttle.ts:31`) **pour exactement
  cette raison**. Règles 2, 7 et 33 : décider explicitement du seau de `GET /promo`,
  ne pas le laisser au plafond global par omission.

---

## 6. Le choix technique du tri par distance

**L'index actuel ne sert pas le tri.** `IDX_commercant_position` est un btree
composite partiel (`commercant.entity.ts:52-54`, migration
`1783810000000-AddCommercantPositionIndex.ts:19-22`). Il sert le `BETWEEN` de
`findActiveForMap` (`promo.service.ts:698-707`), mais **un btree n'ordonne pas selon
une expression calculée**.

**Option retenue : A — pré-filtre bbox dérivé du rayon, puis haversine en SQL.**

`Δlat = rayonKm / 111.32` ; `Δlon = rayonKm / (111.32 · cos(lat))`. Même `BETWEEN`
que la carte (l'index sert), tri sur la formule haversine, et **rognage des coins du
carré** par la même formule.

- **Coût** : zéro migration, zéro extension, zéro changement Docker.
- **Précédent** : `PromoSortOrder.DISCOUNT` (`promo.service.ts:630-641`) fait déjà
  `addSelect` + `orderBy` sur alias + `skip/take` + `getManyAndCount()`.
- **Limite assumée** : le tri porte sur l'ensemble déjà réduit par la bbox. Sans objet
  à l'échelle d'une wilaya.
- ⚠️ **Mais la recette ne suffit pas pour *rendre* la distance** — voir **A7**, qui
  bloque ce choix tant qu'il n'est pas tranché.

**Options écartées :**

- **B — `cube`/`earthdistance` + GiST sur `ll_to_earth(...)`.** TypeORM ne sait pas
  déclarer un index GiST **sur expression** via `@Index()` (l'annotation
  `{spatial: true}` existe pour une colonne, pas pour une expression). L'index
  existerait donc **en base sans déclaration d'entité**, et le prochain
  `migration:generate` proposerait de le **supprimer** — le défaut réel de
  `UQ_commercant_telephone_active` documenté en `commercant.entity.ts:55-74`. Règle 12
  dans son sens miroir.
- **C — PostGIS.** Impose une image Debian là où le volume `postgres_data` a été
  initialisé par Alpine (`docker-compose.yml:14,23,71`). Collations différentes, index
  à reconstruire, sur le VPS de production aussi.

**Un point de conception aussi important que le choix** : le `BETWEEN` de la bbox
existera à **deux endroits** — `findActiveForMap` et la nouvelle liste. Règle 30
⇒ **un seul `applyBoundingBox(qb, {north,south,east,west})`**. Pas un commentaire
« même filtre que la carte ».

**Le tri par défaut ne change pas.** `list-promo-query.dto.ts:15-24` l'interdit
explicitement. ⇒ `sort` reste `recent` par défaut, et **la présence de
`latitude`/`longitude` bascule le tri sur la distance**.

---

## 7. Les lots, dans l'ordre

### Lot 0 — `configNumber` accepte les valeurs signées bornées
**Préalable strict au lot 1.** `common/config/config-number.ts` +
`config-number.spec.ts` (règle 28, refus dans les deux sens).

⚠️ **Le périmètre de non-régression est de 7 appels, pas 5** :
`promo.service.ts:114, 122, 130, 139, 148, 161` **et** `report/report.service.ts:52`.
Le « cinq » vient de la règle 34 de `CLAUDE.md`, elle-même périmée.

### Lot 1 — Les clés de configuration et la route qui les sert
`MAX_MAP_COMMERCANTS` (300, aujourd'hui `promo.service.ts:82`),
`CLIENT_DEFAULT_RADIUS_KM` (5), `CLIENT_DEFAULT_LATITUDE` / `CLIENT_DEFAULT_LONGITUDE`,
`CLIENT_MAX_RADIUS_KM`. Toutes lues par `configNumber`, jamais `get<number>` (règle 34).

⚠️ **Deux commentaires décrivent `MAX_MAP_COMMERCANTS` comme une constante de
service** (`list-promo-map-query.dto.ts:9`, `common/throttle.ts:31`) : ils deviennent
faux dans ce lot (règle 23).

**Règle 36 — trois endroits, même commit** : `apps/backend/.env.example`,
`.env.production.example` **à la racine**, **et le `.env` réel du clone WSL**
(`~/projects/echangopromo/apps/backend/.env`, hors dépôt) — à faire à la main et **à
écrire dans le message de commit**.

**À corriger au passage** : `PROMO_DAILY_CREATION_CAP` (`promo.service.ts:140`) et
`PROMO_REPUBLISH_COOLDOWN_HOURS` (`:149`), lues par `configNumber` et **absentes des
deux `.env.example`**.

**Et la route publique de configuration client** (décision 11), **épinglée** dans
`frontiere_http.py` et dotée d'un appelant mobile **dans le même commit** (règles 11,
31, 33).

### Lot 2 — `GET /promo` apprend la position (backend seul)
DTO (`latitude`, `longitude`, `radiusKm?`) sur le patron de
`list-promo-map-query.dto.ts:17-31`, avec `@Type(() => Number)` et le refus de la
chaîne vide (§5.2), et des bornes réelles — `@Max` sur `radiusKm`, sans quoi c'est une
bbox arbitrairement grande sur une **route publique** (règle 34, précédent
`dureeJours`). `applyBoundingBox` partagé (§6). Haversine, tri, **départage
déterministe** (§5.4, aux deux endroits). `list-promo-query.dto.spec.ts` (règle 28).
Le seau de throttle décidé explicitement (§5.12). L'exception `commercantId` (§5.6).

`communeIds` **reste accepté** ⇒ l'app existante continue de fonctionner. Vérifier que
`migration:generate` ne rend **rien** (règle 12), et supprimer tout fichier
exploratoire avant un `migration:run`.

**Porte aussi les décisions A7 et R8** : `latitude`/`longitude` du commerçant ajoutées à
`toClientJson` (le serveur ordonne, l'app affiche — jamais de spread, règle 4), et **le
rayon cesse de s'appliquer dès qu'un terme de recherche est présent**, le tri par
distance restant actif.

### Lot 2a — Fusionner la définition de « visible » ⚠️ avant le lot 4

`findActiveForMap` redéclare localement les cinq conditions dans
`visiblePromoConditions` (`promo.service.ts:681-691`) alors que le commentaire de
`:186-196` proclame que `applyVisibleConditions` est « l'unique définition ».
Duplication règle 30 **préexistante**, sans rapport avec la bascule — mais A5 exige d'y
ajouter une sixième condition, et on n'ajoute rien à une définition qui n'est pas la
seule.

**Aucun changement de comportement attendu.** C'est ce qui en fait un lot à part : il
se vérifie en constatant que **rien ne bouge** (mêmes promos visibles, même compte,
même carte). Livré et vérifié avant le lot 4.

### Lot 3 — L'app bascule sur position + rayon
Providers (`clientPositionProvider` avec un **drapeau d'origine distinct** — une
position GPS arrivant après coup doit reprendre la main sur le défaut, même précaution
que `map_screen.dart:198-223`), `promo_api`, écrans, et
**`invalidateAfterPositionChange(ref)`** — une fonction nommée, jamais six listes
recopiées (règle 37 ; seul équivalent existant : `invalidateAfterPromoChange`,
`commercant_providers.dart:54-57`).

🔑 **La séparation ③/④ (décision 12) est la contrainte d'architecture de ce lot.**
`clientPositionProvider` sert **le point enregistré**, jamais la lecture du capteur.
`userPositionProvider` (④) reste cantonné à deux usages **locaux** : centrer la carte,
et calculer les distances affichées. **Aucun chemin de code ne doit permettre à ④
d'alimenter une requête réseau**, et le passage de ④ à ③ n'existe que par un geste
explicite de l'utilisateur — jamais par effet de bord. C'est cet invariant, et lui
seul, qui rend vraies les trois affirmations légales préservées en A2.

**La porte de consentement (décision 10) est dans ce lot.** Ce n'est pas un écran de
plus, c'est une **condition à l'émission** : tant que le consentement n'est pas donné,
`PromoApi.listActive` **n'émet ni `latitude` ni `longitude`**. La règle vit **à un
seul endroit** (règle 30). Le **retrait** du consentement doit être testé autant que
l'octroi.

**Et l'écran qui permet d'enregistrer le point** (décision 12) : le client le choisit
**sur la carte**, ce qui est cohérent avec la décision 6 — pas de recherche par nom,
donc pas de géocodeur. Le libellé doit dire ce que c'est : *« les promos autour de ce
point »*, jamais *« ma position »*, qui ferait croire à une capture.

⚠️ **Ne pas confondre avec la permission GPS du système.** Le consentement porte sur
la **transmission** ; la permission sur l'**accès au capteur**. Et l'invitation à
activer la localisation reste **contextuelle, sur la carte** (`map_screen.dart:396-416`,
`:836`) — c'est ce placement qui a levé le refus App Store 5.1.1(iv).

⚠️ **Mais la liste devient la surface géographique principale et n'a aucune
invitation.** Un client qui n'ouvre jamais la carte reste indéfiniment sur la position
par défaut sans qu'on lui propose mieux. `location_invite_store.dart` est conservé :
**décider où le brancher dans la liste**, sans rejouer le motif du refus store.

**Suppressions** (règle 31) : `commune_selection_screen.dart`, route `/select-commune`
(`router.dart:78-79`), `selected_commune_store.dart` et son provider,
`selectedCommunesProvider` / `selectedCommuneLabelProvider` / `kMaxSelectedCommunes`
(`commune_providers.dart:13,33-75`), `_NoCommuneSelected` et le sélecteur-titre
(`promo_list_screen.dart:200-241`, `:375-401`), le **bloc de redirection mort**
(`router.dart:339-368`) avec son import `// ignore: unused_import` (`:35`),
`test/features/client/selection_effective_test.dart`,
`integration_test/parcours_selection_commune_test.dart`.

🔴 **L'onboarding client casse en silence si on se contente de supprimer l'écran.**
`role_choice_screen.dart:29` fait `context.go('/onboarding/location')`, et pour le
client `markCompleted()` **n'est appelé que dans** `requestLocationAndFinish` /
`skipLocationAndFinish` (`onboarding_navigation.dart:37` et `:46`). Supprimer l'écran
et la route (`router.dart:86-87`) sans réécrire `role_choice_screen` produit soit une
route morte, soit **un onboarding qui revient à chaque lancement**
(`splash_screen.dart:82-83` relit `isCompleted()`). ⇒ `role_choice_screen.dart` et
`splash_screen.dart` sont **dans ce lot**.

**Ne pas supprimer** : §4.3, `location_providers.dart`, `location_invite_store.dart`,
`location_capture_field.dart`, `commune_cascade_field.dart`, `commune_filter_bar.dart`,
`commune_api.dart`.

**`.arb`** (règle 27, trois fichiers, même commit) — la vingtaine de clés du §5.8.

**Même commit — les tests qui rougiraient sur un produit correct** (règle 38) :
`parcours_carte_test.dart:62`, `parcours_client_liste_fiche_test.dart:79`,
`parcours_signalement_test.dart:72`, **`parcours_premier_lancement_test.dart:87-107`**
(il assert `Icons.location_on_outlined` et le « Continuer » de l'écran supprimé — et
c'est le parcours corrigé après le refus App Store, `status_v0.1.md:848-851`), et
**`integration_test/harness.dart`** (`TEST_COMMUNE_ID:84`, `TEST_WILAYA_NOM`/
`TEST_COMMUNE_NOM:93-94`), qui est le point commun de toute la suite. Également
impactés : `parcours_agent_creation_commercant_test.dart:136-146`,
`parcours_inscription_commercant_test.dart:35,104-124`, `parcours_espace_pro_test.dart:19`.

⚠️ Les parcours qui posent `selected_commune_ids` **directement en prefs**
continueraient de **passer** après la suppression : une assertion qui ne mesure plus
rien (règle 28).

**Portent aussi** : la cascade unique d'A4 (et la suppression de `_fallbackCenter`), le
repli « Top promos » re-scopé par rayon (A6), **les favoris interrogés par identifiants
sans filtre géographique** (R7), **l'ajout à la politique de confidentialité** (A2.3) et
le retrait de « quartier pilote (Djelfa) » de `legalCguContent` (A2.4).

⚠️ **Ne jamais précéder le lot 2** (§5.3).

### Lot 4 — Le blocage de publication ⚠️ un seul commit, non sécable
`ErrorCode.COMMERCANT_POSITION_REQUIRED` (`error-code.enum.ts`, section `// Commercant`
`:62`) + `CommercantService.assertPositionSet` (après `assertProfileValidated`,
`commercant.service.ts:719`, test `=== null` §5.10) + **ses deux appels aux deux mêmes
endroits que ses voisines** : `promo.service.ts:475` (**dans** `if (!dto.asDraft)`,
§5.9) et `:554` + les **trois** `features/shared/errors/error_messages_{fr,en,ar}.dart`
(règle 26 — `check_error_codes.dart` refusera sinon) + les chaînes `.arb` (règle 27) +
la route de correction et **son écran appelant** (règles 11, 31) + **les 9 sites de
`scripts/lib/`** (§5.5) + **les deux écrans de création** (§5.11) + le banc qui prouve
le refus (§9).

⚠️ Le message **ne doit interpoler aucune valeur**, sans quoi il rejoindrait les
exclusions de `check_error_codes.dart:56-70` — non traduites, donc affichées en
français à un arabophone.

⚠️ Les gardes s'appliquent **aussi** à `trustedActor` : seuls les plafonds anti-abus
sont exemptés (`:493`, `:509`, `:546`). L'écran agent doit afficher le message.

**Porte aussi §5.11** : la position devient **obligatoire sur l'écran de création par
l'agent** (`create_commercant_screen.dart:149`) — c'est ce qui tarit la source, là où la
route de A1 ne fait qu'écoper. L'auto-inscription reste inchangée.

⚠️ **Exige le lot 2a livré** (A5).

### Lot 5 — Retrait de `GET /promo/map/center`
Sa seule raison d'être est écrite en toutes lettres (`promo.service.ts:763-764`).
Avec une position par défaut, ce cas n'existe plus (règle 31).

Route (`promo.controller.ts:166-174`) + `findMapCenterForCommunes` (`:762-839`) +
`MapCenterQueryDto` + `PromoApi.fetchMapCenter` (`promo_api.dart:145-159`) +
`mapCenterForCommunesProvider` (`map_providers.dart:70-80`) + `map_screen.dart:189`,
`:203-223` + **dépinglage `frontiere_http.py:68-70`**.

⚠️ **`frontiere_http.py` n'échoue pas sur une route épinglée disparue** : `:399-406`
sort en `exit(1)` sur une route ouverte **non épinglée**, mais `:408-413` se contente
d'un **avertissement** dans l'autre sens. Une route fantôme y resterait sans qu'aucun
verdict ne rougisse — **le dépinglage doit être dans ce commit**, rien ne le
rattrapera.

⚠️ **`test-parcours-ecran.sh:216-295` se RÉÉCRIT, ne se supprime pas** : le bloc ne lit
pas seulement le centre, il en **dérive la bbox** (`:247-250`) puis sonde `/promo/map`
et choisit un commerce à remise unique. Le supprimer supprimerait tout le parcours
carte.

🔴 **Et ce lot retire le seul contrôle qui prouve que le décor a des coordonnées** :
`provision-decor.sh:405-414` interroge `GET /promo/map/center` précisément parce que,
dixit le script, « vérifier qu'on a envoyé le point n'aurait rien prouvé ». Il
disparaît **au moment où le lot 4 rend la position bloquante**. ⇒ Un remplaçant doit
être prévu **dans ce lot**, pas plus tard.

Note : ce travail a été livré et vérifié en base le 2026-08-05
(`status_v0.1.md:2054-2080`). Le retirer est une décision, pas un nettoyage.

### Lot 6 — Fusion des trois filtres wilaya
Il y en a **trois** : `commercant.service.ts:556-563`, `promo.service.ts:872-879`,
`report.service.ts:183-189`. `admin/moderation.service.ts:33` déclare le type et `:45`
transmet le filtre — aucun SQL. S'y ajoutent trois DTO déclarant `wilaya?`.

Ils **ne disparaissent pas** : filtres admin/agent avec appelants réels
(`commune_filter_bar.dart` → `admin_commercants_screen.dart:195`,
`admin_promos_screen.dart:103`, `moderation_queue_screen.dart:86`).

⚠️ **Les trois ne joignent pas de la même façon** : les deux premiers par relation
(`.innerJoin('commercant.commune', 'commune')`), le troisième **par entité**
(`.innerJoin(Commune, 'commune', 'commune.id = commercant.communeId')`), parce que
`commercant` y est lui-même une jointure d'entité (`report.service.ts:169-173`). La
forme par entité fonctionne dans les trois cas ⇒ **c'est celle du helper**.

⚠️ *La première version affirmait que la forme par relation « casse le troisième » et
que l'alias `'commune'` y était « déjà occupé ». Les deux sont faux* : `'commune'`
n'apparaît dans `report.service.ts` qu'aux lignes `186-188`, et l'alias `commercant` y
est enregistré avec ses métadonnées d'entité, donc la forme par relation se résoudrait
probablement. Adopter la forme par entité reste le bon choix — par uniformité, pas par
nécessité.

Ce que la règle 30 **interdit ici** : écrire « même filtre que
`CommercantService.findAllForAdmin` » et s'arrêter là.

### Lot 7 — Documentation (règle 23)
`docs/SPECS_ECHANGO_PROMO_V0.md` : **§3.1 à partir de la l. 38** (« Sélection de ville
par défaut : demandée au premier lancement » — c'est *elle* que la décision 3 rend
fausse) **et jusqu'à la l. 42** (« filtrée par les communes sélectionnées ») ; §3.2
(l. 104-109) ; §5.2 (l. 210-**218**). *La l. 221 (§5.3) citée dans la première version
concerne le plafond de promos et n'a aucun rapport géographique — retirée.*

Puis `docs/ARCHITECTURE.md`, `docs/status_v0.1.md` (journal daté), et **la règle 33 de
`CLAUDE.md`, périmée sur son décompte** : il y a **15** routes ouvertes, pas 14
(`frontiere_http.py:60` et son dictionnaire `:64-83` ; `status_v0.1.md:2055`). Après
le retrait du lot 5 et l'ajout de la route de configuration du lot 1, on reste à 15 —
et la règle redeviendrait juste **par accident**, le pire état pour une documentation.

### Lot 8 — Conformité store (A2.3) — hors chemin critique, avant soumission
Ne bloque aucune ligne de code, **bloque la mise en ligne**.

- **Google Play « Sécurité des données »** et **App Store « Confidentialité »** : passer
  de « localisation non collectée » à « localisation approximative, **fournie par
  l'utilisateur**, usage fonctionnel, non partagée, pas de suivi ». ⚠️ **Ne pas déclarer
  la position du capteur ④** — elle ne quitte pas l'appareil, et la déclarer serait faux.
- **`PrivacyInfo.xcprivacy`** : **absent** de `apps/mobile/ios`, obligatoire côté Apple.
- **`InfoPlist.strings`** : **absent** — `NSLocationWhenInUseUsageDescription` est en
  français seul dans une app trilingue.
- ⚠️ **Ne pas réécrire `Info.plist:48-49`** : la décision 12 la laisse vraie (§2.1).

---

## 8. Ce qui doit impérativement partager un commit

| Ensemble | Règle |
|---|---|
| `ErrorCode` ↔ les 3 `error_messages_*.dart` | 26 |
| Toute chaîne d'UI ↔ les 3 `.arb` | 27 |
| Nouvelle route ↔ son écran appelant | 11, 31 |
| Clé `.env` ↔ les 2 `.env.example` ↔ la mention du `.env` WSL | 36 |
| Blocage serveur ↔ les décors et bancs qui le déclencheraient à tort | 38 |
| Retrait de route ↔ dépinglage `frontiere_http.py` | 33 |
| Suppression d'écran ↔ la navigation qui y mène et l'état qu'il posait | 31 |
| `@Index()` ↔ sa migration ↔ un `migration:generate` **vide** | 12 |
| Doc ↔ le changement qu'elle décrit | 23 |

---

## 9. Plan de vérification

### 9.1 Le banc du blocage de publication

⚠️ **La première version de ce plan ne pouvait pas prouver ce qu'elle prétendait
prouver.** Elle prescrivait « retirer la position » — or le seul chemin est
`PATCH /commercant/me`, qui allume `profilePendingReview` : l'étape suivante aurait
constaté un `403 COMMERCANT_PROFILE_PENDING_REVIEW`, **jamais**
`COMMERCANT_POSITION_REQUIRED`. Un banc n'assertant que « 403 » aurait été **vert pour
la mauvaise raison** (règles 28 et 38).

**Séquence corrigée :**

1. **Un commerçant AVEC position publie** — établit que la publication *pouvait*
   aboutir. Sans cette étape, l'échec de l'étape 3 ne mesure rien (règle 38).
2. **Un commerçant CRÉÉ sans position** (via `POST /agent/commercant`, pas par
   retrait a posteriori) tente de publier.
3. Constater le **403 avec le code `COMMERCANT_POSITION_REQUIRED` explicitement
   asserté** — jamais le seul statut.
4. Constater que « enregistrer en brouillon » **passe toujours** — sinon on aura
   refabriqué la régression de `promo.service.ts:467-472`.
5. Poser la position par la route de A1, et constater que la publication passe **sans
   validation admin intermédiaire**.

⚠️ **Mesurer au plus près du geste**, jamais en préambule : les six échecs du rejeu du
2026-08-05 venaient de références lues au démarrage pendant que d'autres parcours
modifiaient l'état.

### 9.2 Le banc du rayon

`scripts/lib/client_liste.py` est à réécrire (aucun paramètre géo aujourd'hui). Il doit
éprouver :

- une promo **dedans** et une promo **dehors** ;
- l'**ordre** du tri ;
- ⚠️ **un point dans le carré mais hors du cercle** — c'est le « rognage des coins »
  du §6, et c'est le seul cas qui distingue une bbox d'un rayon. Sans lui, une
  implémentation qui oublie le rognage rend vert.

Le plafond de carte doit continuer d'être **déduit de la réponse**, jamais recopié
(`client_carte.py:184-186`).

### 9.3 La porte de consentement — le contrôle le plus difficile du chantier

Ce qu'il faut prouver est une **absence** : qu'aucune coordonnée ne quitte l'appareil
avant le consentement.

- **Le serveur ne peut pas en témoigner.** Il ne voit que ce qu'il reçoit ; il ne
  distinguera jamais « l'app n'a rien envoyé » de « l'app n'a pas été utilisée ». Un
  banc HTTP est **structurellement incapable** de vérifier ce point — l'écrire quand
  même produirait un contrôle qui rassure sans rien mesurer (règle 28).
- Le seul contrôle valide est un **parcours d'intégration Flutter avec un intercepteur
  sur les requêtes sortantes**, affirmant l'absence de `latitude`/`longitude` tant que
  le consentement n'est pas donné, puis leur **présence** après, puis leur **absence à
  nouveau** après retrait.

🔑 **Et un second contrôle, plus fort, que la décision 12 rend possible** : vérifier
que **la valeur émise est le point enregistré ③ et jamais la position du capteur ④**.
C'est l'invariant sur lequel reposent les trois « ✅ » de A2 et les deux fiches store.
En pratique : accorder la permission GPS, se placer à des coordonnées **différentes**
du point enregistré, et affirmer que la requête porte **le point enregistré**. Un test
où les deux valeurs coïncident ne mesure rien (règle 28 — l'assertion qui se vérifie
elle-même).

⚠️ Il doit **prouver qu'il sait refuser** : retirer la porte dans le code doit le faire
rougir. ⚠️ Et « pas de coordonnées dans la requête » est trivialement vrai si aucune
requête n'est partie : le parcours doit d'abord établir qu'un `GET /promo` **a bien eu
lieu**.

### 9.4 Vérificateurs

`tool/` contient **cinq** fichiers ; `check_all.dart` en lance quatre tout en annonçant
« les trois vérificateurs » dans son propre doc-commentaire (à corriger, règle 23).

| Vérificateur | Impact |
|---|---|
| `check_error_codes.dart` | **Rougit dès l'ajout de l'`ErrorCode`** — c'est son rôle. Auto-test `:186-260` (**9 refus sur 17 cas**), mode `--mutation` en **`:262-281`** |
| `check_enums.dart` | ⚠️ **Impact non nul si R3 est appliqué** : `:98-103` apparie `NotificationType` (`notification.entity.ts:25-33`) avec son miroir Dart (`domain/models/notification.dart:5`). Un type de notification en plus le fait rougir, plus la clé `.arb` du libellé |
| `check_theme.dart` | Tout **nouvel** écran posant un neutre ou un hexa au-dessus des tuiles devra être épinglé **avec sa raison** — table `_epingles` en `:92-103`, refus d'une raison vide en `:207-209` |
| `check_server_rules.dart` | §5.7 — ne rien lui donner à lire |

🔴 **Angle mort : aucun vérificateur ne couvre les `.arb`, les routes, ni les
providers**, et `l10n.yaml` n'a pas de mode strict. Une clé retirée de `app_fr.arb` mais
laissée dans `_en`/`_ar` (ou l'inverse) ne fait échouer **rien**. Sur un lot 3 qui
touche une vingtaine de clés dans trois fichiers, c'est le défaut le plus probable du
chantier.

### 9.5 Un parcours qui revient (règle 37)

Changer la position, revenir sur la liste, vérifier qu'elle a suivi. **Aucun test hors
appareil ne voit ce défaut.**

---

## 10. Risques assumés

| # | Risque | Conséquence concrète | Atténuation |
|---|---|---|---|
| R1 | Navigation sans recherche (décision 6) | Pour voir Oran depuis Alger : plusieurs dézooms, un panoramique, un rezoom (`map_screen.dart:27` `_initialZoom = 13.0`, `:249` `minZoom: 5`) | La position par défaut est **enregistrée** : le coût est payé une fois. Ajouter le symétrique de `mapTooManyShops` — « aucun commerce ici, déplacez la carte » : un dézoom sur zone vide ne doit pas être indiscernable d'une panne |
| R2 | Aucun nom de lieu (décision 7) | Dans une liste triée par distance, le client saura **à quelle distance**, jamais **où** | Trois conditions, sans géocodeur : (1) la **distance** doit apparaître sur la carte de liste — `PromoCard` ne l'affiche pas ; (2) le **nom du commerce** doit remonter dans la grille et la mosaïque — `promo_card.dart:125` l'affiche bien, mais `promo_grid_card.dart:20` et `:130` non ; (3) conserver le champ adresse. ⚠️ *La première version réclamait un « voir sur la carte » depuis la fiche : **il existe déjà** (`promo_detail_screen.dart:696-701`, bouton Itinéraire, specs l. 43). Et elle proposait d'enrichir « le lien profond partagé » : **il n'y en a aucun** — `:57-59` dit « pas de lien profond », et `/p/:id` ne montre jamais la promo (`app-links.controller.ts:88-93`). Ce serait un lot à créer.* |
| R3 | Extinction sans préavis (décision 8) | Un commerçant qui publiait hier ne publie plus, ses promos sortent du public, **et il ne le sait pas**. ⚠️ *Correction : ses compteurs de vues ne « tombent pas à zéro » — `viewCount` est cumulatif et `totalPromoViews` (`commercant_providers.dart:61-62`) somme `GET /promo/me/all`, non filtré par la visibilité publique. Le total **cesse de croître**. Symptôme moins spectaculaire, plus insidieux.* | **Le canal existe** : `NotificationService` est branché et le tableau de bord affiche les alertes non lues en premier plan (`commercant_dashboard_screen.dart:146`, `:647`). Un type de plus à côté de `PROMO_EXPIRING_SOON`, envoyé **avant** le jour J. ⚠️ Coût caché : fait rougir `check_enums.dart` (§9.4) |
| R4 | Perte du multi-zone | Le client suivait jusqu'à 4 communes accolées (décision produit du 2026-07-12, motivée par les grandes villes) | Le rayon est réglable ; à surveiller sur Alger |
| R5 | Trois portes fermées avant la première promo | Registre, revue de profil, **et maintenant position**. Risque d'abandon, découvert au dernier geste | Bannière **permanente** + FAB désactivé avec libellé explicatif — les deux mécanismes existent (`_AlertBox:934`, cas `atCap` `:181-207`, déjà paramétré par `capReachedLabel(slots.plafond)`). Formuler ce qu'il **perd**. Le message doit **différer** de `COMMERCANT_PROFILE_PENDING_REVIEW` |
| R6 | Produit hybride | Géographique pour le client, administratif pour l'agent et l'admin | Assumé. À revoir quand le rôle agent disparaîtra |
| R7 | **L'onglet Favoris devient trompeur** | Le filtre favoris est **purement local**, appliqué aux pages déjà chargées (`promo_providers.dart:224-225`, `:248-254`). Un favori posé sur un commerce **à 8 km disparaît de l'onglet sans un mot** — aujourd'hui la fenêtre est de 4 communes, demain de 5 km | ✅ **TRANCHÉ : les favoris interrogent le serveur par identifiants, sans aucun filtre géographique.** Un favori est un choix explicite de l'utilisateur : rien ne justifie qu'une règle de proximité le lui retire. Et un élément qui disparaît sans erreur ni message est exactement la classe de défaut que ce projet traque. **Dans le lot 3** |
| R8 | **La recherche textuelle rétrécit** | `searchQueryProvider` part au backend (`promo_providers.dart:21-24`, `promo.service.ts:620-628`, ILIKE sur description + nom du commerce) : son périmètre passerait de 4 communes à 5 km, **sans recours** puisque la décision 6 interdit toute recherche de lieu | ✅ **TRANCHÉ : dès qu'un terme de recherche est présent, le rayon ne s'applique plus** — la recherche est nationale, **triée par distance**. Chercher est un acte intentionnel avec une cible ; le tri met de toute façon les résultats proches en tête. Aucune clé de configuration en plus, aucune constante arbitraire. ⚠️ Impose que la pagination reste stable (§5.4) et que `ILIKE` tienne le volume — `promo.service.ts:619` prévoit déjà `pg_trgm` « avant l'extension multi-wilaya » |

**Une phrase à ne pas écrire** : « position obligatoire ». Elle décrit la règle, pas
l'enjeu, et n'explique rien.

---

## 11. Corrections apportées par la relecture adversariale

Consigné pour que personne ne réintroduise une affirmation écartée.

| Affirmation initiale | Réalité |
|---|---|
| `applyVisibleConditions` est l'unique définition de « visible » | `findActiveForMap` la redéclare (`promo.service.ts:681-691`) — duplication règle 30 préexistante |
| A5 : recommander (ii) | (ii) refabrique le défaut fondateur documenté en `:1292-1295`. Recommandation inversée |
| Piège `NaN` sur champ absent | N'existe pas. Le vrai piège est `?latitude=` vide → `0` |
| « 8 sites », « sept bancs » | **9 sites**, 5 fichiers, 5 bancs |
| `provision-decor.sh` ne pose pas les coordonnées | Il les pose depuis `aa7154a` (`:257`). `seed-demo.sh:207-214` aussi |
| L'alias `'commune'` est occupé dans `report.service.ts` | Non — il n'y apparaît qu'en `:186-188` |
| « les 5 clés existantes » de `configNumber` | **7** appels |
| `:399-406` / `:408-413` dans `provision-decor.sh` | Dans **`frontiere_http.py`** |
| `test-parcours-ecran.sh:216-295` à supprimer | À **réécrire** — il dérive la bbox |
| `PromoCard` n'affiche pas le nom du commerce | Il l'affiche (`:125`). C'est `promo_grid_card.dart` |
| « voir sur la carte » à créer | Existe (`promo_detail_screen.dart:696-701`) |
| Enrichir le lien profond partagé | Il n'y en a aucun |
| Les compteurs de vues tombent à zéro | Ils cessent de croître |
| `check_enums.dart` : impact nul | Rougit si R3 est appliqué |
| « 15 modules `scripts/lib` », « 9 parcours » | **32** fichiers `.py`, **11** parcours |
| Dérives de lignes | `check_server_rules:123-128` · `check_theme:92-103` et `:207-209` · `check_error_codes:262-281` · `status_v0.1.md:2055` · `maxCommunesHint:352-359` · `moderation.service.ts:45` · SPECS §3.1 dès la l. 38, §5.2 jusqu'à la l. 218, §5.3 retirée |

---

## 12. Ce qui n'a pas été mesuré

**Ces points ne sont pas des détails** : le premier dimensionne à lui seul A1.

- 🔴 **Combien de commerçants sont sans position en base.** C'est la portée exacte de la
  décision 8, et **la seule mesure dont dépende encore un choix** : elle dit si la
  régularisation du parc est une campagne ou trois appels téléphoniques.
  ⇒ `SELECT count(*) FILTER (WHERE latitude IS NULL) AS sans_position, count(*) AS total
  FROM commercant WHERE "deletedAt" IS NULL;` — sur le conteneur Postgres du clone WSL,
  **avant le lot 4**, résultat consigné dans `status_v0.1.md`. Tant qu'elle n'est pas
  faite, « leurs promos deviennent invisibles » est une phrase, pas une mesure.
- **Combien ont renseigné une adresse texte** — décide si le filet de R2 vaut quelque
  chose.
- **Que `class-transformer` n'appelle pas le `@Transform` d'une clé absente** (§5.2) —
  établi par lecture de la bibliothèque, pas par exécution. À confirmer par un cas de
  banc avant de traiter le §5.2 comme acquis.
- **Que la forme de jointure par relation fonctionne dans `report.service.ts`** (lot 6)
  — non vérifiable sans exécution.
- **Que la pagination TypeORM encaisse un `addSelect` haversine** — inféré de `DISCOUNT`.
- **Que `cube`/`earthdistance` soient disponibles dans `postgres:16-alpine`** — sans
  objet si l'option A est retenue. Certain : **aucun `CREATE EXTENSION` n'existe dans le
  dépôt.**
- **La répartition des communes suivies par les clients** — stockage local, aucune
  télémétrie (R4).
- **Aucun build, test, banc ni `migration:generate` n'a été lancé.**
