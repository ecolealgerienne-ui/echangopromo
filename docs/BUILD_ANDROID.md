# Fabriquer un build Android publiable — depuis n'importe quel poste

> Ce document ne parle **ni** de la mise en place initiale (identité de l'app,
> création du keystore, fiche store, DNS, variables backend) — c'est
> `DEPLOIEMENT_STORES.md` — **ni** des retours des relecteurs — c'est
> `RETOURS_APPLE.md`. Il répond à une seule question : *comment refaire un
> build Android correct, la dixième fois, sur une machine qui n'est pas celle
> de la dernière fois ?*

---

## Pourquoi ce document existe

État relevé le **2026-08-16**, en regardant la Play Console et le dépôt côte à
côte :

| Où | Version |
|---|---|
| Play Console — canal Alpha, **en cours d'examen** | `1.0.0`, code **12** |
| Play Console — ce que les testeurs reçoivent | `0.1.0`, code **5** (6 août) |
| `apps/mobile/pubspec.yaml` du dépôt | `0.1.0+1` |
| Le téléphone de test, installé à la main | `0.1.0`, code **1**, `installer=null` |

Quatre chiffres, quatre valeurs différentes. Et `android/app/build.gradle.kts`
lit `flutter.versionCode` / `flutter.versionName`, donc **directement le
`pubspec`** : le `1.0.0` code 12 soumis à Google n'a donc pas pu sortir de cet
arbre tel qu'il est versionné. Il a été fabriqué avec des `--build-name` /
`--build-number` passés à la main, ou un `pubspec` modifié localement et jamais
commité.

⚠️ **Et `codemagic.yaml` ne porte que des workflows iOS** (vérifié le
2026-08-16 : `flutter build ios`, `flutter build ipa`, aucun `appbundle`). Rien
n'automatise le côté Android, donc rien ne rattrape la main de qui compile.

**Ce que ça coûte, concrètement :**

- personne ne peut dire **quel commit** est dans la version 12 en examen ;
- un `flutter build appbundle` lancé aujourd'hui depuis le dépôt produirait
  **versionCode 1**, que Google refuse (« code de version déjà utilisé ») — et
  le message ne dira pas que la cause est un `pubspec` jamais avancé ;
- le poste qui compile devient une **dépendance non écrite** du produit.

---

## 1. Ce qui voyage avec le dépôt, et ce qui ne doit jamais y entrer

| Élément | Où il vit | Pourquoi |
|---|---|---|
| `version:` de `pubspec.yaml` | **dans le dépôt**, commité | seule source du `versionCode`/`versionName` (§ 2) |
| `android/key.properties` + le `.jks` | **hors dépôt**, dans un coffre | une seule clé de signature par app, **à vie** — la publier, c'est la perdre |
| `API_BASE_URL` | **nulle part** pour un build store | le défaut d'`env.dart` est déjà la production (§ 5) |
| `PLAY_STORE_URL` / `APP_STORE_URL` | ligne de commande | valeurs de publication, sans effet sur l'identité du build |

---

## 2. La version vit dans `pubspec.yaml`, jamais sur la ligne de commande

**Interdit** pour un build destiné à Google :

```bash
flutter build appbundle --release --build-name=1.0.0 --build-number=13   # ✗
```

**Le geste correct** — un commit, puis un build nu :

```yaml
# apps/mobile/pubspec.yaml
version: 1.0.0+13        #  <nom lisible>+<code entier>
```

```bash
flutter build appbundle --release                                        # ✓
```

⚠️ **Pourquoi ce n'est pas une question de goût.** Un drapeau ne laisse aucune
trace : il ne survit ni au changement de poste, ni au `git clone`, ni à la
mémoire de celui qui l'a tapé. Le `pubspec`, si — et c'est *lui* que
`build.gradle.kts` lit. Tant que le numéro reste sur la ligne de commande, deux
machines fabriquent deux versions différentes du même commit sans que rien ne
le signale.

**Choisir le code :** celui affiché dans la Console **+ 1**. Un `versionCode`
ne se réutilise jamais et ne redescend jamais, même si l'envoi précédent a été
abandonné ou refusé.

⚠️ **À faire avant le prochain envoi** : le `pubspec` est à `0.1.0+1` alors que
le code 12 est en examen. Le monter à `1.0.0+13` (ou au-delà, selon ce que la
Console affiche ce jour-là) **et le committer**.

---

## 3. Le commit envoyé doit rester retrouvable — un tag, poussé

`flutter build appbundle` n'inscrit **rien** du commit dans l'artefact : ni
SHA, ni branche, ni date de commit. Rien dans l'AAB, rien dans la Console, ne
permet de remonter au code.

Juste après un envoi accepté par la Console :

```bash
git tag -a android-1.0.0+13 -m "AAB envoye sur le canal Alpha, 2026-08-16"
git push origin android-1.0.0+13
```

Le tag porte **exactement** la version du `pubspec` — c'est ce qui rend la
correspondance vérifiable dans les deux sens. Sans lui, la question « qu'est-ce
qu'il y a dans la 12 ? » n'a pas de réponse, et c'est aujourd'hui le cas.

---

## 4. La clé de signature — le seul objet qui casse vraiment au changement de poste

Google n'accepte **qu'une seule clé de signature par application, à vie**. Un
build fait sur une autre machine doit être signé avec **la même** clé, sinon
l'envoi est refusé.

⚠️ **Et l'absence de clé ne fait PAS échouer le build.**
`android/app/build.gradle.kts` retombe volontairement sur la clé de debug quand
`key.properties` est absent, pour que `flutter run --release` marche en local.
Conséquence sur un poste neuf : `flutter build appbundle --release` **réussit**,
produit un AAB d'apparence normale, et c'est **Google** qui refuse une heure
plus tard. Le symptôme apparaît loin de sa cause.

**Contrôle avant envoi**, sur l'artefact et pas sur la configuration :

```bash
# La release doit être signée par la clé d'upload, pas par la clé de debug.
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
```

L'empreinte SHA-256 affichée doit être celle de votre keystore d'upload. Si
elle correspond à `CN=Android Debug`, `key.properties` manquait.

**Ce qu'il faut avoir avant de compiler sur une nouvelle machine :** le fichier
`.jks`, son mot de passe, celui de l'alias, et le nom de l'alias. Les quatre,
ou rien.

> ⚠️ **À renseigner ici, une fois pour toutes : où la clé est sauvegardée, et
> qui y a accès.** Tant que cette ligne est vide, le produit dépend d'un seul
> disque dur. La perte du keystore n'est pas rattrapable par un rebuild : elle
> demande une réinitialisation de clé d'upload auprès de Google, et sans elle
> l'app ne peut plus jamais être mise à jour.

---

## 5. Vérifier le binaire, pas la ligne de commande

`DEPLOIEMENT_STORES.md` pose la règle : un build store **ne passe pas**
`--dart-define=API_BASE_URL`, le défaut d'`env.dart` étant déjà la production.
Elle est juste, et elle a un angle mort : **un drapeau perdu donne le bon
résultat pour la mauvaise raison.** Le CLAUDE.md documente que `--dart-define`
se perd silencieusement quand `flutter` est lancé via un intermédiaire.

Le contrôle doit donc porter sur l'**artefact**. Recette éprouvée le
2026-08-16 sur un APK arm64 :

```bash
unzip -p build/app/outputs/flutter-apk/app-release.apk lib/arm64-v8a/libapp.so > /tmp/libapp.so

grep -ao "https://promo\.echango\.com" /tmp/libapp.so | wc -l   # attendu : >= 1
grep -ac "10\.0\.2\.2"                  /tmp/libapp.so          # attendu : 0
grep -acE "192\.168\.|127\.0\.0\.1|localhost:3000" /tmp/libapp.so  # attendu : 0
```

Une IP privée dans un binaire envoyé au store, c'est une app qui ne répond
chez personne — et qui marchait parfaitement sur le poste qui l'a compilée.

---

## 6. Liste de contrôle avant chaque envoi Android

- [ ] `pubspec.yaml` : `version:` monté, **commité**, code = celui de la
      Console + 1
- [ ] arbre propre (`git status` vide) — sinon le tag ne désignera pas ce qui
      a été compilé
- [ ] `android/key.properties` présent et pointant sur le bon `.jks`
- [ ] `flutter build appbundle --release` **sans aucun drapeau de version**
- [ ] `keytool -printcert -jarfile …` : empreinte = clé d'upload, pas
      `Android Debug`
- [ ] `libapp.so` : `promo.echango.com` présent, aucune IP privée
- [ ] envoi accepté par la Console, **puis** `git tag android-<version>` poussé
- [ ] noter dans `status_v0.1.md` : version, code, date, canal

---

## 7. Le vrai remède : que le poste de compile cesse d'être une variable

Tout ce qui précède est une discipline humaine, donc elle cédera. Le remède
structurel est un **workflow Android dans `codemagic.yaml`**, à côté des deux
workflows iOS qui existent déjà :

- il part d'un `git clone`, donc de la version du `pubspec` et de rien d'autre ;
- le keystore vient des variables chiffrées de Codemagic, jamais d'un disque ;
- le numéro de build et le commit sont journalisés par la CI, donc la
  correspondance est tenue sans que personne y pense ;
- et le poste du développeur redevient ce qu'il devrait être : indifférent.

Tant que ce workflow n'existe pas, **ce document est la procédure** — et son
existence ne prouve rien : un document ne peut pas échouer (règle #30). Ce qui
prouve, c'est la CI.

### Côté iOS, c'est fait — et ça a révélé la même maladie

`codemagic.yaml` portait `--build-name=1.0.0` **en dur** dans ses deux
workflows. Or App Store Connect affichait **1.0.1 (17)** le 2026-08-16, alors
que ces lignes n'avaient pas bougé depuis trois commits : **la CI annonçait
produire autre chose que ce qui était réellement envoyé.** Le compteur
`$BUILD_NUMBER` de Codemagic n'était pas faux, il était *muet* — il augmente
sans jamais dire de quel commit il vient, et repart de zéro si le projet CI est
recréé.

Les deux drapeaux ont été retirés le 2026-08-16 : `pubspec.yaml` fait foi pour
les deux plateformes. Vérifié de bout en bout — `version: 1.0.1+18` produit un
APK `versionCode=18`, `versionName=1.0.1`, lu dans l'artefact installé.

⚠️ **Le `+18` illustre la seule arithmétique qui vaille ici** : un `pubspec`
alimente **deux** stores aux historiques différents (Apple en était à la build
17, Google au code 12). Le numéro doit dépasser **le plus avancé des deux**, pas
suivre l'un d'eux — sinon c'est l'autre qui refuse, avec un message qui ne
parlera pas de `pubspec`.

⚠️ **Et rejouer un build sur le même commit produit désormais le même numéro**,
donc un refus au second envoi. C'est voulu : c'est ce qui force le commit de
montée de version, donc l'existence de la correspondance version ↔ commit.

---

## 8. Ce qu'on ne sait pas, au 2026-08-16

- **Quel commit est dans la version 12** en examen. Aucun tag, aucune trace.
  La réponse ne peut venir que du poste qui l'a compilée.
- **Si le keystore est sauvegardé** ailleurs que sur ce poste. Voir l'encadré
  du § 4.
- **Il n'existe pas d'équivalent de `RETOURS_APPLE.md` côté Google.** Les
  retours de la Play Console — refus, avertissements de politique, exigences de
  test fermé — ne sont consignés nulle part. Le jour où il y en aura un, il
  faudra le fichier qui va avec.
