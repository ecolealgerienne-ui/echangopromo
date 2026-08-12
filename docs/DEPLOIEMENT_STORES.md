# Déploiement sur les stores (Google Play / Apple App Store)

Ce document couvre deux choses liées mais distinctes :

1. **Publier l'app** sur Google Play et l'App Store (démarches, comptes,
   signature, fiches).
2. **App Links / Universal Links** (`promo.echango.com`) : le lien partagé
   depuis la fiche promo (`promo_detail_screen.dart`) doit ouvrir l'app
   directement si elle est installée, et rediriger vers le store sinon —
   jamais afficher un site avec la promo (décision produit actée).

**État actuel : rien n'est publié.** Tout ce qui suit est préparé dans le
code (déjà fait, voir « Ce qui est déjà en place ») mais désactivé de fait
tant que les vraies valeurs (identifiants, certificats, liens store) ne
sont pas renseignées — sans risque, ça ne casse rien en attendant.

---

## Ce qui est déjà en place (rien à refaire)

- **Mobile** (`apps/mobile`) :
  - `lib/config/env.dart` : `Env.playStoreUrl` / `Env.appStoreUrl`, vides
    par défaut (`String.fromEnvironment`).
  - `android/app/src/main/AndroidManifest.xml` : intent-filter App Links
    (`autoVerify`, host `promo.echango.com`, pathPrefix `/p`) déjà ajouté.
  - `ios/Runner/Runner.entitlements` : capacité Associated Domains
    (`applinks:promo.echango.com`) déjà créée en fichier — **doit encore
    être reliée au projet Xcode** (voir section iOS, ne peut pas se faire
    sans Xcode/Mac).
  - `go_router` route déjà `/p/:id` (`app/router.dart`, même écran que la
    route interne `/promo/:id`) : aucun code Dart supplémentaire à écrire
    pour la navigation elle-même une fois la vérification App
    Links/Universal Links validée par Android/iOS.
- **Backend** (`apps/backend`) :
  - `src/app-links/` (`AppLinksModule`/`AppLinksController`), branché sur
    `promo.echango.com` (voir `@Controller({ host: ... })`), sert :
    - `GET /.well-known/assetlinks.json`
    - `GET /.well-known/apple-app-site-association`
    - `GET /p/:id` → redirige vers le store (ou une page d'attente tant
      qu'aucun lien store n'est configuré). Volontairement `/p` et pas
      `/promo` : évite toute collision avec `GET /promo/:id`, l'API JSON
      de `PromoController` utilisée par l'app mobile — y compris si les
      deux finissent par partager le même sous-domaine (voir plus bas).
  - `.env.example` : 6 nouvelles variables, toutes vides, listées plus
    bas avec leur provenance exacte.

**Ce qu'il reste à faire manuellement** (comptes, identifiants, décisions
produit — rien de tout ça ne peut être deviné ni fait à ta place) est
détaillé ci-dessous, dans l'ordre.

---

## 0. Identité de l'app — fixée le 2026-07-30

**`com.echango.promo`**, identique côté Android et iOS, aligné sur le
domaine `promo.echango.com` déjà utilisé par les App Links.

Appliqué partout :

| Endroit | Valeur |
|---|---|
| `android/app/build.gradle.kts` | `applicationId` et `namespace` |
| `android/app/src/main/kotlin/com/echango/promo/MainActivity.kt` | déclaration `package` |
| `ios/Runner.xcodeproj/project.pbxproj` | `PRODUCT_BUNDLE_IDENTIFIER` (6 configurations) |
| `apps/backend/.env.example` | `ANDROID_PACKAGE_NAME`, `IOS_BUNDLE_ID` |

**Ne plus jamais le changer.** Android comme iOS traitent un identifiant
différent comme une application distincte : après publication, le modifier
couperait la mise à jour pour tous les utilisateurs déjà installés, qui
resteraient bloqués sur l'ancienne version sans aucun message.

Les valeurs backend doivent rester strictement identiques à celles
compilées dans l'app — un écart fait échouer la vérification App
Links/Universal Links **en silence** : le lien s'ouvre alors dans le
navigateur au lieu de l'app, sans erreur nulle part.

### Signature de release (Android)

`android/app/build.gradle.kts` lit `android/key.properties`, volontairement
absent du dépôt (`.gitignore`, avec `*.jks`/`*.keystore`) — Google
n'accepte **qu'une seule clé de signature par application, à vie** : la
publier dans le dépôt reviendrait à la perdre.

Créer le keystore, puis le fichier de configuration :

```bash
keytool -genkey -v -keystore ~/echango-upload.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias upload
```

`apps/mobile/android/key.properties` :

```properties
storePassword=<mot de passe du keystore>
keyPassword=<mot de passe de la clé>
keyAlias=upload
storeFile=C:/chemin/absolu/vers/echango-upload.jks
```

Sans ce fichier, la release retombe sur la clé de **debug** : pratique pour
un `flutter run --release` local, mais l'artefact est refusé par Google
Play. C'est délibéré — l'oubli devient impossible à ignorer.

Sauvegarder le keystore ailleurs que sur la machine de développement.
Perdu, il n'existe aucun recours : l'application doit être republiée sous
un nouvel identifiant, en repartant de zéro côté installations et avis.

## 1. Google Play

### Prérequis

- Compte [Google Play Console](https://play.google.com/console) (frais
  unique ~25 $).
- `applicationId` définitif fixé (étape 0).

### Étapes

1. **Générer un keystore de release** (à conserver précieusement, sa
   perte empêche toute future mise à jour de l'app) :
   ```bash
   keytool -genkey -v -keystore ~/echango-upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. **Configurer la signature** : créer `android/key.properties` (jamais
   commité — à ajouter à `.gitignore` si pas déjà fait) référencé depuis
   `android/app/build.gradle` (`signingConfigs.release`). La documentation
   Flutter officielle
   ([flutter.dev/to/reference-app-bundle](https://docs.flutter.dev/deployment/android))
   détaille exactement ce câblage.
3. **Build** :
   ```bash
   flutter build appbundle --release
   ```
4. **Créer l'app sur Play Console** : fiche store (description FR/EN/AR,
   captures d'écran, icône), **politique de confidentialité** (obligatoire
   — une simple page hébergée sur `echango.com` suffit), classification du
   contenu, formulaire "Sécurité des données" — voir le § dédié ci-dessous,
   la déclaration a changé le 2026-08-12.
5. **Upload** du `.aab` généré à l'étape 3, passage en test interne puis
   production.
6. **Récupérer l'empreinte SHA-256 réelle** pour `assetlinks.json` — **⚠️
   piège fréquent** : si *Play App Signing* est activé (cas par défaut à
   la première publication), Google **re-signe** l'app avec son propre
   certificat avant de la distribuer. L'empreinte à utiliser n'est donc
   **pas** celle du keystore local, mais celle affichée dans *Play
   Console → Configuration de la version → Intégrité de l'app → Signature
   d'application*.
7. **Renseigner les variables** (backend `.env` + rebuild mobile avec
   `--dart-define`) — voir tableau récapitulatif en fin de document.

---

## 2. Apple App Store

### Prérequis

- Un **Mac avec Xcode** (obligatoire pour builder/signer iOS — absent de
  l'environnement de dev actuel, WSL/Windows).
- Compte [Apple Developer Program](https://developer.apple.com/programs/)
  (~99 $/an).
- `applicationId`/bundle id définitif fixé (étape 0).

### Étapes

1. **Créer l'App ID** sur
   [developer.apple.com → Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)
   avec le bundle identifier choisi, en activant la capacité *Associated
   Domains*.
2. **Relier `Runner.entitlements`** (déjà créé dans le repo) au projet :
   dans Xcode, sélectionner le target *Runner* → *Signing & Capabilities*
   → *+ Capability* → *Associated Domains* → ajouter
   `applinks:promo.echango.com`. Xcode câble alors correctement le fichier
   d'entitlements dans `project.pbxproj` — **ne pas éditer ce fichier à la
   main**, c'est le genre de fichier généré qui casse facilement.
3. **Créer la fiche** sur
   [App Store Connect](https://appstoreconnect.apple.com/) (métadonnées,
   captures d'écran, politique de confidentialité — obligatoire aussi), et
   remplir la section **Confidentialité** : voir le § dédié ci-dessous.
4. **Build & upload** : *Xcode → Product → Archive*, puis *Distribute
   App*, ou `flutter build ipa` + l'app *Transporter*.
5. **TestFlight** (recommandé avant la review publique), puis soumission
   à la review Apple.
6. **Récupérer le Team ID** : *developer.apple.com → Membership details*
   (10 caractères, ex. `A1B2C3D4E5`).
7. **Renseigner les variables** — voir tableau récapitulatif.

---

## 3. Réseau : héberger `promo.echango.com`

Le sous-domaine doit atteindre **le même backend NestJS** que l'API
mobile (`AppLinksController` y est déjà branché, restreint à ce host).
Deux points à vérifier côté infra, quel que soit l'hébergeur choisi :

- **DNS** : un enregistrement pour `promo.echango.com` pointant vers le
  serveur qui fait tourner le backend (A/AAAA direct, ou CNAME si
  derrière un load balancer).
- **Reverse proxy** (Nginx/Caddy/autre) : le header `Host` **doit être
  transmis tel quel** au backend (`proxy_set_header Host $host;` en
  Nginx) — c'est ce que `@Controller({ host: 'promo.echango.com' })`
  utilise pour distinguer ces routes de l'API mobile classique. Sans ce
  header, toutes les requêtes tombent sur le mauvais contrôleur (ou une
  404).
- **HTTPS obligatoire** : App Links et Universal Links refusent tous les
  deux le HTTP simple.

---

## 4. Récapitulatif des variables à remplir

| Variable | Où | Provenance |
|---|---|---|
| `PLAY_STORE_URL` | `apps/backend/.env` | URL de la fiche Play Store une fois publiée |
| `APP_STORE_URL` | `apps/backend/.env` | URL de la fiche App Store une fois publiée |
| `ANDROID_PACKAGE_NAME` | `apps/backend/.env` | L'`applicationId` choisi à l'étape 0 |
| `ANDROID_SHA256_CERT_FINGERPRINT` | `apps/backend/.env` | Play Console → Intégrité de l'app (**pas** le keystore local si Play App Signing actif) |
| `IOS_TEAM_ID` | `apps/backend/.env` | developer.apple.com → Membership details |
| `IOS_BUNDLE_ID` | `apps/backend/.env` | Le bundle id choisi à l'étape 0 |
| `PLAY_STORE_URL` / `APP_STORE_URL` (mobile) | build mobile | `--dart-define=PLAY_STORE_URL=...` (voir `env.dart`) — un nouveau build est nécessaire, ces valeurs sont figées à la compilation |
| `API_BASE_URL` (mobile) | build mobile | Plus rien à passer : `env.dart` vaut `https://promo.echango.com` par défaut depuis le 2026-07-29. C'est désormais le **développement local** qui exige `--dart-define=API_BASE_URL=http://<ip-locale>:3000` |

Aucune des variables backend n'est requise pour démarrer le backend
aujourd'hui (contrairement à `JWT_SECRET`, validé au boot) — les
renseigner active la fonctionnalité, ne pas les renseigner ne casse rien.
`API_BASE_URL` côté mobile n'est plus un piège de publication : son défaut
est la production. Le risque s'est déplacé sur le développement local, où
oublier le flag fait taper sur la prod — mais ça se constate tout de suite,
contrairement à un release cassé découvert après validation du store.

---

## 5. Checklist

- [ ] `applicationId`/bundle id définitif choisi et appliqué (`rename`)
- [ ] Keystore Android généré, `key.properties` configuré (jamais commité)
- [ ] App publiée sur Play Console (au moins en test interne)
- [ ] Empreinte SHA-256 récupérée **depuis Play Console** (pas le keystore local)
- [ ] Compte Apple Developer actif, App ID créé, capacité Associated Domains activée
- [ ] `Runner.entitlements` relié au projet via Xcode
- [ ] App publiée/en review sur App Store Connect
- [ ] Team ID Apple récupéré
- [ ] DNS `promo.echango.com` configuré, reverse proxy transmet le header `Host`
- [ ] Les 6 variables backend renseignées dans `.env` de prod
- [ ] Mobile rebuild avec `--dart-define=PLAY_STORE_URL=...`/`APP_STORE_URL=...`
- [ ] Vérifier que le build de release **ne** passe **pas** de `--dart-define=API_BASE_URL` (le défaut `env.dart` est déjà la production)
- [ ] Test réel : lien partagé → app installée → ouvre la fiche promo ; app absente → redirige vers le store


---

## Déclaration de confidentialité — les deux stores (2026-08-12)

⚠️ **Elle a changé avec la bascule géographique, et dans le sens qui coûte si
on se trompe.** Jusqu'ici l'app pouvait dire qu'elle ne collectait aucune
donnée du client. Ce n'est plus vrai : le client **enregistre un point** sur la
carte, et ce point est transmis au service pour construire sa liste.

### Ce qu'il faut déclarer

| | Google Play — « Sécurité des données » | App Store Connect — « Confidentialité » |
|---|---|---|
| **Localisation** | **Collectée**, approximative, **fournie par l'utilisateur**. Finalité : *fonctionnalité de l'app*. **Non partagée**, **pas de suivi**, non utilisée pour la publicité | Catégorie *Coarse Location*, usage *App Functionality*, **pas de suivi** |
| Photos | Collectées (photo du commerce, photos de promo) | *Photos or Videos*, usage *App Functionality* |
| Téléphone | Collecté (commerçant uniquement — le client n'a pas de compte) | *Phone Number*, usage *App Functionality* |

### Ce qu'il ne faut PAS déclarer, et pourquoi

- **Aucun suivi (« tracking »).** Rien n'est partagé avec des tiers, il n'y a
  ni identifiant publicitaire, ni régie. `NSPrivacyTracking` vaut `false` dans
  `PrivacyInfo.xcprivacy`.
- **Aucune lecture de position en arrière-plan, aucun historique.** La position
  du capteur sert au centrage de la carte et au calcul des distances, **sur
  l'appareil**. Elle ne quitte l'appareil que si l'utilisateur s'en sert pour
  poser son point, par un geste explicite.

### Le piège à ne pas rejouer

⚠️ **Ne pas sous-déclarer pour « rester simple ».** Déclarer « collectée, sans
suivi » n'ôte rien au produit ; une déclaration fausse coûte un refus — et il y
en a déjà eu un sur ce sujet précis, le 2026-08-05 (5.1.1(iv), justification de
localisation qui ne décrivait pas l'usage réel).

⚠️ **Et ne pas réécrire `NSLocationWhenInUseUsageDescription` pour y parler de
transmission** : elle décrit l'accès au capteur, qui reste local. C'est la
politique de confidentialité qui décrit le point enregistré. Elle est désormais
localisée dans `ios/Runner/{fr,en,ar}.lproj/InfoPlist.strings` — la version du
`Info.plist` n'est qu'un repli.

### Fichiers concernés

- `apps/mobile/ios/Runner/PrivacyInfo.xcprivacy` — manifeste de confidentialité,
  **obligatoire chez Apple**, absent jusqu'au 2026-08-12.
- `apps/mobile/ios/Runner/{fr,en,ar}.lproj/InfoPlist.strings` — les
  justifications de permission dans les trois langues de l'app.
- `CFBundleLocalizations` dans `Info.plist` — sans elle, iOS ne chercherait
  aucun fichier localisé.
