import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echango_promo/domain/enums/categorie.dart';
import 'package:echango_promo/domain/enums/promo_lifecycle_status.dart';
import 'package:echango_promo/features/shared/l10n/enum_labels.dart';
import '../../../support/localized_context.dart';

void main() {
  testWidgets('promoLifecycleLabel — publiée bascule sur "expirée" une fois la date dépassée',
      (tester) async {
    final context = await pumpLocalizedContext(tester);

    expect(
      promoLifecycleLabel(context, PromoLifecycleStatus.brouillon, isExpired: false),
      'Brouillon',
    );
    expect(
      promoLifecycleLabel(context, PromoLifecycleStatus.publiee, isExpired: false),
      'Publiée',
    );
    expect(
      promoLifecycleLabel(context, PromoLifecycleStatus.publiee, isExpired: true),
      'Expirée',
    );
    expect(
      promoLifecycleLabel(context, PromoLifecycleStatus.arretee, isExpired: false),
      'Arrêtée',
    );
    expect(
      promoLifecycleLabel(context, PromoLifecycleStatus.expiree, isExpired: false),
      'Expirée',
    );
    expect(
      promoLifecycleLabel(context, PromoLifecycleStatus.supprimee, isExpired: false),
      'Supprimée',
    );
  });

  testWidgets('categorieLabel — traduit selon la langue courante', (tester) async {
    final frContext = await pumpLocalizedContext(tester);
    expect(categorieLabel(frContext, Categorie.alimentation), 'Alimentation');

    final enContext = await pumpLocalizedContext(tester, locale: const Locale('en'));
    expect(categorieLabel(enContext, Categorie.alimentation), 'Food');

    final arContext = await pumpLocalizedContext(tester, locale: const Locale('ar'));
    expect(categorieLabel(arContext, Categorie.alimentation), 'المواد الغذائية');
  });
}
