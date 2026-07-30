import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/theme_mode_provider.dart';

/// Bascule clair/sombre, posée à côté du sélecteur de langue. Un simple
/// bouton et non un menu, contrairement à `LanguageSwitcherButton` : avec
/// deux valeurs seulement, un menu déroulant demanderait deux gestes pour
/// faire ce qu'un appui suffit à faire.
///
/// L'icône montre le mode vers lequel on va, pas le mode courant — c'est la
/// convention qui se lit le mieux sur un bouton d'action.
class ThemeModeButton extends ConsumerWidget {
  const ThemeModeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    return IconButton(
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      tooltip: isDark ? l10n.themeSwitchToLight : l10n.themeSwitchToDark,
      onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
    );
  }
}
