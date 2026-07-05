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
    (`autoVerify`, host `promo.echango.com`, pathPrefix `/promo`) déjà
    ajouté.
  - `ios/Runner/Runner.entitlements` : capacité Associated Domains
    (`applinks:promo.echango.com`) déjà créée en fichier — **doit encore
    être reliée au projet Xcode** (voir section iOS, ne peut pas se faire
    sans Xcode/Mac).
  - `go_router` route déjà `/promo/:id` (`app/router.dart`) : aucun code
    Dart supplémentaire à écrire pour la navigation elle-même une fois la
    vérification App Links/Universal Links validée par Android/iOS.
- **Backend** (`apps/backend`) :
  - `src/app-links/` (`AppLinksModule`/`AppLinksController`), branché sur
    `promo.echango.com` (voir `@Controller({ host: ... })`), sert :
    - `GET /.well-known/assetlinks.json`
    - `GET /.well-known/apple-app-site-association`
    - `GET /promo/:id` → redirige vers le store (ou une page d'attente
      tant qu'aucun lien store n'est configuré)
  - `.env.example` : 6 nouvelles variables, toutes vides, listées plus
    bas avec leur provenance exacte.

**Ce qu'il reste à faire manuellement** (comptes, identifiants, décisions
produit — rien de tout ça ne peut être deviné ni fait à ta place) est
détaillé ci-dessous, dans l'ordre.

---

## 0. Préalable bloquant : fixer l'identité de l'app

L'`applicationId` Android est encore `com.example.echango_promo` — **la
valeur par défaut générée par Flutter, jamais changée**. Google refuse de
publier sous `com.example.*`. Il faut choisir l'identifiant définitif
**avant** de générer un certificat de signature ou de créer une fiche
App Store, parce que le changer après publication casse la mise à jour
de l'app pour les utilisateurs existants (Android/iOS traitent un
changement d'id comme une app différente).

Suggestion cohérente avec le domaine déjà choisi : `com.echango.promo`
(Android) et le même en bundle identifier iOS.

Recommandé plutôt qu'un renommage manuel (fastidieux : il faut renommer
le dossier de package Kotlin/Java, `build.gradle`, `AndroidManifest.xml`,
le bundle id Xcode...) : le package pub
[`rename`](https://pub.dev/packages/rename) :

```bash
cd apps/mobile
dart pub global activate rename
dart pub global run rename setAppId --targets android,ios --value "com.echango.promo"
dart pub global run rename setBundleId --targets ios --value "com.echango.promo"
```

Vérifier ensuite `android/app/build.gradle` (`applicationId`) et, sous
Xcode (Mac requis), l'onglet *Signing & Capabilities* du target Runner
pour le bundle identifier iOS.

---

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
   contenu, formulaire "Sécurité des données" (l'app collecte : position
   GPS optionnelle, photo, numéro de téléphone — à déclarer honnêtement).
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
   captures d'écran, politique de confidentialité — obligatoire aussi).
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

Aucune de ces variables n'est requise pour démarrer le backend
aujourd'hui (contrairement à `JWT_SECRET`, validé au boot) — les
renseigner active la fonctionnalité, ne pas les renseigner ne casse rien.

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
- [ ] Test réel : lien partagé → app installée → ouvre la fiche promo ; app absente → redirige vers le store
