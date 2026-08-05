import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme.dart';
import '../../../domain/enums/onboarding_role.dart';
import '../../../l10n/app_localizations.dart';
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

    if (!context.mounted) return;
    context.go('/onboarding/location');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
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
                onTap: () => _choose(context, ref, OnboardingRole.commercant),
              ),
            ],
          ),
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
