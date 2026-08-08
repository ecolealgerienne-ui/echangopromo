import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../onboarding_navigation.dart';

/// Écran d'explication affiché avant la boîte de dialogue système.
///
/// ⚠️ **Un seul bouton, et il mène TOUJOURS à la demande système.** C'est la
/// condition posée par Apple le 2026-08-07 (deuxième refus 5.1.1(iv)) : un
/// message maison a le droit d'expliquer *pourquoi*, il n'a pas le droit de
/// devenir une décision. Deux boutons — « Activer » et « Continuer » — en
/// faisaient une : le second permettait de fermer le message **sans** que la
/// demande système ait lieu, et le premier portait un libellé qui pousse à
/// accepter. Le choix appartient à la boîte du système, à elle seule.
///
/// Trois choses sont donc interdites ici, et chacune a été refusée nommément :
///   · un libellé de bouton qui encourage (« Activer la localisation ») —
///     Apple demande « Continue » ou « Next » ;
///   · un second bouton, un lien, une croix, un geste de retour qui quitte
///     l'écran sans demander ;
///   · un texte à l'impératif (« Activez la localisation pour… »), qui
///     encourage tout autant qu'un bouton.
class LocationPermissionScreen extends ConsumerWidget {
  const LocationPermissionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                  ),
                  child: Icon(Icons.location_on_outlined,
                      size: 30, color: colorScheme.primary),
                ),
              ),
              const SizedBox(height: 20),
              Text(l10n.onboardingLocationTitle,
                  style: textTheme.headlineMedium),
              const SizedBox(height: 10),
              Text(
                l10n.onboardingLocationSubtitle,
                style: textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              _Perk(label: l10n.onboardingLocationPerkNearby),
              const SizedBox(height: 12),
              _Perk(label: l10n.onboardingLocationPerkRoute),
              const SizedBox(height: 12),
              _Perk(label: l10n.onboardingLocationPerkPrivacy),
              const Spacer(),
              // ⚠️ **Le seul bouton de l'écran, et il n'a qu'une issue.**
              // En ajouter un second — « plus tard », « passer », une croix —
              // recréerait exactement ce qu'Apple a refusé le 2026-08-07.
              FilledButton(
                onPressed: () => requestLocationAndFinish(context, ref),
                child: Text(l10n.onboardingLocationContinue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check, size: 18, color: colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
