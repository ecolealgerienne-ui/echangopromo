import 'package:flutter/material.dart';

/// « echango promo » : `echango` dans la couleur du texte, `promo` en
/// terracotta souligné d'un trait safran ondulé — la même signature que
/// l'affiche posée en vitrine chez le commerçant.
///
/// Extrait du splash à sa deuxième utilisation (écran de connexion
/// commerçant), conformément à la règle d'audit #21.
class EchangoWordmark extends StatelessWidget {
  const EchangoWordmark({
    super.key,
    this.underlineProgress = 1,
    this.fontSize,
  });

  /// Fraction du soulignement déjà tracée, de 0 à 1. Le splash l'anime ; tout
  /// autre écran laisse la valeur par défaut, soit le trait complet.
  final double underlineProgress;

  /// `displaySmall` du thème par défaut. Les écrans où la marque n'est pas le
  /// sujet principal passent une taille plus petite.
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w900,
          height: 1.0,
          fontSize: fontSize,
        );
    // Le soulignement suit la taille du texte plutôt qu'une hauteur fixe,
    // sinon il devient disproportionné dès que `fontSize` change.
    final underlineHeight = (style?.fontSize ?? 30) * 0.36;

    // `Row` suit la Directionality ambiante : en arabe elle s'inversait et
    // affichait « promo echango ». La marque est un nom propre, son ordre ne
    // dépend pas de la langue de l'interface — on force donc le sens LTR ici
    // plutôt qu'à chaque point d'appel (trouvé en test TestFlight,
    // 2026-08-04).
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
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
                bottom: -underlineHeight * 0.62,
                height: underlineHeight,
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
      ),
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
      drawn.addPath(
          metric.extractPath(0, metric.length * progress), Offset.zero);
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
