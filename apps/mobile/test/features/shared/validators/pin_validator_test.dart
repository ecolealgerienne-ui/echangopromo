import 'package:flutter_test/flutter_test.dart';
import 'package:echango_promo/features/shared/validators/pin_validator.dart';

void main() {
  group('validatePin', () {
    test('accepte 4 à 6 chiffres', () {
      expect(validatePin('1234'), isNull);
      expect(validatePin('12345'), isNull);
      expect(validatePin('123456'), isNull);
    });

    test('rejette moins de 4 chiffres', () {
      expect(validatePin('123'), isNotNull);
    });

    test('rejette plus de 6 chiffres', () {
      expect(validatePin('1234567'), isNotNull);
    });

    test('rejette les caractères non numériques', () {
      expect(validatePin('12a4'), isNotNull);
    });

    test('rejette null ou vide', () {
      expect(validatePin(null), isNotNull);
      expect(validatePin(''), isNotNull);
    });
  });
}
