import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme.dart';
import '../../../l10n/app_localizations.dart';

/// Écran d'ouverture animé. Le soulignement safran et le badge de réduction
/// reprennent volontairement le langage visuel de l'affiche commerçant
/// (support papier posé en vitrine) : l'app et l'affiche partagent la même
/// signature, c'est ce qui fait reconnaître l'une depuis l'autre.
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

    Animation<double> phase(double begin, double end, {Curve curve = Curves.easeOutCubic}) {
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
      if (mounted) context.go('/onboarding/role');
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
                    child: _Wordmark(underlineProgress: _underline.value),
                  ),
                ),
                const SizedBox(height: 20),
                Opacity(
                  opacity: _badge.value.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.7 + 0.3 * _badge.value.clamp(0.0, 1.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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

/// « echango promo » — `echango` reste dans la couleur du texte, `promo`
/// prend le terracotta et porte le soulignement animé.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.underlineProgress});

  final double underlineProgress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w900,
          height: 1.0,
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('echango', style: style),
        const SizedBox(width: 6),
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Text('promo', style: style?.copyWith(color: colorScheme.primary)),
            Positioned(
              left: -2,
              right: -2,
              bottom: -7,
              height: 11,
              child: CustomPaint(
                painter: _SquigglePainter(
                  progress: underlineProgress,
                  color: colorScheme.secondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Trait ondulé qui se dessine de gauche à droite. `PathMetric.extractPath`
/// donne la portion déjà tracée — c'est ce qui produit l'effet « au feutre »
/// plutôt qu'une simple apparition en fondu.
class _SquigglePainter extends CustomPainter {
  const _SquigglePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || size.width <= 0) return;

    final path = Path()..moveTo(0, size.height * 0.55);
    const waves = 4;
    final step = size.width / waves;
    for (var i = 0; i < waves; i++) {
      path.quadraticBezierTo(
        step * i + step * 0.5,
        i.isEven ? size.height * 0.02 : size.height * 0.98,
        step * (i + 1),
        size.height * 0.55,
      );
    }

    final drawn = Path();
    for (final metric in path.computeMetrics()) {
      drawn.addPath(metric.extractPath(0, metric.length * progress), Offset.zero);
    }

    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * 0.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SquigglePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
