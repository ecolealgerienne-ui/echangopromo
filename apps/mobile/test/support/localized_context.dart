import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echango_promo/l10n/app_localizations.dart';

/// Pompe un `MaterialApp` minimal dans la langue demandée et retourne un
/// `BuildContext` avec `AppLocalizations` résolu — nécessaire pour tester
/// tout code qui dépend de `AppLocalizations.of(context)` (validateurs,
/// libellés d'enum) en dehors d'un widget test complet.
Future<BuildContext> pumpLocalizedContext(
  WidgetTester tester, {
  Locale locale = const Locale('fr'),
}) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) {
        capturedContext = context;
        return const SizedBox.shrink();
      },
    ),
  ));
  return capturedContext;
}
