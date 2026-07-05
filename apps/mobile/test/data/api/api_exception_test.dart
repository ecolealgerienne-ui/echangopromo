import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echango_promo/data/api/api_exception.dart';

const _fr = Locale('fr');

void main() {
  group('ApiException.displayMessage', () {
    test('code connu : utilise le texte localisé, pas le message backend', () {
      final error = ApiException(400, 'AUTH_INVALID_CREDENTIALS', 'message backend brut');
      expect(error.displayMessage(_fr), 'Identifiants invalides.');
    });

    test('code inconnu ou absent (ex: VALIDATION_ERROR) : retombe sur le message backend', () {
      final withUnknownCode = ApiException(400, 'VALIDATION_ERROR', 'Le PIN doit contenir 4 à 6 chiffres');
      expect(withUnknownCode.displayMessage(_fr), 'Le PIN doit contenir 4 à 6 chiffres');

      final withoutCode = ApiException(0, null, 'Impossible de contacter le serveur.');
      expect(withoutCode.displayMessage(_fr), 'Impossible de contacter le serveur.');
    });

    test('langue différente : bascule sur le mapping anglais', () {
      final error = ApiException(400, 'AUTH_INVALID_CREDENTIALS', 'message backend brut');
      expect(error.displayMessage(const Locale('en')), 'Invalid credentials.');
    });
  });
}
