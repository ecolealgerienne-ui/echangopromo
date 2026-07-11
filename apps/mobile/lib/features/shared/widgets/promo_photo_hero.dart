import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'promo_discount_badge.dart';

/// Photo en tête de fiche promo (4:3) + badge de réduction superposé —
/// identique entre la fiche client et la fiche admin/agent (CLAUDE.md règle
/// #21).
class PromoPhotoHero extends StatelessWidget {
  const PromoPhotoHero({
    super.key,
    required this.photoUrl,
    required this.prixAvant,
    required this.prixApres,
  });

  final String? photoUrl;
  final double prixAvant;
  final double prixApres;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: photoUrl != null
              ? CachedNetworkImage(imageUrl: photoUrl!, fit: BoxFit.cover)
              : Container(color: colorScheme.surfaceContainerHighest),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: PromoDiscountBadge(prixAvant: prixAvant, prixApres: prixApres),
        ),
      ],
    );
  }
}
