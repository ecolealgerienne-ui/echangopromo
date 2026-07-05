import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/locale_provider.dart';

/// Bouton de changement de langue (FR/EN/AR) — ajouté à l'`AppBar` de tous
/// les écrans plutôt qu'à un seul endroit central, faute de shell/navigation
/// partagée entre les 3 rôles (audit qualité de code, même logique que
/// `ErrorText`/`LoadingButton` : un seul widget, dupliqué à l'usage).
class LanguageSwitcherButton extends ConsumerWidget {
  const LanguageSwitcherButton({super.key});

  String _labelFor(AppLocalizations l10n, Locale locale) {
    switch (locale.languageCode) {
      case 'en':
        return l10n.languageEnglish;
      case 'ar':
        return l10n.languageArabic;
      default:
        return l10n.languageFrench;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(localeProvider);

    return PopupMenuButton<Locale>(
      icon: const Icon(Icons.language),
      tooltip: l10n.languageSwitchTooltip,
      onSelected: (locale) => ref.read(localeProvider.notifier).setLocale(locale),
      itemBuilder: (context) => [
        for (final locale in supportedAppLocales)
          PopupMenuItem(
            value: locale,
            child: Row(
              children: [
                if (locale == current) const Icon(Icons.check, size: 18) else const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(_labelFor(l10n, locale)),
              ],
            ),
          ),
      ],
    );
  }
}
