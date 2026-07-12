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
    // Affichée en pleine largeur d'écran — approximation raisonnable en
    // l'absence de layout déjà connu à ce stade (`AspectRatio` ne donne pas
    // de contrainte de largeur avant construction). Sans effet si ça dépasse
    // la résolution source (~1200px max, voir StorageApi._compress) :
    // `memCacheWidth` ne fait jamais remonter au-dessus de l'original.
    final heroCacheWidth = (MediaQuery.sizeOf(context).width * MediaQuery.of(context).devicePixelRatio).round();

    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: photoUrl != null
              ? CachedNetworkImage(
                  imageUrl: photoUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth: heroCacheWidth,
                )
              : Container(color: colorScheme.surfaceContainerHighest),
        ),
        PositionedDirectional(
          top: 12,
          start: 12,
          child: PromoDiscountBadge(prixAvant: prixAvant, prixApres: prixApres),
        ),
      ],
    );
  }
}
