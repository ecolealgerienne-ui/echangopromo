import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../onboarding_navigation.dart';

/// Seconde (et dernière) proposition d'activer la localisation, après un
/// « Plus tard » sur l'écran précédent. Montre ce que le refus fait perdre —
/// un aperçu de promos situées autour de l'utilisateur — plutôt que de
/// répéter le même argumentaire.
///
/// L'aperçu est une illustration, pas la vraie carte : l'écran carte
/// (flutter_map + OpenStreetMap) reste à construire.
class LocationSecondChanceScreen extends ConsumerWidget {
  const LocationSecondChanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _MapTeaserPainter(
                    street: colorScheme.outlineVariant,
                    block: colorScheme.surfaceContainerHighest,
                    background: colorScheme.surface,
                  ),
                ),
                const _Pin(alignment: Alignment(-0.45, -0.25), label: '−30%'),
                const _Pin(
                    alignment: Alignment(0.5, -0.15),
                    label: '−20%',
                    secondary: true),
                const _Pin(alignment: Alignment(-0.3, 0.3), label: '−45%'),
                // Fondu vers le bas : le texte reste lisible sans assombrir
                // toute l'illustration.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.35, 0.75, 1.0],
                      colors: [
                        colorScheme.surface.withValues(alpha: 0.0),
                        colorScheme.surface.withValues(alpha: 0.92),
                        colorScheme.surface,
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.onboardingSecondChanceTitle,
                            style: textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          l10n.onboardingSecondChanceSubtitle,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: () => requestLocationAndFinish(context, ref),
                    child: Text(l10n.onboardingLocationEnable),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => skipLocationAndFinish(context, ref),
                    child: Text(l10n.onboardingSecondChanceContinue),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.onboardingSecondChanceFine,
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin(
      {required this.alignment, required this.label, this.secondary = false});

  final Alignment alignment;
  final String label;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = secondary ? colorScheme.secondary : colorScheme.primary;
    final foreground =
        secondary ? colorScheme.onSurface : colorScheme.onPrimary;

    return Align(
      alignment: alignment,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

/// Trame de rues stylisée — volontairement schématique : c'est une
/// illustration du bénéfice, pas un rendu cartographique.
class _MapTeaserPainter extends CustomPainter {
  const _MapTeaserPainter({
    required this.street,
    required this.block,
    required this.background,
  });

  final Color street;
  final Color block;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final blockPaint = Paint()..color = block;
    void drawBlock(double left, double top, double width, double height) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * left, size.height * top,
              size.width * width, size.height * height),
          const Radius.circular(6),
        ),
        blockPaint,
      );
    }

    drawBlock(0.10, 0.16, 0.36, 0.30);
    drawBlock(0.58, 0.16, 0.30, 0.30);
    drawBlock(0.10, 0.56, 0.36, 0.26);
    drawBlock(0.58, 0.56, 0.30, 0.26);

    final streetPaint = Paint()
      ..color = street
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.035
      ..strokeCap = StrokeCap.round;

    for (final y in const [0.10, 0.51, 0.88]) {
      canvas.drawLine(
        Offset(-10, size.height * y),
        Offset(size.width + 10, size.height * y),
        streetPaint,
      );
    }
    for (final x in const [0.05, 0.52, 0.93]) {
      canvas.drawLine(
        Offset(size.width * x, -10),
        Offset(size.width * x, size.height + 10),
        streetPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_MapTeaserPainter oldDelegate) =>
      oldDelegate.street != street ||
      oldDelegate.block != block ||
      oldDelegate.background != background;
}
