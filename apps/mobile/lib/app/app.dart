import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_mode_provider.dart';
import 'router.dart';
import 'theme.dart';

class EchangoPromoApp extends ConsumerWidget {
  const EchangoPromoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      routerConfig: router,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: supportedAppLocales,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Piloté par l'utilisateur, pas par le réglage du téléphone : le thème
      // clair est l'identité de l'app, et `ThemeMode.system` la faisait
      // disparaître pour quiconque a son téléphone en sombre.
      themeMode: themeMode,
    );
  }
}
