/// **Parcours de création d'une promo, de bout en bout** — de l'écran de
/// connexion au compteur qui s'incrémente (étape 3 de `docs/METHODE_TEST.md`).
///
/// ── Pourquoi celui-ci ────────────────────────────────────────────────────
///
/// C'est **le geste du produit**. Tout le reste — la carte, la liste, la
/// modération, les signalements — n'existe que parce qu'un commerçant a réussi
/// à publier. Et c'est la seule chaîne du dépôt qui traverse tout à la fois :
/// un formulaire, le sélecteur système, la compression, un upload multipart,
/// MinIO, la base, puis le retour à l'écran précédent et son compteur.
///
/// Chaque maillon est éprouvé séparément — `test-storage-upload.sh` pour
/// l'upload, `test-plafond-promos.sh` pour le plafond, `test-promo-cycle.sh`
/// pour le cycle de vie. **Aucun ne les traverse ensemble**, et c'est
/// exactement là que vivent les défauts qui restent : une clé de photo
/// remontée mais jamais renvoyée au formulaire, un `pop()` qui ne rafraîchit
/// pas l'écran d'en dessous, un compteur qui ne se recharge qu'au prochain
/// démarrage.
///
/// ── L'assertion finale, et pourquoi c'est celle-là ───────────────────────
///
/// Le compteur d'emplacements du tableau de bord doit passer de `n / plafond`
/// à `n+1 / plafond`. Il ne se contente pas de prouver que la promo est
/// créée : il prouve que **l'écran l'a appris**. Un parcours qui vérifierait
/// la création côté serveur uniquement laisserait passer le défaut le plus
/// probable — la publication marche, l'écran reste sur son chiffre d'avant, et
/// le commerçant republie en croyant avoir échoué.
///
/// Le décor mesure `n` **auprès du serveur** avant le lancement
/// (`GET /promo/me/slots`, voir `scripts/test-parcours-ecran.sh`). Aucun
/// chiffre n'est écrit ici.
///
/// ── Ce qu'il ne couvre PAS ───────────────────────────────────────────────
///
/// **La galerie Android**, remplacée par un double — voir
/// `faux_selecteur_photo.dart`, qui dit précisément ce qui reste réel.
///
/// **L'onboarding**, déclaré fait avant le démarrage : il a son propre
/// parcours (`parcours_premier_lancement_test.dart`). Les mélanger ferait
/// échouer l'un pour des raisons appartenant à l'autre.
///
/// **Le brouillon** (`Enregistrer sans publier`) : c'est une autre branche de
/// `_submit`, qui mérite son propre parcours plutôt qu'un `if` dans celui-ci.
library;

import 'package:echango_promo/domain/enums/categorie.dart';
import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'faux_selecteur_photo.dart';
import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('publier une promo incrémente le compteur du tableau de bord',
      (tester) async {
    exigerIdentifiants({
      'TEST_COMMERCANT_TEL': commercantTel,
      'TEST_COMMERCANT_PIN': commercantPin,
      'TEST_PLAFOND': plafondAttendu,
      'TEST_EN_LIGNE': enLigneAttendu,
    });

    final avant = int.parse(enLigneAttendu);
    final plafond = int.parse(plafondAttendu);
    // ⚠️ Le décor est censé l'avoir vérifié, mais un parcours qui démarre au
    // plafond trouverait un bouton DÉSACTIVÉ et échouerait trente secondes
    // plus tard en accusant le formulaire. On le dit ici, tout de suite.
    expect(
      avant,
      lessThan(plafond),
      reason: 'le commerçant du décor est déjà au plafond ($avant/$plafond) : '
          'le bouton de création est désactivé, ce parcours n’a pas de place '
          'pour publier',
    );

    await reinitialiserAppareil();
    // Le décor pose des promos dont la photo n'existe pas dans MinIO ; leur
    // 404 ferait échouer ce parcours en accusant le compteur (voir le harnais).
    ignorerErreursDeChargementDImage();

    // L'onboarding est déclaré fait : voir l'en-tête de ce fichier.
    (await SharedPreferences.getInstance())
        .setBool('onboarding_completed', true);

    final faux = await installerFauxSelecteurPhoto();

    app.main();
    await tester.pump(const Duration(seconds: 2));

    // ── 1. Connexion commerçant ──────────────────────────────────────────
    await pomperJusqua(
      tester,
      find.byIcon(Icons.storefront_outlined),
      raison: 'la barre d’onglets client n’est pas apparue',
    );
    await taper(tester, find.byIcon(Icons.storefront_outlined));

    await pomperJusqua(
      tester,
      find.byType(TextFormField),
      raison: 'l’écran de connexion commerçant ne s’est pas ouvert',
    );
    await saisir(tester, 0, commercantTel);
    await saisir(tester, 1, commercantPin);
    await taper(tester, find.byType(FilledButton));

    // ── 2. Le tableau de bord, et son chiffre de départ ──────────────────
    //
    // On attend la VALEUR du serveur, pas l'écran : tant que
    // `GET /promo/me/slots` n'a pas répondu, le compteur affiché ne mesure
    // rien (c'est le défaut qui a motivé le premier parcours).
    await pomperJusquaVrai(
      tester,
      () => textesRendus()
          .any((t) => normaliserCompteur(t) == '$avant / $plafond'),
      raison: 'le compteur d’emplacements n’a jamais affiché « $avant / '
          '$plafond » avant la création',
      limite: const Duration(seconds: 40),
    );

    // ── 3. Le formulaire ─────────────────────────────────────────────────
    //
    // Le bouton de création porte `Icons.add`, ou `Icons.block` s'il est
    // désactivé — l'attente échouerait donc en nommant le plafond, et non en
    // accusant un bouton absent.
    await taper(tester, find.byIcon(Icons.add));
    await pomperJusqua(
      tester,
      find.byIcon(Icons.add_a_photo_outlined),
      raison: 'le formulaire de promo ne s’est pas ouvert',
    );

    // ── 4. La photo, en passant par la feuille de choix ──────────────────
    await taper(tester, find.byIcon(Icons.add_a_photo_outlined));
    await pomperJusqua(
      tester,
      find.byIcon(Icons.photo_library_outlined),
      raison: 'la feuille « appareil photo / galerie » ne s’est pas ouverte',
    );
    await taper(tester, find.byIcon(Icons.photo_library_outlined));

    await pomperJusquaVrai(
      tester,
      () => faux.appels > 0,
      raison: 'l’app n’a jamais demandé de photo au système — le tap est '
          'parti dans le vide',
    );
    // ⚠️ Le double rend la même photo quelle que soit la source ; c'est ICI
    // qu'on vérifie que le tap a atterri sur « galerie » et non sur
    // « appareil photo ». Sans cette ligne, les deux entrées de la feuille
    // seraient interchangeables et un tap décalé passerait au vert.
    expect(
      faux.derniereSource,
      ImageSource.gallery,
      reason: 'le tap a atterri sur la mauvaise entrée de la feuille',
    );

    // ── 5. Le reste du formulaire ────────────────────────────────────────
    //
    // Par RANG : description, prix avant, prix après (`promo_form_fields.dart`).
    await saisir(tester, 0, 'Parcours écran — création de bout en bout');
    await saisir(tester, 1, '1200');
    await saisir(tester, 2, '900');

    // La catégorie est pré-remplie depuis le profil du commerçant, mais on la
    // choisit explicitement : un parcours qui dépendrait du pré-remplissage
    // échouerait sur la validation du formulaire — visible, mais en accusant
    // le mauvais coupable.
    await taper(tester, find.byType(DropdownButtonFormField<Categorie>));
    await pomperJusqua(
      tester,
      find.byType(DropdownMenuItem<Categorie>),
      raison: 'le menu des catégories ne s’est pas déployé',
    );
    // `.last` et non `.first` : l'élément sélectionné est aussi rendu dans le
    // champ lui-même, en plus du menu ouvert.
    await taper(tester, find.byType(DropdownMenuItem<Categorie>).last);

    // ── 6. Publier ───────────────────────────────────────────────────────
    //
    // `LoadingButton` rend un `FilledButton` ; « Enregistrer en brouillon »
    // est un `OutlinedButton`. Les deux ne se confondent pas.
    await taper(tester, find.byType(FilledButton));

    // ── 7. Le compteur a-t-il appris ? ───────────────────────────────────
    //
    // La fenêtre est large : l'upload de la photo traverse la compression, le
    // réseau, MinIO, puis la création. 90 s couvre un émulateur lent sans
    // rendre le parcours interminable en cas d'échec réel.
    final attendu = '${avant + 1} / $plafond';
    await pomperJusquaVrai(
      tester,
      () => textesRendus().any((t) => normaliserCompteur(t) == attendu),
      raison: 'après publication, le compteur n’affiche toujours pas '
          '« $attendu » — la promo est peut-être créée sans que l’écran '
          'l’ait appris',
      limite: const Duration(seconds: 90),
    );
  });
}
