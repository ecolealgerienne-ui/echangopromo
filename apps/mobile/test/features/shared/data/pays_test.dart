import 'package:echango_promo/features/shared/data/pays.dart';
import 'package:echango_promo/features/shared/widgets/telephone_field.dart';
import 'package:flutter_test/flutter_test.dart';

/// La table des pays est **générée** (`tool/generer_pays.mjs`). Ce banc ne
/// vérifie donc pas son contenu ligne à ligne — il vérifie les propriétés dont
/// le reste de l'app dépend, et qu'une régénération pourrait casser en silence.
void main() {
  group('la table des pays', () {
    test('couvre les 245 pays connus de libphonenumber', () {
      // Le chiffre est daté (2026-08-15) : il bougera le jour où la
      // bibliothèque bougera, et c'est précisément ce qu'on veut voir passer
      // dans un diff plutôt que découvrir en production.
      expect(kTousLesPays, hasLength(245));
    });

    test('n’a ni doublon ni code ISO malformé', () {
      final codes = kTousLesPays.map((p) => p.iso).toList();
      expect(codes.toSet(), hasLength(codes.length));
      for (final code in codes) {
        expect(code, matches(RegExp(r'^[A-Z]{2}$')), reason: code);
      }
    });

    test('porte un indicatif et les trois noms pour chaque pays', () {
      for (final pays in kTousLesPays) {
        expect(pays.indicatif, isNotEmpty, reason: pays.iso);
        expect(pays.indicatif, matches(RegExp(r'^\d+$')), reason: pays.iso);
        expect(pays.nomFr, isNotEmpty, reason: pays.iso);
        expect(pays.nomEn, isNotEmpty, reason: pays.iso);
        expect(pays.nomAr, isNotEmpty, reason: pays.iso);
      }
    });

    test('décrit l’Algérie comme le serveur l’attend', () {
      final dz = paysParIso('DZ');
      expect(dz, isNotNull);
      expect(dz!.indicatif, '213');
      expect(dz.nomFr, 'Algérie');
      expect(dz.nomAr, 'الجزائر');
      // L'exemple sert de `hintText` : vide, le champ n'aurait plus aucune
      // indication de format depuis le retrait de « +213... ».
      expect(dz.exemple, isNotEmpty);
    });

    test('calcule le drapeau depuis les lettres ISO', () {
      expect(paysParIso('DZ')!.drapeau, '🇩🇿');
      expect(paysParIso('AE')!.drapeau, '🇦🇪');
    });

    test('rend null sur un code inconnu, pas un repli plausible', () {
      // ⚠️ Le cas qui doit ÉCHOUER : un repli silencieux sur l'Algérie ferait
      // afficher « +213 » devant un numéro qui n'est pas algérien.
      expect(paysParIso('ZZ'), isNull);
      expect(paysParIso(''), isNull);
      expect(paysParIso('dz'), isNull, reason: 'la casse compte');
    });

    test('retombe sur l’anglais pour une langue inconnue', () {
      final dz = paysParIso('DZ')!;
      expect(dz.nomPour('fr'), 'Algérie');
      expect(dz.nomPour('ar'), 'الجزائر');
      expect(dz.nomPour('en'), 'Algeria');
      expect(dz.nomPour('es'), 'Algeria');
    });
  });

  test('le pays par défaut est l’Algérie, comme côté serveur', () {
    // Le serveur applique `PAYS_PAR_DEFAUT = 'DZ'` quand le champ est absent
    // (`apps/backend/src/commercant/telephone.ts`). Deux défauts différents
    // feraient créer un compte sous un pays que l'app n'a jamais affiché.
    expect(kPaysParDefaut.iso, 'DZ');
  });
}
