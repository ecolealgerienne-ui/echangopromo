import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'promo_discount_badge.dart';

/// Photo(s) en tête de fiche promo (4:3) + badge de réduction superposé —
/// identique entre la fiche client et la fiche admin/agent (CLAUDE.md règle
/// #21). Carousel swipeable depuis le passage au multi-photo (décision
/// produit 2026-07-12, jusqu'à 3 photos) — un point indicateur n'apparaît
/// que si plus d'une photo, pour ne rien changer visuellement au cas
/// (encore majoritaire juste après la migration) d'une seule photo.
class PromoPhotoHero extends StatefulWidget {
  const PromoPhotoHero({
    super.key,
    required this.photoUrls,
    required this.prixAvant,
    required this.prixApres,
  });

  final List<String> photoUrls;
  final double prixAvant;
  final double prixApres;

  @override
  State<PromoPhotoHero> createState() => _PromoPhotoHeroState();
}

class _PromoPhotoHeroState extends State<PromoPhotoHero> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final photoUrls = widget.photoUrls;
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
          child: photoUrls.isEmpty
              ? Container(color: colorScheme.surfaceContainerHighest)
              : PageView.builder(
                  controller: _controller,
                  itemCount: photoUrls.length,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, index) => CachedNetworkImage(
                    imageUrl: photoUrls[index],
                    fit: BoxFit.cover,
                    memCacheWidth: heroCacheWidth,
                  ),
                ),
        ),
        PositionedDirectional(
          top: 12,
          start: 12,
          child: PromoDiscountBadge(prixAvant: widget.prixAvant, prixApres: widget.prixApres),
        ),
        if (photoUrls.length > 1)
          PositionedDirectional(
            bottom: 12,
            start: 0,
            end: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < photoUrls.length; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page ? Colors.white : Colors.white54,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
