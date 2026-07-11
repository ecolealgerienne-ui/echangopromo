import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../domain/models/promo.dart';
import '../../shared/widgets/promo_discount_badge.dart';
import '../../shared/widgets/promo_price_row.dart';

/// Padding autour du bloc texte (description/prix/nom) — partagé avec
/// `promo_list_screen.dart` pour calculer un `childAspectRatio` de grille
/// qui correspond exactement à la hauteur réelle de la carte (photo +
/// bloc texte), sans espace vide résiduel.
const promoCardPadding = 12.0;

/// Hauteur réservée au bloc texte, indépendante du contenu réel : la
/// description est censée tenir sur 2 lignes, le prix sur 1, le nom du
/// commerçant sur 1 (specs). Fixer cette hauteur (au lieu de laisser
/// chaque `Text` prendre sa hauteur naturelle, qui varie si la
/// description tient sur 1 seule ligne) rend les cartes homogènes dans
/// une grille à ratio fixe. Marge incluse au-delà de l'estimation
/// theme par défaut (~83) pour absorber une échelle de police
/// légèrement plus grande sans faire déborder la carte.
const promoCardTextBlockHeight = 96.0;

class PromoCard extends StatelessWidget {
  const PromoCard({
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // `Expanded` plutôt qu'`AspectRatio` : la hauteur totale de la
            // carte est déjà imposée (tight) par la grille — un `AspectRatio`
            // fixe redemande sa propre hauteur en plus de celle du bloc
            // texte ci-dessous, et le moindre écart entre le ratio calculé
            // côté grille et la hauteur réellement prise par le texte
            // (métriques de police, échelle d'accessibilité) fait déborder
            // la `Column`. Avec `Expanded`, la photo prend toujours
            // exactement l'espace restant, jamais plus — proche de 16:9 en
            // pratique (le ratio de grille vise ça) mais sans jamais pouvoir
            // provoquer d'overflow.
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (promo.photoUrl != null)
                    CachedNetworkImage(imageUrl: promo.photoUrl!, fit: BoxFit.cover)
                  else
                    Container(color: colorScheme.surfaceContainerHighest),
                  PositionedDirectional(
                    top: 8,
                    start: 8,
                    child: PromoDiscountBadge(
                      prixAvant: promo.prixAvant,
                      prixApres: promo.prixApres,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      textStyle: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  if (isFavorite)
                    const PositionedDirectional(
                      top: 8,
                      end: 8,
                      child: Icon(Icons.favorite, color: Colors.redAccent),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(promoCardPadding),
              // Hauteur fixe : sans ça, une description tenant sur 1 seule
              // ligne (ou l'absence de nom de commerçant, ci-dessous
              // toujours rendu même vide) rendrait cette carte plus courte
              // que ses voisines dans la grille.
              child: SizedBox(
                height: promoCardTextBlockHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      promo.description,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    PromoPriceRow(
                      prixAvant: promo.prixAvant,
                      prixApres: promo.prixApres,
                      beforeFontSize: 13,
                      afterFontSize: 14,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      // Toujours rendu (même vide) pour réserver sa ligne —
                      // sinon la carte d'un commerçant sans nom connu serait
                      // plus courte que les autres.
                      promo.commercantNom ?? '',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
