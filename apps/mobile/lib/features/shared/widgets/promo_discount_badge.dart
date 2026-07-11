import 'package:flutter/material.dart';
import '../../../app/theme.dart';

/// Badge "-X%" superposé à la photo d'une promo — dupliqué à l'identique
/// entre la carte client, la fiche client et la fiche admin/agent (CLAUDE.md
/// règle #21 : extrait dès la 2e duplication, ici la 3e).
class PromoDiscountBadge extends StatelessWidget {
  const PromoDiscountBadge({
    super.key,
    required this.prixAvant,
    required this.prixApres,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.textStyle,
  });

  final double prixAvant;
  final double prixApres;
  final EdgeInsets padding;

  /// `labelLarge` par défaut (taille fiche détail) — la carte, plus petite,
  /// passe `labelSmall`.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final discountPercent = ((prixAvant - prixApres) / prixAvant * 100).round();

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        '-$discountPercent%',
        style: (textStyle ?? Theme.of(context).textTheme.labelLarge)
            ?.copyWith(color: colorScheme.onPrimary, fontWeight: FontWeight.w700),
      ),
    );
  }
}
