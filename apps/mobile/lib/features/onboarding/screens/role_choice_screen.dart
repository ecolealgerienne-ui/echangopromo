import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme.dart';
import '../../../domain/enums/onboarding_role.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/widgets/app_settings_actions.dart';
import '../../../providers/core_providers.dart';

/// Deuxième écran du premier lancement : oriente l'accueil, sans créer de
/// compte. Le choix commerçant marque l'onboarding comme terminé et bascule
/// directement sur `/commercant` (connexion ou tableau de bord selon la
/// session) — le parcours localisation ne concerne que le client.
class RoleChoiceScreen extends ConsumerWidget {
  const RoleChoiceScreen({super.key});

  Future<void> _choose(
      BuildContext context, WidgetRef ref, OnboardingRole role) async {
    final store = ref.read(onboardingStoreProvider);
    await store.setRole(role);

    if (role == OnboardingRole.commercant) {
      await store.markCompleted();
      if (!context.mounted) return;
      context.go('/commercant');
      return;
    }

    // ⚠️ **`markCompleted()` DOIT être appelé ici depuis le 2026-08-12.**
    // Il ne l'était que dans l'écran de localisation, supprimé avec la
    // bascule : sans cette ligne, l'onboarding ne se terminerait jamais pour
    // un client et reviendrait **à chaque lancement** (`splash_screen` relit
    // `isCompleted()`). Rien ne l'aurait signalé — ni compilation, ni test.
    await store.markCompleted();
    if (!context.mounted) return;
    // Plus d'écran de permission au démarrage : le client n'a aucune
    // permission à accorder pour voir des promos. L'invitation à activer la
    // localisation reste contextuelle, sur la carte — c'est ce placement qui a
    // levé le refus App Store 5.1.1(iv) du 2026-08-05.
    context.go('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        // ⚠️ **Le sélecteur de langue manquait ici, et c'était le pire endroit
        // pour l'oublier** : c'est le PREMIER écran, et le seul que voit un
        // utilisateur qui ne lit pas le français. Les 22 autres écrans le
        // portent via leur `AppBar` — celui-ci n'en a pas, et il est passé
        // entre les mailles (signalé le 2026-08-13).
        //
        // Épinglé en haut, HORS de la colonne centrée : placé dedans, il aurait
        // simplement flotté juste au-dessus de « Bienvenue » au lieu d'occuper
        // le coin de l'écran. Et pas d'`AppBar` ajoutée pour l'occasion : une
        // barre de titre au-dessus de « Bienvenue » ferait doublon.
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: 8),
                child: AppSettingsActions(),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.onboardingWelcomeTitle,
                        style: textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      l10n.onboardingWelcomeSubtitle,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _RoleCard(
                      icon: Icons.person_outline,
                      title: l10n.onboardingRoleClientTitle,
                      description: l10n.onboardingRoleClientDesc,
                      onTap: () => _choose(context, ref, OnboardingRole.client),
                    ),
                    const SizedBox(height: 12),
                    _RoleCard(
                      icon: Icons.storefront_outlined,
                      title: l10n.onboardingRoleMerchantTitle,
                      description: l10n.onboardingRoleMerchantDesc,
                      tintWithSecondary: true,
                      onTap: () =>
                          _choose(context, ref, OnboardingRole.commercant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.tintWithSecondary = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  /// Le commerçant est teinté en safran, le client en terracotta : les deux
  /// cartes se distinguent au premier coup d'œil sans texte supplémentaire.
  final bool tintWithSecondary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tint =
        tintWithSecondary ? colorScheme.secondary : colorScheme.primary;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(icon, color: tint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
