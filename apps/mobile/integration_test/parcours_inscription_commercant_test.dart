/// **Parcours d'inscription commerçant, de bout en bout** (étape 3 de
/// `docs/METHODE_TEST.md`).
///
/// ── Pourquoi celui-ci ────────────────────────────────────────────────────
///
/// C'est **le premier contact d'un commerçant avec le produit**, et le seul
/// écran qui crée un compte. Jusqu'ici, aucun commerçant n'avait jamais été
/// inscrit depuis l'app : tous venaient du décor, c'est-à-dire d'un `POST`
/// direct. L'écran qui porte l'entrée dans le produit n'était éprouvé par
/// rien.
///
/// Il enchaîne aussi la plus longue suite d'appels du dépôt : créer le compte,
/// **se connecter avec le jeton rendu**, envoyer la photo du registre, puis
/// demander sa vérification. Le commentaire de `_submit` explique pourquoi cet
/// ordre est obligatoire — `/storage/upload` exige une session commerçant qui
/// n'existe pas encore au moment de l'inscription.
///
/// ── L'assertion, et sa contre-mesure ─────────────────────────────────────
///
/// À l'écran : on atterrit sur le tableau de bord, avec son compteur à
/// `0 / plafond` — un compte neuf n'a aucune promo.
///
/// Côté serveur, le script vérifie deux choses qu'un écran ne peut pas
/// prouver seul : **le compte existe** (la connexion avec ces identifiants
/// rend un jeton) et **le registre est en attente de vérification**. Le second
/// est le plus intéressant : il n'est vrai que si l'upload de la photo a
/// abouti ET si `requestRegistreVerification` a suivi. Un écran qui
/// atterrirait sur le tableau de bord en ayant silencieusement sauté ces deux
/// appels afficherait exactement la même chose.
///
/// ── Ce qu'il ne couvre PAS, et pourquoi ──────────────────────────────────
///
/// **La position GPS** (`LocationCaptureField`) : elle ouvre la boîte de
/// dialogue du système, qu'`integration_test` ne peut pas toucher. Elle est
/// facultative à l'inscription (`latitude`/`longitude` nullables), donc le
/// parcours s'en passe — et le dit.
///
/// **La photo de la boutique**, facultative elle aussi. Seule celle du
/// **registre** est obligatoire, et c'est elle qui déclenche la chaîne
/// upload → vérification.
///
/// **La galerie Android**, remplacée par le double décrit dans
/// `faux_selecteur_photo.dart`.
library;

import 'package:echango_promo/domain/enums/categorie.dart';
import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'faux_selecteur_photo.dart';
import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('un commerçant s’inscrit depuis l’app et son registre part',
      (tester) async {
    exigerIdentifiants({
      'TEST_COMMERCANT_TEL': commercantTel,
      'TEST_COMMERCANT_PIN': commercantPin,
      'TEST_PLAFOND': plafondAttendu,
    });

    await reinitialiserAppareil();
    (await SharedPreferences.getInstance())
        .setBool('onboarding_completed', true);
    ignorerErreursDeChargementDImage();
    final faux = await installerFauxSelecteurPhoto();

    app.main();
    await tester.pump(const Duration(seconds: 2));

    // ── 1. La porte : espace commerçant, puis « pas encore inscrit » ─────
    await pomperJusqua(
      tester,
      find.byIcon(Icons.storefront_outlined),
      raison: 'la barre d’onglets client n’est pas apparue',
    );
    await taper(tester, find.byIcon(Icons.storefront_outlined));

    await pomperJusqua(
      tester,
      find.byIcon(Icons.add_business_outlined),
      raison: 'l’écran de connexion commerçant ne propose pas l’inscription',
    );
    await taper(tester, find.byIcon(Icons.add_business_outlined));

    // ── 2. Le formulaire ─────────────────────────────────────────────────
    //
    // Par RANG, dans l'ordre du formulaire (`commercant_fields_form.dart` puis
    // la section PIN) : nom, téléphone, adresse, PIN, confirmation.
    await pomperJusqua(
      tester,
      find.byType(DropdownButtonFormField<Categorie>),
      raison: 'le formulaire d’inscription ne s’est pas ouvert',
    );
    await saisir(tester, 0, 'Commerce Parcours');
    await saisir(tester, 1, commercantTel);
    await saisir(tester, 2, 'Rue du parcours écran');

    // La catégorie, choisie par RANG : les libellés sont traduits, les valeurs
    // viennent de l'enum.
    await taper(tester, find.byType(DropdownButtonFormField<Categorie>));
    await pomperJusqua(
      tester,
      find.byType(DropdownMenuItem<Categorie>),
      raison: 'le menu des catégories ne s’est pas déployé',
    );
    await taper(tester, find.byType(DropdownMenuItem<Categorie>).last);

    // ⚠️ **La cascade wilaya → commune était ici**, deux
    // `DropdownButtonFormField<String>` dont le second ne se remplissait
    // qu'une fois le premier choisi. Retirée le 2026-08-13 : l'adresse en
    // texte libre, saisie plus haut, est le seul repère de lieu que le
    // commerçant fournit — et elle est facultative.

    // ── 3. Descendre : le formulaire fait plus d'un écran ────────────────
    //
    // Les deux champs PIN, la photo du registre, les conditions et le bouton
    // vivent sous la ligne de flottaison — et une `ListView` ne construit pas
    // ce qu'elle n'affiche pas. Le premier passage a échoué là-dessus, en
    // annonçant « champ de rang 3 absent » sur un formulaire qui en compte
    // cinq.
    await defilerJusquaVrai(
      tester,
      () => find.byType(CheckboxListTile).evaluate().isNotEmpty,
      raison: 'le bas du formulaire (conditions) n’a jamais été atteint',
    );

    // ⚠️ Les rangs du haut ne valent plus rien ici : ce qui est sorti par le
    // haut a pu être détruit. On compte ce qui est VISIBLE, et les deux
    // derniers champs texte de l'arbre sont le PIN et sa confirmation — rien
    // d'autre n'en porte plus bas.
    final champs = find.byType(TextFormField).evaluate().length;
    expect(
      champs,
      greaterThanOrEqualTo(2),
      reason: 'les champs PIN ne sont pas à l’écran après défilement '
          '($champs champ(s) visible(s))',
    );
    await saisir(tester, champs - 2, commercantPin);
    await saisir(tester, champs - 1, commercantPin);

    // ── 4. La photo du registre ──────────────────────────────────────────
    //
    // Deux `PhotoPickerField` sur l'écran : la boutique (facultative) puis le
    // registre (obligatoire). Chacun expose directement ses deux boutons —
    // appareil photo et galerie — sans feuille intermédiaire. `.last` désigne
    // le registre, qu'il reste une ou deux galeries construites.
    await taper(tester, find.byIcon(Icons.photo_library_outlined).last);
    await pomperJusquaVrai(
      tester,
      () => faux.appels > 0,
      raison: 'l’app n’a jamais demandé la photo du registre au système',
    );

    // ── 5. Les conditions, puis l'envoi ──────────────────────────────────
    //
    // ⚠️ Redescendre AVANT de cocher : la photo du registre, une fois choisie,
    // s'affiche en aperçu et pousse tout ce qui suit vers le bas. La case à
    // cocher, visible à l'étape 3, ne l'est plus — et ce qui sort de l'écran
    // est détruit.
    await defilerJusquaVrai(
      tester,
      () => find.byType(CheckboxListTile).evaluate().isNotEmpty,
      raison: 'les conditions ne sont plus à l’écran après l’ajout de la photo',
    );
    await taper(tester, find.byType(CheckboxListTile));
    await defilerJusquaVrai(
      tester,
      () => find.byType(FilledButton).evaluate().isNotEmpty,
      raison: 'le bouton d’inscription n’a jamais été atteint',
    );
    await taper(tester, find.byType(FilledButton));

    // ── 6. Le tableau de bord d'un compte NEUF ───────────────────────────
    //
    // La fenêtre est large : l'inscription enchaîne création de compte,
    // connexion, upload de la photo du registre et demande de vérification.
    final attendu = '0 / $plafondAttendu';
    await pomperJusquaVrai(
      tester,
      () => textesRendus().any((t) => normaliserCompteur(t) == attendu),
      raison: 'le tableau de bord du nouveau compte n’affiche pas '
          '« $attendu » — l’inscription n’a pas abouti, ou pas jusqu’au bout',
      limite: const Duration(seconds: 90),
    );
  });
}
