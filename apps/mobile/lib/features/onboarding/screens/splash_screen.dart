import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/launch_state.dart';
import '../../../app/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/widgets/echango_wordmark.dart';
import '../../../providers/core_providers.dart';

/// Écran d'ouverture animé, affiché à chaque lancement à froid de l'app.
///
/// Le soulignement safran et le badge de réduction reprennent volontairement
/// le langage visuel de l'affiche commerçant (support papier posé en
/// vitrine) : l'app et l'affiche partagent la même signature, c'est ce qui
/// fait reconnaître l'une depuis l'autre.
///
/// C'est ici, et pas dans la redirection du routeur, qu'on décide de la
/// suite : l'onboarding n'a de sens qu'une fois l'animation terminée.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Séquence : le mot-marque monte, le soulignement se dessine, le badge
  /// apparaît, la baseline s'affiche — puis on enchaîne sur le choix du rôle.
  late final Animation<double> _wordmark;
  late final Animation<double> _underline;
  late final Animation<double> _badge;
  late final Animation<double> _tagline;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    Animation<double> phase(double begin, double end,
        {Curve curve = Curves.easeOutCubic}) {
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(begin, end, curve: curve),
      );
    }

    _wordmark = phase(0.0, 0.34);
    _underline = phase(0.30, 0.60, curve: Curves.easeOut);
    _badge = phase(0.52, 0.80, curve: Curves.easeOutBack);
    _tagline = phase(0.72, 1.0);

    _controller.forward();
    _controller.addStatusListener(_onAnimationDone);
  }

  void _onAnimationDone(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    // Petite pause une fois l'animation finie, pour que le splash reste
    // lisible plutôt que de disparaître à l'instant précis où il se termine.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      // Avant de naviguer : sans ça, la redirection du routeur renverrait
      // aussitôt sur le splash puisqu'elle intercepte '/'.
      markSplashShown();
      final onboardingDone = ref.read(onboardingStoreProvider).isCompleted();
      context.go(onboardingDone ? '/' : '/onboarding/role');
    });
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onAnimationDone);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: _wordmark.value,
                  child: Transform.translate(
                    offset: Offset(0, 16 * (1 - _wordmark.value)),
                    child: EchangoWordmark(underlineProgress: _underline.value),
                  ),
                ),
                const SizedBox(height: 20),
                Opacity(
                  opacity: _badge.value.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.7 + 0.3 * _badge.value.clamp(0.0, 1.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        '−30%',
                        style: textTheme.labelLarge?.copyWith(
                          color: colorScheme.surface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Opacity(
                  opacity: _tagline.value,
                  child: Text(
                    l10n.onboardingSplashTagline.toUpperCase(),
                    style: textTheme.labelMedium?.copyWith(
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
