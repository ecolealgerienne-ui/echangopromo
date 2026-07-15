import 'package:flutter_test/flutter_test.dart';
import 'package:echango_promo/features/shared/validators/pin_validator.dart';
import '../../../support/localized_context.dart';

void main() {
  // `validatePin`/`validateExistingPin` retournent un validateur lié au
  // `BuildContext` (message d'erreur localisé) — nécessite un contexte avec
  // `AppLocalizations` résolu.
  testWidgets('validatePin — 6 à 12 chiffres (décision produit 2026-07-13)', (tester) async {
    final context = await pumpLocalizedContext(tester);
    final validate = validatePin(context);

    expect(validate('123456'), isNull, reason: 'accepte 6 chiffres');
    expect(validate('123456789012'), isNull, reason: 'accepte 12 chiffres');

    expect(validate('12345'), isNotNull, reason: 'rejette moins de 6 chiffres');
    expect(validate('1234567890123'), isNotNull, reason: 'rejette plus de 12 chiffres');
    expect(validate('12a456'), isNotNull, reason: 'rejette les caractères non numériques');
    expect(validate(null), isNotNull, reason: 'rejette null');
    expect(validate(''), isNotNull, reason: 'rejette vide');
  });

  testWidgets('validateExistingPin — reste permissif sur 4 à 12 chiffres (PIN fixés avant le 2026-07-13)',
      (tester) async {
    final context = await pumpLocalizedContext(tester);
    final validate = validateExistingPin(context);

    expect(validate('1234'), isNull, reason: 'accepte un ancien PIN à 4 chiffres');
    expect(validate('123456789012'), isNull, reason: 'accepte 12 chiffres');

    expect(validate('123'), isNotNull, reason: 'rejette moins de 4 chiffres');
    expect(validate('1234567890123'), isNotNull, reason: 'rejette plus de 12 chiffres');
    expect(validate(null), isNotNull, reason: 'rejette null');
    expect(validate(''), isNotNull, reason: 'rejette vide');
  });
}
