import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../domain/models/map_shop.dart';
import '../../../domain/models/promo.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/utils/distance_format.dart';
import '../../shared/utils/maps_launcher.dart';
import '../../shared/utils/phone_launcher.dart';
import '../../shared/widgets/promo_discount_badge.dart';
import '../../shared/widgets/promo_price_row.dart';

/// Fiche du commerçant, remontée depuis le bas de la carte au clic sur un
/// point. Les promos défilent horizontalement quand il y en a plusieurs.
class MapShopSheet extends StatefulWidget {
  const MapShopSheet({
    super.key,
    required this.shop,
    required this.onPromoTap,
    this.distanceMeters,
  });

  final MapShop shop;
  final void Function(Promo promo) onPromoTap;

  /// `null` si la localisation n'est pas accordée — la ligne se réduit alors
  /// à la catégorie, sans trou ni séparateur orphelin.
  final double? distanceMeters;

  @override
  State<MapShopSheet> createState() => _MapShopSheetState();
}

class _MapShopSheetState extends State<MapShopSheet> {
  late final PageController _controller = PageController();
  int _index = 0;

  @override
  void didUpdateWidget(covariant MapShopSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Un autre commerce sélectionné doit repartir de sa première promo,
    // pas hériter de la position du précédent.
    if (oldWidget.shop.id != widget.shop.id && _controller.hasClients) {
      _controller.jumpToPage(0);
      setState(() => _index = 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final shop = widget.shop;

    return Material(
      color: colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Row(
                children: [
                  _ShopAvatar(shop: shop),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          shop.nom,
                          style: textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          [
                            categorieLabel(context, shop.categorie),
                            if (widget.distanceMeters != null)
                              formatDistance(l10n, widget.distanceMeters!),
                          ].join(' · '),
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => openMapsAt(shop.latitude, shop.longitude),
                    icon: const Icon(Icons.navigation_outlined),
                    tooltip: l10n.mapDirections,
                  ),
                  const SizedBox(width: 6),
                  IconButton.outlined(
                    onPressed: shop.telephone == null
                        ? null
                        : () => callPhone(shop.telephone!),
                    icon: const Icon(Icons.phone_outlined),
                    tooltip: l10n.mapCall,
                  ),
                ],
              ),
            ),
            if (shop.promos.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Text(
                  l10n.mapNoActivePromo,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 260,
                child: PageView.builder(
                  controller: _controller,
                  itemCount: shop.promos.length,
                  onPageChanged: (index) => setState(() => _index = index),
                  itemBuilder: (context, index) => _PromoSlide(
                    promo: shop.promos[index],
                    onTap: () => widget.onPromoTap(shop.promos[index]),
                  ),
                ),
              ),
              if (shop.promos.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < shop.promos.length; i++)
                        AnimatedContainer(
                          duration: kAppTransitionDuration,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _index ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? colorScheme.primary
                                : colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShopAvatar extends StatelessWidget {
  const _ShopAvatar({required this.shop});

  final MapShop shop;

  @override
  Widget build(BuildContext context) {
    if (shop.photoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: CachedNetworkImage(
          imageUrl: shop.photoUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) => _InitialsAvatar(nom: shop.nom),
        ),
      );
    }
    return _InitialsAvatar(nom: shop.nom);
  }
}

/// Repli quand le commerçant n'a pas de photo : ses initiales, plutôt qu'une
/// icône générique identique pour tous les commerces de la carte.
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.nom});

  final String nom;

  String get _initials {
    final words = nom.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return (words[0].characters.first + words[1].characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.md),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.secondary, colorScheme.primary],
        ),
      ),
      child: Text(
        _initials,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colorScheme.onPrimary,
            ),
      ),
    );
  }
}

class _PromoSlide extends StatelessWidget {
  const _PromoSlide({required this.promo, required this.onTap});

  final Promo promo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final photo = promo.thumbnailUrl ?? (promo.photoUrls.isNotEmpty ? promo.photoUrls.first : null);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: Stack(
                children: [
                  SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: photo == null
                        ? Container(color: colorScheme.surfaceContainerHighest)
                        : CachedNetworkImage(
                            imageUrl: photo,
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                Container(color: colorScheme.surfaceContainerHighest),
                            errorWidget: (context, url, error) =>
                                Container(color: colorScheme.surfaceContainerHighest),
                          ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: PromoDiscountBadge(
                      prixAvant: promo.prixAvant,
                      prixApres: promo.prixApres,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              promo.description,
              style: textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            PromoPriceRow(prixAvant: promo.prixAvant, prixApres: promo.prixApres),
          ],
        ),
      ),
    );
  }
}
