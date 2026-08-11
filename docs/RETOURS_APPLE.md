# Retours d'Apple — ce que chaque refus nous a appris

**À lire avant chaque soumission**, y compris pour les autres apps de la suite
(TikMeal, echango POS, echango Vendeur). Rien ici n'est une bonne pratique
générale recopiée d'un guide : **chaque point référence un refus, un blocage ou
un aller-retour réellement subi**, avec sa date et l'identifiant de soumission.
C'est ce qui permet de reconnaître un cas nouveau qui relève du même motif.

> ⚠️ **Un document de retours n'est pas une garantie.** Il dit ce qui s'est déjà
> produit, pas ce qui peut se produire. Un reviewer humain change d'un passage à
> l'autre, et deux revues du même écran ont déjà donné deux motifs différents
> (voir R1 → R2). La liste de contrôle en fin de document réduit le risque connu ;
> elle ne l'annule pas.

---

## 1. L'historique, en un coup d'œil

App concernée : **echango Promo**, bundle `com.echango.promo`, soumission
`3d2aab99-3e00-43fe-a9a9-2aa048b44ae3`. **Les trois revues ont été faites sur
iPad Air 11" (M3)** — voir la leçon G.

| Date | Version | Verdict | Motif | Nature |
|---|---|---|---|---|
| 2026-07-31 | — | **Bloqué avant revue** | *Missing Compliance* (TestFlight) | Technique, `Info.plist` |
| fin juillet 2026 | — | **Bloqué avant revue** | Signature iOS / CI Codemagic | Technique, build |
| 2026-08-05 | *non noté* | ❌ Refus | **5.1.1(iv)** — localisation | Produit, écran |
| 2026-08-07 | 1.0 (10) | ❌ Refus | **5.1.1(iv)** — localisation, *encore* | Produit, écran |
| 2026-08-10 | 1.0 (11) | ❌ Refus | **2.3.10** — captures d'écran | Métadonnées |

**Deux refus sur trois portaient sur le même écran**, et le troisième ne touche
pas au code. Aucun n'a porté sur une fonctionnalité, une panne ou la sécurité.

---

## 2. Les cas, un par un

### R0 — *Missing Compliance* : le build arrive, et personne ne peut l'installer (2026-07-31)

**Symptôme :** les testeurs reçoivent l'invitation TestFlight, et **aucune build
n'apparaît** dans l'app TestFlight. Aucun message d'erreur, ni dans App Store
Connect, ni côté testeur, ni dans le log de build. Le build est là, marqué
« Missing Compliance », et non distribuable.

**Cause :** la clé `ITSAppUsesNonExemptEncryption` n'était pas déclarée dans
`Info.plist`. Sans elle, Apple attend une réponse manuelle au questionnaire de
conformité export **pour chaque build**.

**Correctif** (`apps/mobile/ios/Runner/Info.plist`) :

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

`false` est la bonne valeur tant que l'app n'utilise que **HTTPS/TLS via les API
standard du système** — cas explicitement exempté par l'*Export Administration
Regulations*. À repasser à `true` (avec dépôt d'un CCATS) uniquement si on
embarque un jour sa propre implémentation de chiffrement.

> **La leçon** : un blocage Apple peut être **totalement silencieux**. Ici, rien
> n'échoue — ça n'apparaît simplement pas. Toujours vérifier l'**état** de la
> build dans App Store Connect, jamais se fier au succès du build CI.

---

### R1 — 5.1.1(iv) : « Plus tard » sur le bouton qui fait avancer (2026-08-05)

**Ce qu'Apple a écrit :**

> The app encourages or directs users to allow the app to access the location…
> to proceed users press a **"plus tard"** button. Use words like "Continue" or
> "Next" on the button instead.

**Ce qu'Apple a vu, et qui était vrai :** sur l'écran de localisation de
l'onboarding, le bouton qui fait avancer s'appelait « Plus tard ». Un mot de
report là où il faut un mot neutre.

**Ce qu'Apple n'a pas dit, et qui était la cause de fond :** « Plus tard » ne
refusait rien — il menait à un **second écran** qui redemandait exactement la
même chose, sous le titre « Activer la localisation ». Deux sollicitations
d'affilée, c'est littéralement *encourages users to allow*.

**Ce qui a été fait :** libellé neutre, second écran supprimé, proposition
déplacée sur la carte en bandeau contextuel, et justification `Info.plist`
réécrite (elle décrivait la position **du commerce** alors que le testeur voyait
la demande **du client** — voir la leçon E).

> **La leçon (A)** : **le motif cité est un symptôme, pas la cause.** Corriger
> exactement la phrase reçue, et rien d'autre, c'est acheter un second refus plus
> lent. Lire la *guideline*, pas seulement le paragraphe.

---

### R2 — 5.1.1(iv), encore : le message ne doit pas décider (2026-08-07)

**Ce qu'Apple a écrit :**

> - A custom message appears before the permission request, and to proceed users
>   press a **"Activer la localisation"** button. Use words like "Continue" or
>   "Next" on the button instead.
> - A custom message appears before the permission request, and the user can
>   **close the message and delay** the permission request with the "Continuer"
>   button. The user should always proceed to the permission request after the
>   message.

**Pourquoi R1 n'avait pas suffi :** on avait lu le premier refus comme un
problème de libellé, et renommé le seul bouton **secondaire**. L'écran gardait
donc **deux** issues, et chacune portait exactement un des deux griefs — le
principal **encourageait**, le secondaire **reportait**.

**Et le bandeau de la carte, qui était le correctif de R1, portait les deux
griefs à lui seul** : le même libellé « Activer la localisation » (même clé de
traduction, `onboardingLocationEnable`) et une croix pour l'écarter sans
demander. Le reviewer qui ouvrait la carte retrouvait mot pour mot ce qu'il
venait de refuser.

**Ce qui a été fait :**

- un seul bouton, « Continuer », qui mène **toujours** à la demande système ;
- la fonction `skipLocationAndFinish` **supprimée** — la garder, c'est garder la
  porte que le refus vise ;
- textes passés de l'impératif au descriptif (« Activez la localisation pour… »
  encourage autant qu'un bouton) ;
- bandeau de la carte supprimé, remplacé par le geste standard : le bouton
  « me localiser » déclenche directement la demande, sans texte intercalaire.

> **La leçon (B)** — la règle réelle, celle qu'Apple applique et qui ne tient pas
> dans un vocabulaire : **un message maison a le droit d'expliquer, il n'a pas le
> droit de décider.** La seule décision est celle prise dans la boîte du système.
>
> **La leçon (C)** : **corriger à un endroit et recréer ailleurs.** Après un
> refus, chercher le motif dans **toute** l'app — pas seulement sur l'écran cité.
> Le correctif de R1 est devenu le grief de R2.

---

### R2 bis — le trou que le correctif laissait ouvert (trouvé en relecture, pas par Apple)

Le premier jet du correctif R2 n'affichait le bouton « me localiser » **que si la
permission était encore demandable**. Question posée juste après : *« comment le
client active-t-il la localisation, alors ? »* — il n'y avait pas de réponse.

**Sur iOS, ce cas n'est pas le cas rare, c'est le cas normal.** Le plugin
`geolocator` traduit `notDetermined` en `LocationPermission.denied` et le refus
utilisateur en `deniedForever`. Donc **dès le premier « Ne pas autoriser »** —
celui de l'onboarding, que tout le monde voit — `requestPermission()` ne rouvre
plus jamais de boîte, la condition d'affichage devient fausse, et l'utilisateur
ne voit **ni bouton ni message**. Il est enfermé dehors.

Le bouton est désormais toujours affiché, avec quatre issues et aucun cul-de-sac :

| État | Ce que fait le bouton |
|---|---|
| Position connue | Recentre la carte |
| Permission demandable | Déclenche la boîte système |
| Refusée (`deniedForever`) | Message + action **Réglages** (`openAppSettings`) |
| Service de localisation coupé | Message + action **Réglages** (`openLocationSettings`) |

> **La leçon (D)** : **un refus sans porte de retour est un défaut produit**, pas
> seulement de conformité. Et Apple donne lui-même le remède dans sa lettre :
> *« include a notification to inform the user and provide a link to the Settings
> app »*. Un message qui constate sans ouvrir de porte n'est pas une sortie.

---

### R3 — 2.3.10 : des références Google Play dans les captures (2026-08-10)

**Ce qu'Apple a écrit :**

> The app or metadata includes information about third-party platforms that may
> not be relevant for App Store users… Revise the app's screenshots to remove
> Google Play references.

**Ce que ça n'était pas :** le binaire. Vérifié — le seul endroit où l'app peut
afficher un lien de store choisit déjà par plateforme
(`Platform.isIOS ? Env.appStoreUrl : Env.playStoreUrl`), et la ligne n'apparaît
même pas tant que l'URL est vide. Sur iOS, `playStoreUrl` n'est jamais lu.

**Ce que c'était :** les captures d'écran uploadées dans App Store Connect.

**À savoir pour le corriger :** Apple le dit dans sa lettre, et c'est le piège —
*« some screenshots may only be viewed and updated by selecting **View All Sizes
in Media Manager** »*. Il existe des emplacements de tailles que la vue par
défaut ne montre pas, et l'image fautive y survit à une correction faite
« au premier écran ».

> **La leçon (H)** : **les métadonnées sont revues comme le code**, et le motif
> couvre plus que les images — description, texte promotionnel, nouveautés de
> version, URL marketing et support.
>
> **La leçon (I)** : un rejet de métadonnées **ne demande pas un nouveau build**.
> On corrige et on renvoie les métadonnées seules, sans repasser par la CI.

---

## 3. Les leçons, sous une forme réutilisable

Les lettres renvoient aux cas ci-dessus.

**A. Le motif cité est un symptôme.** Corriger la phrase reçue et rien d'autre
achète un refus plus lent. Chercher *pourquoi* cet écran a déclenché cette
guideline. *(R1 → R2)*

**B. Une permission : le message explique, il ne décide pas.** En pratique, sur
un écran d'explication pré-permission :
- **un seul** bouton, libellé neutre (« Continuer », « Suivant ») ;
- **aucune** autre sortie : pas de second bouton, pas de croix, pas de lien
  « plus tard », pas de geste de retour ni de pile de navigation qui en laisse un ;
- **aucun impératif** dans le texte (« Activez… ») — ça encourage autant qu'un
  bouton ;
- **une seule** sollicitation : jamais deux écrans qui demandent la même chose. *(R1, R2)*

**C. Après un refus, chercher le motif partout.** Le correctif d'un refus peut
être le grief du suivant. Faire un `grep` sur la clé de traduction et sur le
motif d'interaction, pas seulement sur l'écran cité. *(R2)*

**D. Toute permission a une porte de retour.** Refusée ⇒ un message **et** un
lien vers les Réglages. Vérifier ce que le plugin rend vraiment sur iOS : un
premier refus y vaut souvent `deniedForever`. *(R2 bis)*

**E. La justification `Info.plist` doit décrire ce que le testeur voit.** La
nôtre parlait de la position du commerce alors que la demande vue à la revue
était celle du client. Apple ne l'a pas relevé — c'est un motif 5.1.1 à part
entière, qui attendait son tour. *(R1)*

**F. Un blocage Apple peut être totalement silencieux.** *Missing Compliance* ne
produit aucune erreur : la build est simplement absente. Vérifier l'**état** dans
App Store Connect, pas le succès de la CI. *(R0)*

**G. Le testeur choisit l'appareil, pas vous.** Les trois revues ont eu lieu sur
**iPad Air 11"**. Déclarer le support iPad, c'est faire juger la mise en page
*et* exiger un jeu de captures iPad réelles. Si l'iPad n'est pas visé, le retirer
des appareils supportés est une décision, pas un oubli.

**H. Les métadonnées sont revues comme le code** — captures (toutes les tailles,
via *View All Sizes in Media Manager*), description, texte promotionnel,
nouveautés, URL marketing et support. *(R3)*

**I. Un rejet de métadonnées ne demande pas un nouveau build.** *(R3)*

**J. Le libellé et la clé doivent dire la même chose.** `onboardingLocationLater`
portant le texte « Continuer » était le prochain contresens garanti : la clé a
été renommée dans le même commit. *(R1)*

---

## 4. Liste de contrôle avant soumission

À dérouler **entièrement**, dans l'ordre. Les cases non cochées sont des risques
assumés, pas des détails.

### Build et technique

- [ ] `ITSAppUsesNonExemptEncryption` déclarée dans `Info.plist` *(sinon : build invisible, R0)*
- [ ] Numéro de build incrémenté (Codemagic le fait via `$BUILD_NUMBER`)
- [ ] La build est **« Ready to Submit »** dans App Store Connect — pas seulement verte dans la CI
- [ ] Chaque `NS*UsageDescription` décrit **ce que le testeur verra**, pas un usage secondaire

### Permissions — un passage par permission demandée

Pour la localisation, la caméra, la photothèque, les notifications… :

- [ ] L'écran d'explication (s'il existe) n'a **qu'un** bouton, au libellé neutre
- [ ] Ce bouton mène **toujours** à la demande système
- [ ] Aucune autre sortie : croix, retour, balayage, second bouton
- [ ] Aucun impératif dans le titre ni le sous-titre
- [ ] La même permission n'est **jamais** demandée deux fois d'affilée
- [ ] Après un refus, il existe un chemin visible vers les Réglages
- [ ] Aucun autre écran de l'app ne reproduit le motif (grep sur les clés de traduction)

### Métadonnées

- [ ] Captures = **vraies captures** de l'app, pas des maquettes marketing
- [ ] **Toutes les tailles** passées en revue via *View All Sizes in Media Manager*
- [ ] Aucune référence à un store tiers : badge Google Play, cadre d'appareil Android, logo
- [ ] Aucune mention d'Android ou d'un autre store dans la **description**, le **texte promotionnel**, les **nouveautés de version**
- [ ] L'**URL marketing** et l'**URL de support** ne mènent pas à une page portant un badge Play
- [ ] Captures **iPad** présentes si le support iPad est déclaré *(leçon G)*

### Accès pour le testeur

- [ ] Un **compte de démonstration** est fourni dans les notes de revue si une
      fonctionnalité est derrière une connexion
- [ ] Les portes non évidentes sont **expliquées** dans les notes

> ⚠️ **Point d'attention propre à echango Promo, jamais encore éprouvé en revue** :
> l'espace pro n'a pas d'entrée dans le menu public, et l'écran de connexion
> commerçant bascule en mode admin dès qu'on y saisit un e-mail au lieu d'un
> numéro. Un reviewer qui tombe dessus sans identifiants peut le lire comme une
> fonctionnalité incomplète. Fournir un compte commerçant **et** décrire la
> bascule dans les notes de revue.

### Réponse à Apple

- [ ] Si le refus repose sur un malentendu → répondre dans App Store Connect **avant** de resoumettre
- [ ] Sinon → une réponse courte pointant le changement précis fait souvent gagner un aller-retour

---

## 5. Ce qu'on ne sait pas

Écrit ici pour que personne ne le prenne pour acquis :

- **L'écran d'explication de la localisation existe toujours.** Il est conforme à
  la lettre de R2 (un bouton, mot neutre, une seule issue), et Apple autorise
  explicitement d'expliquer avant de demander. Mais c'est un écran dont le métier
  est de valoriser la permission, et **il s'est déjà fait refuser deux fois**. Un
  troisième reviewer peut estimer que sa liste d'arguments « encourage ». Le
  supprimer — la boîte système portant seule l'explication via `Info.plist` — est
  l'option à risque nul ; il a été décidé le 2026-08-11 de **garder l'écran**.
- **Aucune revue n'a encore dépassé l'écran d'accueil de manière documentée.** Les
  trois refus portent sur l'onboarding et les métadonnées. Rien ne dit comment les
  parcours commerçant, agent et admin seront reçus.
- **Le support iPad n'a jamais été une décision explicite.** Il est actif par
  défaut, et c'est ce qui fait tester sur iPad Air.

---

## 6. Où vit le détail

| Sujet | Où |
|---|---|
| Chronologie complète, correctifs, code | `docs/status_v0.1.md`, entrées des 2026-08-05 et 2026-08-08 |
| Procédure de publication (comptes, signature, App Links) | `docs/DEPLOIEMENT_STORES.md` |
| Configuration CI iOS | `codemagic.yaml` |
| Règles de code qui découlent de ces refus | `CLAUDE.md` |
