import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Prix barré + prix après réduction — dupliqué à l'identique entre la
/// carte client, la fiche client et la fiche admin/agent (CLAUDE.md règle
/// #21 : extrait dès la 2e duplication, ici la 3e).
class PromoPriceRow extends StatelessWidget {
  const PromoPriceRow({
    super.key,
    required this.prixAvant,
    required this.prixApres,
    this.beforeFontSize = 16,
    this.afterFontSize = 20,
  });

  final double prixAvant;
  final double prixApres;
  final double beforeFontSize;
  final double afterFontSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currency = NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          currency.format(prixAvant),
          style: TextStyle(
            decoration: TextDecoration.lineThrough,
            color: colorScheme.onSurfaceVariant,
            fontSize: beforeFontSize,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          currency.format(prixApres),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: afterFontSize,
            color: colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
