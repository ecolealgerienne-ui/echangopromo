import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../domain/models/promo.dart';
import '../../shared/widgets/promo_discount_badge.dart';
import '../../shared/widgets/promo_price_row.dart';

/// Proportion de la carte occupée par la photo, en grille 2 colonnes. Le
/// reste revient au texte : description sur deux lignes, commerce, prix.
const _photoFlex = 62;
const _textFlex = 38;

/// Carte verticale du fil client en 2 colonnes (`PromoDensity.grid`).
///
/// Distincte de `PromoCard`, qui est une **ligne** horizontale : y ajouter un
/// mode vertical aurait demandé deux arbres de widgets complets dans un même
/// `build`, sans rien partager d'autre que les données. Le point commun réel
/// (prix, badge de remise) est déjà factorisé dans `PromoPriceRow` et
/// `PromoDiscountBadge`, réutilisés ici.
class PromoGridCard extends StatelessWidget {
  const PromoGridCard({
    super.key,
    required this.promo,
    required this.isFavorite,
    required this.onTap,
    this.onToggleFavorite,
  });

  final Promo promo;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final photoUrl = promo.thumbnailUrl ?? promo.photoUrl;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: _photoFlex,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (photoUrl != null)
                    CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover)
                  else
                    Container(color: colorScheme.surfaceContainerHighest),
                  PositionedDirectional(
                    top: 6,
                    start: 6,
                    child: PromoDiscountBadge(
                      prixAvant: promo.prixAvant,
                      prixApres: promo.prixApres,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      textStyle: textTheme.labelSmall,
                    ),
                  ),
                  if (isFavorite || onToggleFavorite != null)
                    PositionedDirectional(
                      top: 2,
                      end: 2,
                      child: IconButton(
                        // Fond translucide : sur une photo claire, un cœur
                        // blanc devient invisible.
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.surface.withValues(alpha: 0.7),
                          minimumSize: const Size(28, 28),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        iconSize: 16,
                        onPressed: onToggleFavorite,
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: isFavorite ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: _textFlex,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      promo.description,
                      style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    PromoPriceRow(
                      prixAvant: promo.prixAvant,
                      prixApres: promo.prixApres,
                      beforeFontSize: 10,
                      afterFontSize: 13,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tuile de la mosaïque 6 colonnes (`PromoDensity.mosaic`) : la photo, et
/// rien d'autre que la remise. À cette largeur le moindre mot serait illisible
/// — la tuile sert à repérer une promo à l'œil, puis à l'ouvrir.
class PromoPhotoTile extends StatelessWidget {
  const PromoPhotoTile({
    super.key,
    required this.promo,
    required this.isFavorite,
    required this.onTap,
  });

  final Promo promo;
  final bool isFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final photoUrl = promo.thumbnailUrl ?? promo.photoUrl;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photoUrl != null)
              CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover)
            else
              Container(color: colorScheme.surfaceContainerHighest),
            // Le badge porte déjà sa propre pastille pleine : il reste
            // lisible sur une photo claire sans voile supplémentaire.
            PositionedDirectional(
              bottom: 2,
              start: 2,
              child: PromoDiscountBadge(
                prixAvant: promo.prixAvant,
                prixApres: promo.prixApres,
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                textStyle: const TextStyle(fontSize: 9, height: 1.1),
              ),
            ),
            if (isFavorite)
              const PositionedDirectional(
                top: 2,
                end: 2,
                child: Icon(Icons.favorite, size: 10, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}
