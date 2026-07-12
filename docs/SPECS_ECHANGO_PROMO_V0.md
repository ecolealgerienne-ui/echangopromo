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
- **Sélection de ville par défaut** : demandée au premier lancement, stockée en local (pas de compte), modifiable à tout moment.
- Pour les grandes villes : sélection affinée par **commune** (découpage administratif officiel wilaya → commune).
- **Liste des promos actives**, filtrée par commune sélectionnée.
- **Filtre par catégorie** (liste fixe, voir §5.6).
- **Fiche promo** : photo, produit, prix avant/après, nom et adresse du commerçant, date de fin de validité. Si le commerçant a renseigné une photo de son commerce et/ou une position GPS, la fiche affiche aussi la photo du commerce et un bouton "Itinéraire" qui ouvre l'app Google Maps (lien simple, pas d'intégration payante).
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
2. Définition d'un **code PIN** (4-6 chiffres) par le commerçant — directement à l'inscription, ou plus tard via l'écran de connexion pour un compte créé par l'agent (`claim`, voir cycle de vie ci-dessous). Aucune preuve de possession du numéro n'est demandée.
3. Connexions suivantes : téléphone + PIN.
4. **PIN oublié** : pas de flux libre-service. Seul l'**admin** peut effacer le PIN d'un commerçant (sur demande, hors app) ; le commerçant en redéfinit ensuite un nouveau via `claim`, comme pour un compte créé par un agent.

**Cycle de vie du compte** (états) :

```
créé_agent → autonome (dès que le commerçant définit son PIN via `claim`)
auto_inscrit → autonome (directement, dès la saisie du PIN à l'inscription)
```

- Un compte créé par l'agent reste `créé_agent` jusqu'à ce que le commerçant définisse lui-même son PIN pour ce numéro (`claim`) — il n'y a plus d'étape "revendication" distincte ni d'OTP intermédiaire.
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

**Fiche commerçant — données saisies à la création** (auto-inscription ou
création agent) :
- Commune sélectionnée par **wilaya puis commune** (même logique de
  sélection guidée que côté client, §3.1), pas une liste plate.
- **Photo du commerce, optionnelle** — pour que les clients l'identifient
  facilement dans la liste/fiche (caméra ou galerie, contrairement à la
  photo de promo prise par l'agent qui est caméra uniquement).
- **Position GPS, optionnelle** — capturée via la localisation native de
  l'appareil (gratuit, aucune intégration Google Maps payante). L'adresse
  texte est elle aussi optionnelle (peut être saisie en complément de ou à
  la place de la position GPS), l'adressage informel étant
  courant localement. Sert uniquement à afficher un bouton "Itinéraire"
  côté client (§3.1) ; aucune carte interactive en V0.
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

- **Rattaché à zéro, une ou plusieurs Commune(s)** (relation many-to-many) — le
  concept de Zone opérationnelle séparée a été abandonné (2026-07-09) : un
  agent doit pouvoir couvrir plusieurs communes, voire une wilaya entière
  ("assigner toute la wilaya" est une commodité d'UI qui sélectionne en masse
  les communes de cette wilaya, pas un champ distinct), le staffing "un agent
  par commune" n'étant pas soutenable.
- Authentification **email + mot de passe**, compte créé exclusivement par l'Admin (pas d'auto-inscription agent).
- Voit la liste des commerces de ses communes avec statut : jamais visité / à jour / à relancer.
- Crée une fiche commerçant (numéro de téléphone, nom, adresse, catégorie) + première promo.
- Prend la photo de la promo **obligatoirement dans l'app** (pas d'upload depuis la galerie), avec horodatage. **Pas de géolocalisation capturée** (décision explicite — écartée après discussion).
- Met à jour une promo existante sur un commerce déjà onboardé.
- N'a plus d'action à faire pour activer le compte du commerçant : celui-ci le fait lui-même, quand il le souhaite, en définissant son PIN sur l'écran de connexion (pas d'OTP à initier).
- **Pas de mode hors-ligne en V0** (décision explicite malgré la couverture réseau variable à Djelfa — voir §7, risque à surveiller pendant le pilote).

### 3.4 Admin / Modérateur

- Authentification **email + mot de passe**.
- **Un seul rôle en V0** (pas de séparation admin/modérateur pour le pilote — à réévaluer si recrutement d'un modérateur dédié).
- Valide ou rejette le registre envoyé par un commerçant auto-inscrit — condition désormais bloquante pour que celui-ci puisse publier (§3.2).
- Traite la file de modération des promos signalées (masquer / valider en `vérifiée_ok` / avertir le commerçant).
- Crée et gère les comptes agents, assigne un agent à une ou plusieurs communes.
- **Transfère des communes** d'un agent à un autre (cas : départ d'un agent — sans ça, les fiches des communes concernées cessent d'être mises à jour silencieusement).
- **Réinitialise le PIN** d'un commerçant sur demande (seul recours en cas de PIN oublié, pas de flux libre-service — voir §3.2).
- Vue globale (dashboard) : nombre de commerces actifs, nombre de promos publiées, nombre de signalements en attente.

---

## 4. Entités de données (vue haut niveau)

> Détail des schémas/relations à faire dans une passe dédiée "modèle de données" — ceci n'est qu'un inventaire d'entités et de leurs statuts/cycles de vie, nécessaire pour cadrer le développement.

- **Commune** — référentiel administratif officiel (wilaya → commune), utilisé pour le filtre client et pour le rattachement territorial d'un agent (many-to-many `Agent` ↔ `Commune` — le concept de Zone séparée a été abandonné).
- **Commerçant** — fiche + état de compte (`créé_agent` / `autonome`) + origine de vérification (`auto_inscrit` / `confirmé_agent`) + statut registre (`en_attente` / `validé` / `rejeté`, bloquant pour publier uniquement si `auto_inscrit`).
- **Promo** — liée à un commerçant, statut (`active` / `expirée` / `signalée` / `masquée` / `vérifiée_ok`), photo, prix avant/après, catégorie, date de fin, compteur de signalements.
- **Agent** — compte + communes assignées (many-to-many).
- **Admin** — compte, rôle unique en V0.
- **Signalement (Report)** — device_id, promo_id, horodatage. Sert au calcul du seuil de modération.
- **Journal d'audit (AuditLog)** — recommandé pour tracer les actions des agents (création, modification de fiche commerçant) et de l'admin (réinitialisation de PIN, transfert de communes) avec identité + horodatage, notamment utile en cas de communes multiples ou de transfert.

---

## 5. Règles métier

### 5.1 Expiration des promos
Tâche planifiée (cron, ex. quotidienne) qui bascule automatiquement les promos ayant dépassé leur date de fin vers le statut `expirée`. Aucune action utilisateur ne déclenche ce changement — c'est un point critique à ne pas oublier en développement, sans quoi l'objectif de fraîcheur du contenu est compromis silencieusement.

### 5.2 Commune — territoire agent et filtre client (Zone abandonnée)
- **Commune** : découpage officiel, filtre visible côté client, doit permettre l'extension vers d'autres wilayas sans refonte.
- Le découpage opérationnel interne "Zone" (distinct de Commune) a été
  abandonné le 2026-07-09 : un agent est rattaché directement à une ou
  plusieurs `Commune` (relation many-to-many), un agent par commune n'étant
  pas soutenable et le rôle agent lui-même étant amené à disparaître à
  l'extension multi-wilaya. "Assigner toute la wilaya" reste une commodité
  d'UI (sélection en masse des communes de cette wilaya), pas un champ
  distinct — une seule source de vérité pour le territoire d'un agent.

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
2. Vêtements / Textile
3. Électroménager
4. Beauté / Hygiène
5. Maison / Ameublement
6. Autre

Extensible en phase ultérieure si besoin identifié sur le terrain.

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
