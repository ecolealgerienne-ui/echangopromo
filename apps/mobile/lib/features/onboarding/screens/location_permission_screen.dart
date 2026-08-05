import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../onboarding_navigation.dart';

/// Demande de localisation « maison », affichée avant la boîte de dialogue
/// système (voir `requestLocationAndFinish` pour le pourquoi de cet ordre).
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
              FilledButton(
                onPressed: () => requestLocationAndFinish(context, ref),
                child: Text(l10n.onboardingLocationEnable),
              ),
              const SizedBox(height: 4),
              TextButton(
                // ⚠️ **Ce bouton TERMINE l'onboarding.** Il menait à un
                // second écran qui redemandait la même chose — ce qu'Apple a
                // refusé le 2026-08-05 (5.1.1(iv) : « encourages users to
                // allow »). La proposition existe toujours, mais là où elle a
                // un sens : sur la carte, qui ne fonctionne pas sans position.
                onPressed: () => skipLocationAndFinish(context, ref),
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
