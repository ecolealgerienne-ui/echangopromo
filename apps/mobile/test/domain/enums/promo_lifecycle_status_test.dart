import 'package:flutter_test/flutter_test.dart';
import 'package:echango_promo/domain/enums/promo_lifecycle_status.dart';

void main() {
  test('fromValue retrouve chaque valeur backend', () {
    expect(PromoLifecycleStatus.fromValue('brouillon'), PromoLifecycleStatus.brouillon);
    expect(PromoLifecycleStatus.fromValue('publiee'), PromoLifecycleStatus.publiee);
    expect(PromoLifecycleStatus.fromValue('arretee'), PromoLifecycleStatus.arretee);
    expect(PromoLifecycleStatus.fromValue('expiree'), PromoLifecycleStatus.expiree);
  });

  test('fromValue retombe sur expiree pour une valeur inconnue', () {
    expect(PromoLifecycleStatus.fromValue('valeur-inconnue'), PromoLifecycleStatus.expiree);
  });
}
