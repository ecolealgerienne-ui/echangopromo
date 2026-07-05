import 'package:flutter_test/flutter_test.dart';
import 'package:echango_promo/features/shared/validators/pin_validator.dart';
import '../../../support/localized_context.dart';

void main() {
  // `validatePin` retourne désormais un validateur lié au `BuildContext`
  // (message d'erreur localisé) plutôt qu'une fonction figée en français
  // — nécessite un contexte avec `AppLocalizations` résolu.
  testWidgets('validatePin', (tester) async {
    final context = await pumpLocalizedContext(tester);
    final validate = validatePin(context);

    expect(validate('1234'), isNull, reason: 'accepte 4 chiffres');
    expect(validate('12345'), isNull, reason: 'accepte 5 chiffres');
    expect(validate('123456'), isNull, reason: 'accepte 6 chiffres');

    expect(validate('123'), isNotNull, reason: 'rejette moins de 4 chiffres');
    expect(validate('1234567'), isNotNull, reason: 'rejette plus de 6 chiffres');
    expect(validate('12a4'), isNotNull, reason: 'rejette les caractères non numériques');
    expect(validate(null), isNotNull, reason: 'rejette null');
    expect(validate(''), isNotNull, reason: 'rejette vide');
  });
}
