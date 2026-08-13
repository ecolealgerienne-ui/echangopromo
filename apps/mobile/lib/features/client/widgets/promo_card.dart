import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../domain/models/promo.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/utils/distance_format.dart';
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
    this.onToggleFavorite,
    this.distanceMeters,
  });

  final Promo promo;
  final bool isFavorite;
  final VoidCallback onTap;

  /// Facultatif : sans lui, le cœur reste un simple indicateur (comportement
  /// d'origine, conservé pour les écrans qui affichent une promo sans
  /// permettre de la mettre en favori). Avec, il devient un bouton — mettre
  /// en favori depuis le fil évitait d'ouvrir la fiche uniquement pour ça.
  final VoidCallback? onToggleFavorite;

  /// Distance à vol d'oiseau, en mètres, ou `null` quand elle n'est pas
  /// calculable — position du client inconnue, ou commerce sans coordonnées.
  ///
  /// ⚠️ **Calculée par l'appelant, pas ici.** Cette ligne est reconstruite à
  /// chaque défilement ; y appeler `ref.watch(userPositionProvider)` ferait
  /// relire la position par carte visible. L'écran la lit une fois et la passe.
  ///
  /// ⚠️ `null` n'est pas « 0 m » et ne s'affiche pas comme tel : la ligne
  /// disparaît. Un `0` afficherait « à 0 m » sur une position inconnue —
  /// exactement le défaut que la règle 29 décrit.
  final double? distanceMeters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    // Décode directement à la taille physique affichée (96dp) plutôt que la
    // pleine résolution de l'image source (jusqu'à 1200px) — sans ça,
    // chaque vignette de la liste garde en mémoire ~150x plus de pixels
    // que ce qui est réellement montré.
    final photoCachePx =
        (_photoSize * MediaQuery.of(context).devicePixelRatio).round();

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
                          : Container(
                              color: colorScheme.surfaceContainerHighest),
                    ),
                  ),
                  // Affiché en permanence quand il est cliquable : un cœur
                  // qui n'apparaît qu'une fois activé ne se laisse pas
                  // découvrir.
                  if (isFavorite || onToggleFavorite != null)
                    PositionedDirectional(
                      top: 2,
                      start: 2,
                      child: Material(
                        color: colorScheme.surface.withValues(alpha: 0.88),
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: onToggleFavorite,
                          customBorder: const CircleBorder(),
                          child: Padding(
                            // Zone tactile plus large que l'icône : 14dp seuls
                            // seraient sous le minimum atteignable au pouce.
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 16,
                              color: isFavorite
                                  ? Theme.of(context)
                                      .extension<AppSemanticColors>()!
                                      .favorite
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
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
                      // ⚠️ Le nom et la distance sur la MÊME ligne : le serveur
                      // sert `commercantLatitude`/`Longitude` depuis le
                      // 2026-08-12 « pour que l'app puisse afficher la distance
                      // dans la liste », et personne ne l'affichait — le modèle
                      // Dart jetait les deux champs (règle 31). Les séparer sur
                      // deux lignes rallongerait chaque carte du fil pour une
                      // valeur de quelques caractères.
                      [
                        if ((promo.commercantNom ?? '').isNotEmpty)
                          promo.commercantNom!,
                        if (distanceMeters != null)
                          formatDistance(l10n, distanceMeters!),
                      ].join(' · '),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          textStyle: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    if (promo.isExpiringSoon) ...[
                      const SizedBox(height: 6),
                      Text(
                        l10n.expiringSoonBadgeLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context)
                                  .extension<AppSemanticColors>()!
                                  .warning,
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
