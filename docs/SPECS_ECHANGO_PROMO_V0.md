# Spécifications fonctionnelles — echango Promo (V0 / Pilote Djelfa)

**Statut** : Draft V0 — pour cadrage technique (Claude Code)
**Écosystème** : module de la suite echango (echango, echango POS, echango Pay)
**Domaine** : echango.com — sous-domaine dédié disponible (ex. `promo.echango.com`)

---

## 1. Contexte & objectif

Application mobile mettant en relation commerçants et clients autour des promotions commerciales, en Algérie. Pilote lancé sur **un seul quartier de Djelfa** avant extension à d'autres quartiers, communes, puis wilayas.

**Principe central** : le contenu (promos) est initialement produit par un **agent terrain** qui visite physiquement les commerçants, afin de résoudre le problème classique d'amorçage des marketplaces biface (cold-start problem) — le client trouve du contenu dès le premier jour, sans attendre que les commerçants s'inscrivent eux-mêmes.

**Modèle économique** :
- Gratuit pour les commerçants et les clients en V0.
- Monétisation prévue plus tard, une fois la masse critique atteinte : publicité ciblée / mise en avant payante, à l'ouverture vers d'autres wilayas. **Hors périmètre V0.**

---

## 2. Acteurs

| Acteur | Compte requis | Créé par |
|---|---|---|
| Client | Non | — |
| Commerçant | Oui (transitoire → autonome) | Agent (V0), auto-inscription (phase 2) |
| Agent terrain | Oui | Admin |
| Admin / Modérateur | Oui | (bootstrap manuel) |

---

## 3. Spécifications par acteur

### 3.1 Client

- **Pas d'inscription.** Aucune donnée personnelle collectée.
- **Identifiant device anonyme** généré à l'installation, stocké localement, utilisé uniquement pour la limitation des signalements (voir §5.4). Ce n'est pas un compte.
- **Point de recherche enregistré par le client (bascule 2026-08-12)** — remplace la sélection de ville et de communes. Le client choisit un point sur la carte, ou s'y centre via le GPS puis l'enregistre ; les promos affichées sont celles des commerces dans un rayon autour de **ce point**. Rien ne l'oblige à être son domicile ni l'endroit où il se trouve.
  - **Aucune permission n'est requise pour chercher.** Sans point enregistré, le serveur cadre sur son propre défaut (`GET /promo/config`) et l'accueil le dit — un bandeau non masquable, parce qu'une liste pleine et plausible autour d'un lieu qui n'est pas le sien est plus trompeuse qu'un écran vide.
  - **Le geste d'enregistrement vaut consentement** : c'est à ce moment, et pas après, que le client apprend que le point part au service. Il se retire depuis la carte, ce qui efface le point avec lui.
  - Le GPS, s'il est autorisé, sert **uniquement** à centrer la carte et à afficher les distances, **sur l'appareil**. Il ne franchit la frontière que par un enregistrement explicite.
  - **Ce qui a disparu avec la commune** : le multi-zone (jusqu'à 4 communes, décision du 2026-07-12) et le nom de lieu affiché en tête de l'accueil — sans géocodeur, l'app ne sait pas comment s'appelle l'endroit visé, et un nom approché serait pire que pas de nom.
- **Liste des promos actives**, cadrée par le point et un rayon (défaut 5 km, `CLIENT_DEFAULT_RADIUS_KM`), triée par distance. Une **recherche textuelle ignore le rayon** : chercher est un acte intentionnel avec une cible.
- **Filtre par catégorie** (liste fixe, voir §5.6).
- **Fiche promo** : jusqu'à 3 photos (2026-07-12 — une seule ne suffit pas à juger un produit, carousel swipeable si plusieurs), produit, prix avant/après, nom, adresse et téléphone du commerçant (numéro tap-pour-appeler, ajout 2026-07-12 — déjà renvoyé par l'API publique mais jamais affiché jusqu'ici), date de fin de validité. Si le commerçant a renseigné une photo de son commerce et/ou une position GPS, la fiche affiche aussi la photo du commerce et un bouton "Itinéraire" qui ouvre l'app Google Maps (lien simple, pas d'intégration payante).
- **Signalement** "promo expirée / incorrecte" : action sans compte, limitée par device ID (voir §5.4). Objectif : limiter les abus côté commerçant autant que côté client.
- **Recherche par catégorie** : sélection parmi la liste fermée de catégories (§5.6), pas de saisie libre. C'est une recherche guidée, pas un moteur de recherche texte.
- **Favoris promo** (corrigé le 2026-07-12 — cette section disait à tort "favoris commerçant", ce qui a d'ailleurs causé une régression lors d'un audit qui a aligné le code sur ce texte au lieu du comportement réel voulu) : le client peut marquer une promo précise en favori, stocké **en local sur l'appareil** (pas de compte, cohérent avec le reste du parcours client) par id de promo. Affiche les promos favorites en priorité dans la liste. Une promo republiée obtient un nouvel id et n'est donc pas favorite automatiquement — comportement accepté (favori = "j'aime cette offre précise", pas un abonnement au commerçant). Sans notifications push (phase 2), c'est un raccourci d'affichage, pas une alerte proactive.
- **Hors V0 (phase 2)** : recherche par mot-clé/produit en texte libre, notifications push géolocalisées.

### 3.2 Commerçant

**Deux voies de création de compte, disponibles toutes les deux dès la V0** :

1. **Auto-inscription** — le commerçant s'inscrit lui-même dans l'app, sans passage d'agent requis. L'agent existe pour **assister** les commerçants peu à l'aise avec le digital ou pour démarcher activement, mais n'est plus une condition d'accès.
2. **Création assistée par l'agent** — l'agent crée la fiche lors de sa visite terrain (utile pour aller chercher activement les commerçants qui n'auraient pas spontanément téléchargé l'app).

**Authentification — téléphone + code PIN, sans SMS** (décision produit :
le SMS est jugé inutile et coûteux pour ce marché, aucune vérification de
possession du numéro n'est effectuée) :

1. Saisie du numéro de téléphone (auto-inscription) ou saisie par l'agent (création assistée).
2. Définition d'un **code PIN** (6-12 chiffres, relevé de 4-6 le 2026-07-13 — voir encart sécurité ci-dessous) par le commerçant à l'inscription, ou **choisi par l'agent et transmis en personne** pour un compte créé par l'agent.
3. Connexions suivantes : téléphone + PIN.
4. **Changement de PIN** : deux cas bien distincts.
   - **Le commerçant connaît encore son PIN actuel** et veut le changer — **libre-service**, depuis son profil dans l'app (`PATCH /commercant/me/pin`, ancien + nouveau PIN, l'ancien faisant office de preuve d'identité). Pas besoin d'agent ni d'admin.
   - **PIN vraiment oublié** (l'ancien est inconnu) — seul cas qui passe par un admin/agent : après avoir identifié l'appelant pendant la conversation, il fixe directement un nouveau PIN et le communique par téléphone, même mécanisme que la création par agent.

> **Fermeture de faille (2026-07-13)** : jusqu'ici, un compte créé par un agent restait `créé_agent` (PIN non défini) jusqu'à ce que le commerçant le revendique lui-même via `POST /commercant/claim`, un endpoint public ne demandant que le numéro de téléphone — **n'importe qui connaissant ce numéro (souvent public : enseigne, carte de visite) pouvait donc revendiquer le compte avant le vrai commerçant**, avec le même risque à chaque réinitialisation de PIN par un admin. L'endpoint `claim` est supprimé : l'agent choisit désormais le PIN en personne à la création (compte `autonome` dès le départ, plus d'état intermédiaire) ; le PIN vraiment oublié passe par un admin/agent qui le fixe directement, communiqué uniquement de vive voix (jamais par SMS, cohérent avec la décision "pas d'OTP") ; un simple changement de PIN connu reste, lui, libre-service. La longueur minimale du PIN est montée à 6 chiffres à cette occasion (ancien minimum de 4 jugé trop faible) ; la connexion et la vérification de l'ancien PIN restent permissives sur 4-12 chiffres pour ne pas invalider les PIN déjà fixés avant ce changement.

**Cycle de vie du compte** (états) :

```
créé_agent → autonome (historique uniquement — un compte créé par un agent est
              désormais autonome dès la création, voir encart ci-dessus ;
              `créé_agent` ne subsiste que sur d'éventuelles lignes antérieures
              au 2026-07-13, dont le PIN se fixe comme un PIN oublié ordinaire)
auto_inscrit → autonome (directement, dès la saisie du PIN à l'inscription)
```

- Un compte créé par l'agent est `autonome` dès la création (l'agent choisit et transmet le PIN en personne) — plus d'étape de revendication publique.
- Un compte auto-inscrit passe directement en `autonome` dès l'inscription — pas d'étape intermédiaire, car il n'y a pas de tiers (agent) à qui retirer la main.

**Niveaux de vérification (indépendants du cycle de vie du compte)** :

| Niveau | Condition | Effet |
|---|---|---|
| `auto_inscrit` | Inscription autonome — aucune vérification du numéro de téléphone | **Bloqué pour publier** tant que le registre n'est pas envoyé et validé par un admin (revert du 2026-07-11, voir ci-dessous) |
| `confirmé_agent` | Constaté physiquement par l'agent lors de sa visite | **Suffisant pour publier** — la visite de l'agent vaut vérification, jamais concerné par la validation du registre |

> **Revert du 2026-07-11** : la V0 avait explicitement choisi de ne jamais bloquer la publication sur le registre de commerce, pour ne pas exclure le commerce informel (décision d'origine conservée ci-dessous pour mémoire). Décision produit ultérieure : un commerçant auto-inscrit doit désormais envoyer une photo de son registre à l'inscription et attendre la validation d'un admin avant de pouvoir publier une promo (`CommercantService.assertRegistreValidated`, `ErrorCode.COMMERCANT_REGISTRE_NOT_VALIDATED`) — un commerçant confirmé par un agent n'est jamais concerné, la visite de l'agent vaut déjà vérification.
>
> Décision d'origine (V0, abandonnée) : *« ne pas exiger le registre de commerce pour publier, afin de ne pas exclure le commerce informel, très présent localement »* — le badge `vérifié_registre` était alors optionnel et jamais bloquant.
>
> **Conséquence résiduelle de l'auto-inscription et de l'absence de vérification téléphonique** : le registre validé filtre maintenant les faux comptes côté auto-inscription, mais ni le niveau `confirmé_agent` ni une preuve de possession du numéro de téléphone n'apportent cette garantie — un numéro usurpé peut techniquement créer un compte au nom d'un tiers. Le système de signalement/modération (§5.4) reste la ligne de défense pour ce cas résiduel.
>
> **Ajout du 2026-07-12** : toute modification ultérieure du profil (`PATCH /commercant/me` — nom, adresse, catégorie, photo, position) bloque à son tour la publication jusqu'à validation par un admin (`CommercantService.assertProfileValidated`, `ErrorCode.COMMERCANT_PROFILE_PENDING_REVIEW`, colonne `profilePendingReview`) — contrairement au blocage registre ci-dessus, celui-ci s'applique à **tous** les commerçants sans exception, y compris `confirmé_agent` : une fois le compte créé, toute modification repasse par un contrôle humain quelle que soit l'origine de vérification initiale. Pas de rejet symétrique au registre — l'admin valide ou suspend le compte, il n'y a pas de motif de refus dédié à saisir. À l'inscription d'un auto-inscrit, l'envoi de la photo boutique allume les deux blocages en même temps (registre + profil) — `resolveRegistreVerification` purge donc aussi `profilePendingReview`, pour qu'une seule validation admin couvre les deux au moment de l'inscription plutôt que d'exiger deux actions distinctes pour un même nouveau compte.

**Fiche commerçant — données saisies à la création** (auto-inscription ou
création agent) :
- **Position sur la carte** — capturée au GPS ou choisie sur la carte. C'est
  elle, et elle seule, qui décide où le commerce apparaît. Obligatoire à la
  création par un agent (il est sur place) ; à défaut exigée à la publication.
- **Adresse en texte libre, facultative** — purement indicative, jamais un
  critère de recherche géographique.
  ⚠️ Remplace la sélection **wilaya puis commune**, supprimée le 2026-08-13
  avec le découpage administratif tout entier.
- **Photo du commerce, optionnelle** — pour que les clients l'identifient
  facilement dans la liste/fiche (caméra ou galerie, contrairement à la
  photo de promo prise par l'agent qui est caméra uniquement).
- **Position GPS — facultative à l'inscription, mais OBLIGATOIRE pour publier**
  (2026-08-12). Sans elle, une promo n'est visible par personne : les clients
  cherchent par proximité et la carte filtre sur un cadre, qu'un `NULL` ne peut
  satisfaire. Publier serait un geste sans effet, et le tableau de bord
  annoncerait « 3 en ligne » sur un stock que personne ne voit.
  - Le **brouillon reste possible** sans position : c'est mettre en ligne qui
    exige un point, pas préparer.
  - **Obligatoire dès la création par un agent** (serveur et écran) : l'agent
    est physiquement dans le commerce, c'est la seule capture juste par
    construction. Mesuré le 2026-08-12 : 40 des 44 commerçants sans position
    venaient de cette route.
  - `PATCH /commercant/me/position` pose le point **sans** déclencher la revue
    de profil à la première pose — sinon le commerçant bloqué qui corrige se
    retrouverait bloqué une seconde fois, à attendre un admin.
  - L'adresse texte reste **optionnelle** et complémentaire : un point capté à
    l'intérieur d'un local dérive de 50 à 200 m, et ne dit pas « 2ᵉ étage ».
    Capturée via la localisation native (gratuit, aucune intégration Google Maps
    payante).
- **Confirmation du PIN** : ressaisie obligatoire à la définition du PIN
  (inscription ou activation d'un compte créé par un agent), pour éviter
  qu'une faute de frappe bloque le commerçant à la première connexion.

**Gestion des promos — cycle de vie éditorial** (indépendant du statut de
modération, voir §5.4 — CLAUDE.md règle 8) :

```
brouillon → publiée → arrêtée
              ↓
           expirée (auto, à dateFin)
```

- **Édition toujours possible**, quel que soit le statut (description,
  prix, catégorie, photo) — c'est la publication/republication qui
  constitue le "geste actif" ci-dessous, pas une restriction sur l'édition.
- **Brouillon** : la promo est créée et remplie mais pas visible côté
  client, et ne compte pas dans le plafond de 5.
- **Publication** (depuis brouillon, arrêtée ou expirée) : fixe une
  **date de fin obligatoire**, toujours recalculée à neuf (jamais une
  simple prolongation) — entre **1 et 7 jours**, 5 jours par défaut.
  Objectif inchangé : forcer un geste actif régulier du commerçant,
  garantir la fraîcheur du contenu. Compte dans le plafond de 5 actives.
- **Arrêt** : action volontaire du commerçant (ex. rupture de stock),
  disparaît immédiatement de la liste client et libère un slot sur le
  plafond de 5 — republication possible à tout moment (nouveau cycle
  complet, pas une reprise).
- **Expiration** : automatique à `dateFin` (tâche planifiée, §5.1),
  **disparaît de la liste client**. Republication complète requise pour
  réactiver, comme l'arrêt volontaire.
- Jusqu'à **5 promos "publiée" simultanément** par commerçant (brouillons
  et promos arrêtées/expirées illimités, hors plafond).

**Dashboard commerçant (statistiques)** — inclus dès la V0 :
- Nombre de vues sur la fiche commerçant.
- Nombre de vues par promo.
- **Comptage par device unique** (même identifiant device anonyme que celui utilisé côté anti-fraude signalement, §5.4), pas un compteur brut — évite qu'un rafraîchissement répété de la page gonfle artificiellement les chiffres.
- Objectif : donner une raison concrète au commerçant autonome de revenir régulièrement dans l'app, en plus de l'obligation de republication à expiration.

### 3.3 Agent terrain

- **Sans territoire — l'agent est GLOBAL depuis le 2026-08-13.** Il était
  rattaché à zéro, une ou plusieurs `Commune` (le concept de Zone opérationnelle
  séparée ayant été abandonné le 2026-07-09), et cette liste bornait tout ce
  qu'il pouvait voir et faire. Elle a disparu avec le découpage administratif.
  ⚠️ **Ce que ça retire, et que rien ne remplace à ce jour** : la garde
  d'appartenance de quatorze routes d'écriture, la partition du travail de
  modération (tous les agents voient la même file, les résolutions sont des
  écritures inconditionnelles), et le seul moyen dont l'admin disposait pour
  **restreindre** un agent — il n'existe plus de granularité entre « agent » et
  « admin moins deux écrans ».
  ⚠️ Le §7 de ce document prévoyait déjà la disparition du rôle agent « à
  l'extension multi-wilaya ». Cette décision crée exactement l'état décrit : la
  question de savoir si le rôle survit est ouverte, pas tranchée.
- Authentification **email + mot de passe**, compte créé exclusivement par l'Admin (pas d'auto-inscription agent).
- Crée une fiche commerçant (numéro de téléphone, nom, adresse, catégorie) + première promo.
- Prend la photo de la promo **obligatoirement dans l'app** (pas d'upload depuis la galerie), avec horodatage. **Pas de géolocalisation capturée** (décision explicite — écartée après discussion).
- Met à jour une promo existante sur un commerce déjà onboardé.
- N'a plus d'action à faire pour activer le compte du commerçant : celui-ci le fait lui-même, quand il le souhaite, en définissant son PIN sur l'écran de connexion (pas d'OTP à initier).
- **Pas de mode hors-ligne en V0** (décision explicite malgré la couverture réseau variable à Djelfa — voir §7, risque à surveiller pendant le pilote).
- **Agent = modérateur, mêmes écrans que l'admin** (décision produit
  2026-07-12) : dashboard, modération, liste de promos, liste/fiche
  commerçant (valider registre/profil, suspendre/réactiver, réinitialiser
  le PIN, créer une fiche commerçant) — un seul jeu d'écrans partagé. ⚠️ Ils
  étaient scopés aux communes de l'agent côté backend ; ils ne le sont plus
  depuis le 2026-08-13, agent et admin reçoivent **exactement les mêmes
  données**. Seules deux fonctionnalités restent réservées à l'admin : la
  gestion des agents et le journal d'audit — ce sont désormais **les seules
  choses qui distinguent les deux rôles**.
- **Liste "commerces de mes communes" avec statut de tournée (jamais
  visité/à jour/à relancer) retirée le 2026-07-12** — décision produit,
  jugée redondante avec la fiche commerçant unifiée ci-dessus. Le statut de
  tournée n'est plus calculé ni affiché nulle part dans le produit.

### 3.4 Admin / Modérateur

- Authentification **email + mot de passe**.
- **Un seul rôle en V0** (pas de séparation admin/modérateur pour le pilote — à réévaluer si recrutement d'un modérateur dédié).
- Gagne, depuis le 2026-07-12, la capacité de publier une promo pour un
  commerçant (même écran que l'agent) — en plus de ses capacités de
  modération/gestion déjà partagées avec l'agent (voir §3.3).
- Valide ou rejette le registre envoyé par un commerçant auto-inscrit — condition désormais bloquante pour que celui-ci puisse publier (§3.2).
- Traite la file de modération des promos signalées (masquer / valider en `vérifiée_ok` / avertir le commerçant).
- Crée et gère les comptes agents (création, réinitialisation de mot de passe,
  révocation de session).
  ⚠️ **Il ne leur assigne plus de territoire depuis le 2026-08-13**, et ne peut
  donc plus les restreindre : un agent créé a d'emblée les mêmes droits
  d'écriture que tous les autres, sur tout le parc. Il n'existe par ailleurs
  **aucune route de suppression d'agent** — seulement la révocation.
- ~~**Transfère des communes** d'un agent à un autre~~ — supprimé le
  2026-08-13. ⚠️ Ce geste répondait à un besoin réel — le départ d'un agent,
  pour que les fiches dont il s'occupait ne cessent pas d'être suivies **en
  silence** — et **rien ne le reprend**. Sans territoire la question ne se pose
  plus ; c'est la question inverse qui s'ouvre, celle de l'attribution du
  travail entre agents.
- **Réinitialise le PIN** d'un commerçant sur demande (seul recours en cas de PIN oublié, pas de flux libre-service — voir §3.2).
- Vue globale (dashboard) : nombre de commerces actifs, nombre de promos publiées, nombre de signalements en attente.

---

## 4. Entités de données (vue haut niveau)

> Détail des schémas/relations à faire dans une passe dédiée "modèle de données" — ceci n'est qu'un inventaire d'entités et de leurs statuts/cycles de vie, nécessaire pour cadrer le développement.

- ~~**Commune**~~ — référentiel administratif officiel (wilaya → commune).
  **Supprimé le 2026-08-13**, table comprise. Le lieu d'un commerce ne
  s'exprime plus que par sa **position** (qui décide de tout) et son
  **adresse** en texte libre (facultative, indicative).
- **Commerçant** — fiche + état de compte (`créé_agent` / `autonome`) + origine de vérification (`auto_inscrit` / `confirmé_agent`) + statut registre (`en_attente` / `validé` / `rejeté`, bloquant pour publier uniquement si `auto_inscrit`).
- **Promo** — liée à un commerçant, statut (`active` / `expirée` / `signalée` / `masquée` / `vérifiée_ok`), photo, prix avant/après, catégorie, date de fin, compteur de signalements.
- **Agent** — compte. Plus aucun territoire depuis le 2026-08-13.
- **Admin** — compte, rôle unique en V0.
- **Signalement (Report)** — device_id, promo_id, horodatage. Sert au calcul du seuil de modération.
- **Journal d'audit (AuditLog)** — trace les actions des agents (création et
  modification de fiche commerçant, **écritures de promo depuis le
  2026-08-13**) et de l'admin (réinitialisation de PIN, gestion des agents)
  avec identité + horodatage.
  ⚠️ **Il devient le seul contrepoids à la portée globale de l'agent**, et il
  ne suffit pas encore : il ne se filtre que par `actorType` et n'affiche que
  des UUID. Lisible pour un agent de commune, illisible pour un agent national.

---

## 5. Règles métier

### 5.1 Expiration des promos
Tâche planifiée (cron, ex. quotidienne) qui bascule automatiquement les promos ayant dépassé leur date de fin vers le statut `expirée`. Aucune action utilisateur ne déclenche ce changement — c'est un point critique à ne pas oublier en développement, sans quoi l'objectif de fraîcheur du contenu est compromis silencieusement.

### 5.2 Le lieu — une position, et rien d'autre

⚠️ **Cette section s'appelait « Commune — territoire agent et admin ». Le
découpage administratif a été supprimé le 2026-08-13**, en trois temps :

1. **2026-07-09** — le découpage opérationnel interne « Zone » est abandonné au
   profit d'un rattachement direct de l'agent à des communes.
2. **2026-08-12** — la commune cesse d'être l'ancrage du **client** : celui-ci
   enregistre un point et cherche dans un rayon autour de lui (§3.1).
3. **2026-08-13** — la commune disparaît entièrement : elle n'était plus que la
   frontière d'autorisation de l'agent et un filtre d'écrans admin.

**Ce qui reste, et qui suffit** :

- La **position** du commerce décide de tout — carte, liste au rayon,
  visibilité. Sans elle, un commerce n'existe pour aucun client, et la
  publication est refusée.
- L'**adresse** en texte libre est facultative et purement indicative. Elle
  n'est jamais un critère géographique ; elle sert à reconnaître une enseigne,
  et alimente la recherche texte des écrans admin.

**Ce que ça coûte, et qu'il faut savoir** : le produit n'a plus aucune notion
de territoire. Ni pour restreindre un agent, ni pour répartir le travail de
modération, ni pour dire à un client où il regarde — sans géocodeur, l'app ne
sait pas comment s'appelle l'endroit qu'elle affiche.

### 5.3 Plafond de promos actives
5 promos **publiées** maximum par commerçant, simultanément (voir §3.2 pour le cycle de vie brouillon/publiée/arrêtée). Tri par défaut à définir (proposition : date d'expiration la plus proche en premier) — **point encore ouvert**, à trancher lors du modèle de données/UX.

### 5.4 Anti-fraude sur les signalements
- Identifiant device anonyme généré à l'installation côté client (pas de compte).
- Maximum **1 signalement par device par promo**.
- Seuil de mise en file de modération : **3 devices distincts** ayant signalé la même promo.
- Résolution : si l'admin valide la promo comme légitime → statut `vérifiée_ok`, les signalements des **mêmes devices** sont ignorés pendant **30 jours** sur cette promo (de nouveaux devices peuvent toujours signaler si le problème réapparaît réellement, ex. promo devenue effectivement expirée).

### 5.5 Preuve de passage agent
Photo prise obligatoirement via l'appareil photo intégré à l'app (pas de sélection depuis la galerie), avec horodatage. Sert de preuve minimale que l'agent est passé sur place. Pas de géolocalisation associée (décision explicite).

### 5.6 Catégories (liste fermée, V0)
Liste fixe, pas de saisie libre par l'agent, pour éviter la fragmentation dès le premier jour :
1. Alimentation
2. **Restauration** — restaurants, fast-foods, salons de thé (**ajoutée le
   2026-07-30**, migration `1783830000000-AddCategorieRestauration`)
3. Vêtements / Textile
4. Électroménager
5. Beauté / Hygiène
6. Maison / Ameublement
7. Autre

**L'ordre de cette liste est l'ordre d'affichage** côté mobile
(`Categorie.values`) — d'où la place de Restauration juste après Alimentation :
les deux répondent à la même intention, alors qu'elles sont bien distinctes
(chercher où manger n'est pas chercher des courses à emporter).

Extensible en phase ultérieure si besoin identifié sur le terrain — la source
de vérité est `apps/backend/src/common/enums/categorie.enum.ts`, et son miroir
Dart tenu par `tool/check_enums.dart`.

> ⚠️ **Cette section a annoncé 6 catégories pendant deux semaines et demie
> après l'ajout de la 7ᵉ** — corrigé le 2026-08-15. Ce n'est pas resté sans
> effet : `docs/SPEC_INTEGRATION_ECHANGOCRM.md` s'est écrit sur cette liste, et
> son contrat d'échange aurait fait **rejeter toutes les fiches de restaurants**
> avec une énumération à 6 valeurs côté CRM. Une liste fermée recopiée dans un
> document est une copie de plus à tenir (règle 30) : la lire ici sans vérifier
> l'enum est le geste qui a produit le défaut.

### 5.7 Langue
Saisie libre en arabe et/ou français par l'agent/commerçant, sans contrainte de format. Pas de recherche texte libre en V0 (la recherche V0 se limite à la sélection par catégorie prédéfinie, §3.1 — la problématique de correspondance bilingue ne se pose donc pas encore, à traiter uniquement quand la recherche par mot-clé sera développée en phase 2).

### 5.8 Stockage des images et rétention

- **Stockage** : photos des promos hébergées sur **OVH S3** (cohérent avec l'infrastructure existante du porteur de projet).
- **Compression obligatoire côté app avant upload, cible ~250 Ko après compression** (décision 2026-07-12 : le premier plafond retenu, 5 Mo, était beaucoup trop généreux pour le marché algérien — coût data, couverture réseau variable à Djelfa). Compression par paliers largeur/qualité décroissants (1200px/q80 → … → 700px/q35, voir `StorageApi._compress` côté mobile) jusqu'à passer sous la cible, plutôt qu'un seul réglage fixe qui ne garantissait rien sur le poids réel produit. Même cible pour la photo de commerce et le document de registre — une seule règle de compression, pas de cas particulier par usage. Le plafond serveur (`MAX_UPLOAD_BYTES`, 500 Ko) n'est qu'un filet de sécurité au-dessus de cette cible, pas l'objectif.
- **CDN devant le bucket recommandé** pour les lectures côté client (évite de taper S3 directement à chaque affichage de promo à volume).
- **Structure de bucket** à prévoir dès le départ pour faciliter le nettoyage automatique, ex. `promo-photos/{commercant_id}/{promo_id}.jpg`.

**Politique de rétention — deux durées de vie distinctes** (décision : ne pas tout supprimer en bloc) :

| Élément | Durée de rétention | Raison |
|---|---|---|
| **Image (fichier S3)** | 1 mois, puis suppression automatique | Maîtrise du coût de stockage — pas de valeur au-delà de l'audit à court terme |
| **Métadonnées de la promo** (prix, dates, catégorie, compteurs de vues) | Conservées indéfiniment en base | Préserve l'historique de performance pour le dashboard commerçant (§3.2) et les statistiques globales, coût quasi nul (données texte) |

> Tâche planifiée supplémentaire à prévoir (cron) : suppression des fichiers S3 dont la promo associée dépasse 1 mois, indépendante du job d'expiration fonctionnelle à J+5 (§5.1).

---

## 6. Naming & branding

- **Nom du module** : **echango Promo**
- Cohérent avec la convention existante de l'écosystème (echango, echango POS, echango Pay) : nom fonctionnel et sobre plutôt que marketing, compréhensible tel quel par l'utilisateur cible (commerçant de proximité, pas nécessairement familier du vocabulaire startup).
- Domaine et sous-domaines disponibles sous echango.com.
- Déjà publié sur App Store / Play Store sous le compte développeur echango / echango POS — aucun conflit de nommage attendu pour l'ajout d'un module supplémentaire. Longueur du nom largement dans les limites des stores (max 30 caractères Apple/Google, "echango Promo" en fait 13).

---

## 7. Points ouverts / à trancher avant ou pendant le développement

Ces points ont été identifiés en cours de discussion mais **pas encore définitivement arbitrés** — à ne pas considérer comme figés :

1. **Mode hors-ligne agent** : explicitement écarté du périmètre V0, mais risque réel identifié (couverture réseau variable à Djelfa). Une version minimale a été proposée (bloquer l'action avec message clair "pas de réseau" plutôt que de laisser échouer silencieusement) mais **non validée par le porteur de projet** — à trancher avant le début du développement de l'app agent.
2. **Tri par défaut de la liste des promos actives** côté client (proposition : expiration la plus proche en premier — non confirmé).
3. **Choix technique (stack)** : non tranché dans cette discussion. Le porteur de projet utilise habituellement NestJS (backend) + Flutter (mobile) sur ses autres projets — à confirmer explicitement comme choix pour ce module ou à rediscuter.
4. **CGU / consentement** (photo, données commerçant) : non traité, explicitement noté comme hors périmètre pour un pilote à échelle réduite (~30 commerces, connus personnellement), mais **à traiter avant toute ouverture publique plus large**.
5. ~~**Coût SMS OTP**~~ — **Tranché** : suppression complète de l'OTP SMS (jugé inutile et coûteux pour ce marché). Le commerçant définit son PIN sans preuve de possession du numéro ; le signalement/modération devient la seule ligne de défense anti-fraude (voir §3.2 et le point 7 ci-dessous).
6. ~~**Ajustabilité de la date de fin par défaut**~~ — **Tranché** : sélecteur de durée 1 à 7 jours à la publication (5 jours par défaut), validé côté serveur (`PROMO_MAX_DURATION_DAYS`). Voir §3.2.
7. **Impact de l'auto-inscription sur l'anti-fraude** : avec l'auto-inscription ouverte dès la V0, un compte peut publier sans jamais être vérifié physiquement (niveau `auto_inscrit`). Le seuil de signalement actuel (3 devices) a été calibré en pensant à un contenu majoritairement `confirmé_agent`. À réévaluer une fois le pilote lancé : le seuil est-il toujours pertinent avec une proportion significative de comptes `auto_inscrit` non vérifiés ?

---

## 8. Hors périmètre V0 (explicitement reporté)

> Mise à jour : l'auto-inscription commerçant, les favoris client, la recherche par catégorie et le dashboard commerçant avec statistiques ont été **intégrés à la V0** (voir §3.1, §3.2). Liste mise à jour ci-dessous.

- Notifications push géolocalisées
- Recherche par mot-clé / produit en texte libre
- Monétisation (mise en avant payante, publicité ciblée, statistiques annonceurs)
- Séparation des rôles admin / modérateur
- CGU / consentement formalisé

---

## 9. Note de méthode (double passe)

**Passe 1** — reconstitution chronologique de toutes les décisions actées au fil de la discussion, structurées par acteur/entité/règle.

**Passe 2** — relecture ciblée sur les incohérences et angles morts. Éléments corrigés ou explicités lors de cette seconde passe :
- Distinction clarifiée entre l'état de compte du commerçant (cycle de vie) et son niveau de vérification (badge) — deux dimensions indépendantes qui étaient mentionnées séparément dans la discussion mais jamais formellement reliées.
- Ajout du Journal d'audit comme entité recommandée (mentionné une fois dans la discussion à propos des zones, mais pas repris dans la liste finale des entités).
- Remontée explicite du point "mode hors-ligne" en section "points ouverts" plutôt que de le classer comme définitivement tranché, car une contre-proposition de Claude n'a jamais reçu de réponse explicite du porteur de projet.
- Ajout explicite du point "ajustabilité de la durée par défaut de 5 jours", jamais précisé dans la discussion (fixe vs. modifiable).
