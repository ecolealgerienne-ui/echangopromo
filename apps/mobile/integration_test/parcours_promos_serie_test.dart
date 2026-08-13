/// **Décor — N promos d'affilée par le formulaire commerçant.**
///
/// ── Pourquoi ce fichier existe à côté de `parcours_creation_promo_test` ─────
///
/// Ce n'est **pas** un parcours de vérification : c'est un producteur de décor
/// qui emprunte le chemin réel. `parcours_creation_promo_test` éprouve *une*
/// création et son effet sur le compteur — c'est lui qui juge. Celui-ci
/// *fabrique*, et il le fait par l'écran plutôt que par l'API pour une seule
/// raison : un décor produit par un chemin que le produit n'emprunte pas ne
/// prouve rien sur ce chemin.
///
/// ── ⚠️ UN seul lancement pour TOUS les commerçants ──────────────────────────
///
/// Le coût d'un parcours n'est pas le geste, c'est le **lancement** :
/// compilation, installation, démarrage. Environ trois minutes, pour une
/// trentaine de secondes de travail utile.
///
/// ⚠️ Et on ne peut pas se contenter d'un lancement **par commerçant** : les
/// identifiants voyagent en `--dart-define`, donc en `String.fromEnvironment`,
/// qui est résolu **à la compilation**. Changer de numéro entre deux passages
/// force une reconstruction complète — `--use-application-binary` ne sauverait
/// rien, le binaire n'étant pas le même.
///
/// La seule façon de ne compiler qu'une fois est donc de faire tenir **toute**
/// la liste dans une seule valeur, et de boucler dessus à l'intérieur de l'app :
/// connexion, N créations, déconnexion, commerçant suivant. Neuf commerçants ×
/// cinq promos passent d'une quarantaine de lancements à **un**.
///
/// ── ⚠️ Cinq, et pas six ─────────────────────────────────────────────────────
///
/// Deux plafonds serveur valent 5 et se rejoignent ici : **5 créations par
/// 24 h** (anti-abus) et **5 promos actives** par commerçant. Demander six
/// promos ne produirait pas six échecs identiques mais deux refus différents,
/// et le décor accuserait le formulaire. Le nombre vient donc de l'appelant,
/// qui le tient du serveur — jamais d'une constante écrite ici (règle 32).
///
/// ── Ce qu'il vérifie quand même ─────────────────────────────────────────────
///
/// Un producteur qui ne vérifie rien produit des décors faux en silence. Après
/// chaque création, il attend que **le compteur d'emplacements ait avancé d'un
/// cran** : c'est le seul signal, à l'écran, que le serveur a réellement
/// enregistré. Sans lui, un formulaire qui échoue laisserait le décor annoncer
/// cinq promos là où il n'y en a aucune.
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

/// Combien de promos créer par commerçant. Vient de l'appelant, qui a lu le
/// plafond du serveur — jamais d'une constante écrite ici (règle 32).
const String promosACreer = String.fromEnvironment('TEST_PROMOS_A_CREER');

/// La liste des commerçants, `tel:pin` séparés par des virgules.
///
/// ⚠️ Tout dans **une** valeur, et c'est la raison d'être de ce fichier : un
/// `--dart-define` par commerçant imposerait une compilation par commerçant.
const String commercantsSerie = String.fromEnvironment('TEST_COMMERCANTS');

/// Préfixe des descriptions, pour reconnaître ce décor en base à l'œil nu.
const String promoPrefixe =
    String.fromEnvironment('TEST_PROMO_PREFIXE', defaultValue: 'Promo décor');

/// Lit « X / Y » parmi les textes rendus. `null` tant que le serveur n'a pas
/// répondu — surtout pas `0`, qui ferait croire à un commerçant sans promo et
/// lancerait cinq créations de trop (règle 29).
(int, int)? compteurAffiche() {
  for (final t in textesRendus()) {
    final m = RegExp(r'^(\d+) / (\d+)$').firstMatch(normaliserCompteur(t));
    if (m != null) {
      return (int.parse(m.group(1)!), int.parse(m.group(2)!));
    }
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('remplir le décor : N promos par commerçant, en un lancement',
      (tester) async {
    exigerIdentifiants({
      'TEST_COMMERCANTS': commercantsSerie,
      'TEST_PROMOS_A_CREER': promosACreer,
    });

    final vise = int.parse(promosACreer);
    final comptes = commercantsSerie
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => (e.split(':')[0], e.split(':')[1]))
        .toList();
    expect(comptes, isNotEmpty,
        reason: 'TEST_COMMERCANTS ne porte aucun couple « tel:pin »');

    await reinitialiserAppareil();
    // Les promos déjà en base portent des photos absentes de MinIO ; leur 404
    // ferait échouer ce producteur en accusant le compteur (voir le harnais).
    ignorerErreursDeChargementDImage();
    (await SharedPreferences.getInstance())
        .setBool('onboarding_completed', true);

    final faux = await installerFauxSelecteurPhoto();
    // Commerçants que le serveur a refusés pour une raison métier. Ils ne font
    // PAS échouer la course — mais ils sont nommés à la fin, sinon un décor
    // incomplet passerait pour un décor complet (règle 29).
    final bloques = <String>[];

    app.main();
    await tester.pump(const Duration(seconds: 2));

    for (var m = 0; m < comptes.length; m++) {
      final (tel, pin) = comptes[m];
      // Décalage du cycle des catégories, propre à ce commerçant.
      final decalage = m;
      // ── Connexion ───────────────────────────────────────────────────────
      await pomperJusqua(
        tester,
        find.byIcon(Icons.storefront_outlined),
        raison: 'la barre d’onglets client n’est pas apparue (avant $tel)',
      );
      await taper(tester, find.byIcon(Icons.storefront_outlined));
      await pomperJusqua(
        tester,
        find.byType(TextFormField),
        raison: 'l’écran de connexion commerçant ne s’est pas ouvert ($tel)',
      );
      await saisir(tester, 0, tel);
      await saisir(tester, 1, pin);
      await taper(tester, find.byType(FilledButton));

      // ── ⚠️ Le point de départ se LIT, il ne se suppose pas ──────────────
      //
      // Chaque commerçant part d'un état différent, et un producteur qui
      // supposerait « zéro » créerait cinq promos de trop chez celui qui en a
      // déjà. On attend donc que `GET /promo/me/slots` ait répondu, et on lit
      // ce qu'il dit. Tant que rien n'est affiché, on ne sait pas — ce n'est
      // pas zéro.
      await pomperJusquaVrai(
        tester,
        () => compteurAffiche() != null,
        raison: 'le compteur d’emplacements ne s’est jamais affiché pour $tel',
        limite: const Duration(seconds: 40),
      );
      final (depart, plafond) = compteurAffiche()!;

      // On ne dépasse ni le plafond d'actives, ni ce qui est demandé.
      final combien = (vise - depart).clamp(0, plafond - depart);
      debugPrint('[DÉCOR] $tel : $depart / $plafond en ligne, '
          '$combien à créer');

      for (var i = 0; i < combien; i++) {
        final rang = depart + i;
        // Choisie ici : elle sert à la fois au menu déroulant et à la
        // description, pour qu'on la reconnaisse en base à l'œil nu.
        final categorie =
            Categorie.values[(decalage + i) % Categorie.values.length];

        await taper(tester, find.byIcon(Icons.add));
        await pomperJusqua(
          tester,
          find.byIcon(Icons.add_a_photo_outlined),
          raison: 'le formulaire ne s’est pas ouvert ($tel, ${i + 1}/$combien)',
        );

        // ⚠️ Comparé au compteur D'AVANT cette itération, jamais à zéro : au
        // deuxième tour `faux.appels` vaut déjà 1, et un `> 0` serait vrai sans
        // que le tap ait rien déclenché. Une assertion qui reste vraie après le
        // premier tour ne mesure plus rien.
        final appelsAvant = faux.appels;
        await taper(tester, find.byIcon(Icons.add_a_photo_outlined));
        await pomperJusqua(
          tester,
          find.byIcon(Icons.photo_library_outlined),
          raison: 'la feuille photo ne s’est pas ouverte ($tel, ${i + 1})',
        );
        await taper(tester, find.byIcon(Icons.photo_library_outlined));
        await pomperJusquaVrai(
          tester,
          () => faux.appels > appelsAvant,
          raison: 'l’app n’a pas demandé de photo au système ($tel, ${i + 1})',
        );
        expect(faux.derniereSource, ImageSource.gallery,
            reason: 'le tap a atterri sur la mauvaise entrée de la feuille');

        // Des prix qui varient : un décor où les cinq promos sont identiques
        // ne permet ni de les distinguer à l’écran, ni d’éprouver un tri par
        // remise.
        await saisir(
            tester, 0, '$promoPrefixe ${rang + 1} — ${categorie.value}');
        await saisir(tester, 1, '${1000 + i * 100}');
        await saisir(tester, 2, '${700 - i * 50}');

        // ── ⚠️ Une catégorie DIFFÉRENTE à chaque promo ────────────────────
        //
        // Le producteur prenait `.last`, donc « autre » pour les cinq — un
        // décor où tout partage une catégorie **rend le filtre inéprouvable** :
        // « le filtre montre les bonnes promos » et « le filtre ne filtre
        // rien » y donnent le même écran.
        //
        // On décale aussi par commerçant (`decalage`), sinon les trois
        // commerces d’une même ville porteraient exactement les mêmes cinq
        // catégories, et un filtre appliqué à une ville rendrait toujours tout
        // le monde ou personne.
        //
        // ⚠️ Choisi par **valeur**, jamais par rang : la liste rendue contient
        // aussi la copie affichée dans le champ lui-même, donc un `.at(i)`
        // viserait à côté d’un cran. `.last` sur la valeur voulue lève
        // l’ambiguïté — même précaution que le parcours de création.
        await taper(tester, find.byType(DropdownButtonFormField<Categorie>));
        await pomperJusqua(
          tester,
          find.byType(DropdownMenuItem<Categorie>),
          raison: 'le menu des catégories ne s’est pas déployé ($tel)',
        );
        await taper(
          tester,
          find
              .byWidgetPredicate((w) =>
                  w is DropdownMenuItem<Categorie> && w.value == categorie)
              .last,
        );

        await taper(tester, find.byType(FilledButton));

        // ── ⚠️ Le compteur a-t-il avancé ? ────────────────────────────────
        //
        // C’est le seul signal, à l’écran, que le SERVEUR a enregistré. Sans
        // cette attente, un producteur qui échoue enchaînerait quand même, et
        // le décor annoncerait cinq promos là où il n’y en a aucune — faux, et
        // en silence.
        //
        // ⚠️ **Mais un refus MÉTIER n’est pas un échec de ce producteur**, et
        // le confondre coûte cher. Mesuré le 2026-08-13 : le serveur refusait
        // en « Plafond de 5 créations de promo par 24h atteint », le producteur
        // attendait 90 s puis accusait le compteur, et les HUIT commerçants
        // suivants n’étaient jamais servis. Le tableau de bord, lui, affichait
        // « 0 / 5 » et un bouton actif : les deux plafonds sont indépendants et
        // l’écran n’expose que celui des promos ACTIVES.
        //
        // On attend donc l’un OU l’autre, et on distingue les deux.
        var avance = false;
        await pomperJusquaVrai(
          tester,
          () {
            avance = compteurAffiche()?.$1 == rang + 1;
            return avance || refusVisible();
          },
          raison: 'après la création ${i + 1}/$combien de $tel, ni compteur à '
              '« ${rang + 1} / $plafond » ni refus lisible à l’écran',
          limite: const Duration(seconds: 90),
        );
        if (!avance) {
          // Le serveur a refusé, et il a dit pourquoi. Ce commerçant s’arrête
          // là ; les suivants n’ont rien à voir avec son quota.
          final motif = textesRendus().firstWhere(
            (t) => t.contains('Plafond') || t.contains('plafond'),
            orElse: () => 'refus non identifié',
          );
          debugPrint('[DÉCOR] $tel : arrêté à $i/$combien — $motif');
          bloques.add('$tel : $motif');
          // Revenir au tableau de bord pour pouvoir se déconnecter.
          await taper(tester, find.byType(BackButtonIcon));
          await tester.pump(const Duration(seconds: 2));
          break;
        }
      }

      // ── Déconnexion, pour laisser la place au suivant ───────────────────
      //
      // Par le menu, comme un commerçant : `authControllerProvider.logout()`
      // vide la session ET ramène à l’accueil client, d’où la barre d’onglets
      // retrouvée au tour suivant.
      await taper(tester, find.byIcon(Icons.account_circle_outlined));
      await pomperJusqua(
        tester,
        find.byType(PopupMenuItem<String>),
        raison: 'le menu du compte ne s’est pas déployé ($tel)',
      );
      await taper(tester, find.byType(PopupMenuItem<String>).last);
      await tester.pump(const Duration(seconds: 2));
    }

    // ⚠️ Le bilan est IMPRIMÉ, pas seulement compté : un décor partiel qui se
    // tait est indiscernable d’un décor complet.
    if (bloques.isNotEmpty) {
      debugPrint('[DÉCOR] ${bloques.length} commerçant(s) refusé(s) par le '
          'serveur :');
      for (final b in bloques) {
        debugPrint('[DÉCOR]   - $b');
      }
    }
  });
}

/// Un refus métier est-il affiché ? On cherche le mot « plafond », que les deux
/// refus possibles portent (créations/24 h et promos actives).
///
/// ⚠️ Chercher un mot d’un message serveur est un pis-aller assumé : la vraie
/// solution serait un code d’erreur lisible depuis l’écran, ce que Flutter
/// n’expose pas. On ne recopie donc PAS le chiffre — seulement le mot qui
/// distingue « refusé » de « en cours », et le message complet est réimprimé
/// tel quel pour que personne n’ait à le deviner.
bool refusVisible() =>
    textesRendus().any((t) => t.contains('Plafond') || t.contains('plafond'));
