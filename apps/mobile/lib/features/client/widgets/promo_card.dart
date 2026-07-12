import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../domain/models/promo.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/widgets/promo_discount_badge.dart';
import '../../shared/widgets/promo_price_row.dart';

/// Taille de la photo dans la ligne — assez grande pour continuer à jouer
/// son rôle de signal de confiance (preuve qu'il s'agit d'un vrai commerce),
/// contrairement à une simple miniature ; assez petite pour laisser au texte
/// (notamment l'arabe, plus large qu'un français tronqué) toute la largeur
/// de l'écran. Proposition 2026-07-11 : liste 1 colonne plutôt que grille 2
/// colonnes, sur le modèle Deliveroo/Uber Eats plutôt que la miniature d'un
/// catalogue supermarché.
const _photoSize = 96.0;

/// Ligne "promo" du fil client — remplace l'ancienne carte de grille
/// 2 colonnes : une seule colonne laisse la place au nom du commerçant, au
/// badge "expire bientôt" et à un texte RTL sans troncature agressive.
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
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    // Décode directement à la taille physique affichée (96dp) plutôt que la
    // pleine résolution de l'image source (jusqu'à 1200px) — sans ça,
    // chaque vignette de la liste garde en mémoire ~150x plus de pixels
    // que ce qui est réellement montré.
    final photoCachePx = (_photoSize * MediaQuery.of(context).devicePixelRatio).round();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: SizedBox(
                      width: _photoSize,
                      height: _photoSize,
                      child: (promo.thumbnailUrl ?? promo.photoUrl) != null
                          ? CachedNetworkImage(
                              imageUrl: (promo.thumbnailUrl ?? promo.photoUrl)!,
                              fit: BoxFit.cover,
                              memCacheWidth: photoCachePx,
                              memCacheHeight: photoCachePx,
                            )
                          : Container(color: colorScheme.surfaceContainerHighest),
                    ),
                  ),
                  if (isFavorite)
                    PositionedDirectional(
                      top: 4,
                      start: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.favorite, size: 14, color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      promo.description,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      promo.commercantNom ?? '',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: PromoPriceRow(
                            prixAvant: promo.prixAvant,
                            prixApres: promo.prixApres,
                            beforeFontSize: 12,
                            afterFontSize: 15,
                          ),
                        ),
                        PromoDiscountBadge(
                          prixAvant: promo.prixAvant,
                          prixApres: promo.prixApres,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          textStyle: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    if (promo.isExpiringSoon) ...[
                      const SizedBox(height: 6),
                      Text(
                        l10n.expiringSoonBadgeLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).extension<AppSemanticColors>()!.warning,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
