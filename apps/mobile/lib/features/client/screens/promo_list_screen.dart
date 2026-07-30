import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../../domain/models/promo.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/utils/categorie_asset.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/promo_discount_badge.dart';
import '../../shared/widgets/theme_mode_button.dart';
import '../providers/commune_providers.dart';
import '../providers/favorites_provider.dart';
import '../providers/promo_providers.dart';
import '../widgets/promo_card.dart';
import '../widgets/promo_filter_sheet.dart';

const _listPadding = 12.0;
const _listSpacing = 10.0;

/// Accueil client. Deux dispositions, une seule structure : en mode
/// découverte le bandeau "Top promos" occupe le haut ; dès qu'une catégorie
/// est choisie il se replie et la liste prend toute la place. La barre de
/// recherche, elle, ne bouge jamais — c'est le repère fixe qui évite de
/// donner l'impression d'avoir changé d'écran.
class PromoListScreen extends ConsumerWidget {
  const PromoListScreen({super.key});

  Future<void> _loadMore(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref.read(promoListProvider.notifier).loadMore();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(extractApiErrorMessage(
              error,
              fallback: l10n.operationFailed,
              locale: Localizations.localeOf(context),
            )),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final promoListState = ref.watch(promoListProvider);
    final promos = ref.watch(visiblePromosProvider);
    final favorites = ref.watch(favoritesProvider);
    final selectedCategorie = ref.watch(categoryFilterProvider);
    final favoritesOnly = ref.watch(favoritesOnlyFilterProvider);
    final search = ref.watch(searchQueryProvider);
    final expanded = ref.watch(listExpandedProvider);

    // Liste en plein écran : soit le client a filtré (catégorie, recherche,
    // favoris) et cherche donc quelque chose de précis, soit il a simplement
    // tiré la liste vers le haut. Même disposition dans les deux cas — la
    // vitrine du haut n'a plus lieu d'être.
    final focused = expanded || selectedCategorie != null || search.isNotEmpty || favoritesOnly;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _TopBar(),
            // AnimatedSize plutôt qu'une hauteur figée : le bandeau se
            // replie sans que la liste ne saute d'un coup.
            AnimatedSize(
              duration: kAppTransitionDuration,
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: focused
                  ? const SizedBox(width: double.infinity)
                  : const _TopPromosSection(),
            ),
            _CategoryCircles(selected: selectedCategorie, compact: focused),
            _ListHeader(
              focused: focused,
              categorie: selectedCategorie,
              favoritesOnly: favoritesOnly,
              count: promos.length,
            ),
            Expanded(
              child: switch (promoListState.status) {
                PromoListStatus.loading => const Center(child: CircularProgressIndicator()),
                PromoListStatus.error => Center(child: ApiErrorText(promoListState.error!)),
                PromoListStatus.loaded => RefreshIndicator(
                    onRefresh: () => ref.read(promoListProvider.notifier).refresh(),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                          _listPadding, 0, _listPadding, _listPadding),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount:
                          promos.isEmpty ? 1 : promos.length + (promoListState.hasMore ? 1 : 0),
                      separatorBuilder: (context, index) => const SizedBox(height: _listSpacing),
                      itemBuilder: (context, index) {
                        if (promos.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 80),
                            child: Center(
                              child: Text(
                                search.isEmpty
                                    ? l10n.noActivePromos
                                    : l10n.noSearchResults(search),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        if (index == promos.length) {
                          return Center(
                            child: promoListState.loadingMore
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : OutlinedButton(
                                    onPressed: () => _loadMore(context, ref),
                                    child: Text(l10n.loadMoreButtonLabel),
                                  ),
                          );
                        }
                        final promo = promos[index];
                        return PromoCard(
                          promo: promo,
                          isFavorite: favorites.contains(promo.id),
                          onTap: () => context.push('/promo/${promo.id}'),
                          onToggleFavorite: () =>
                              ref.read(favoritesProvider.notifier).toggle(promo.id),
                        );
                      },
                    ),
                  ),
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: const _ClientTabBar(),
    );
  }
}

/// Commune, langue, recherche et filtres — la seule zone qui reste
/// identique dans les deux dispositions.
class _TopBar extends ConsumerStatefulWidget {
  const _TopBar();

  @override
  ConsumerState<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<_TopBar> {
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(searchQueryProvider));
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Chaque frappe relance une requête serveur : sans ce délai, taper
  /// "boulangerie" en déclencherait onze.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    ref.read(searchQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final filtersActive = ref.watch(favoritesOnlyFilterProvider) ||
        ref.watch(promoSortProvider) != PromoSort.nouveautes;
    final hasSearch = ref.watch(searchQueryProvider).isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              // Le sélecteur de commune fait office de titre : c'est
              // l'information qui conditionne tout le contenu affiché.
              Expanded(
                child: InkWell(
                  onTap: () => context.push('/select-commune'),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on, size: 18, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            ref.watch(selectedCommuneLabelProvider) ??
                                l10n.changeCommuneTooltip,
                            style: textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.expand_more, size: 18, color: colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
              const ThemeModeButton(),
              const LanguageSwitcherButton(),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  onChanged: _onChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l10n.searchPromoHint,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: hasSearch
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: l10n.searchClear,
                            onPressed: _clear,
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Badge(
                  isLabelVisible: filtersActive,
                  smallSize: 8,
                  child: const Icon(Icons.tune),
                ),
                tooltip: l10n.filtersSortTooltip,
                onPressed: () => showPromoFilterSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bandeau "Top promos" : les plus fortes réductions de la commune, calculées
/// par le backend. Silencieux en cas d'erreur — c'est une vitrine, pas un
/// contenu essentiel : une erreur ici volerait la place de la liste, qui a
/// son propre traitement d'erreur.
class _TopPromosSection extends ConsumerWidget {
  const _TopPromosSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final promos = ref.watch(topPromosProvider).valueOrNull ?? const <Promo>[];
    if (promos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(l10n.topPromosTitle, style: textTheme.titleSmall),
        ),
        SizedBox(
          height: 172,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: promos.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) => _TopPromoCard(promo: promos[index]),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _TopPromoCard extends StatelessWidget {
  const _TopPromoCard({required this.promo});

  final Promo promo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final photo =
        promo.thumbnailUrl ?? (promo.photoUrls.isNotEmpty ? promo.photoUrls.first : null);

    return SizedBox(
      width: 232,
      child: InkWell(
        onTap: () => context.push('/promo/${promo.id}'),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photo == null)
                Container(color: colorScheme.surfaceContainerHighest)
              else
                CachedNetworkImage(
                  imageUrl: photo,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: colorScheme.surfaceContainerHighest),
                  errorWidget: (context, url, error) =>
                      Container(color: colorScheme.surfaceContainerHighest),
                ),
              // Voile du bas : le texte doit rester lisible quelle que soit
              // la photo envoyée par le commerçant.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.4, 1.0],
                    colors: [
                      Colors.transparent,
                      colorScheme.scrim.withValues(alpha: 0.78),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: PromoDiscountBadge(
                  prixAvant: promo.prixAvant,
                  prixApres: promo.prixApres,
                  textStyle: textTheme.labelSmall,
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      promo.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(color: Colors.white),
                    ),
                    if (promo.commercantNom != null)
                      Text(
                        promo.commercantNom!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall
                            ?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                      ),
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

/// Catégories en ronds. En mode filtré les ronds rétrécissent et le libellé
/// disparaît : la bande passe de vitrine à barre de filtre, sans changer de
/// place ni de nature.
class _CategoryCircles extends ConsumerWidget {
  const _CategoryCircles({required this.selected, required this.compact});

  final Categorie? selected;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedContainer(
      duration: kAppTransitionDuration,
      curve: Curves.easeOut,
      height: compact ? 58 : 92,
      padding: const EdgeInsets.only(top: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: Categorie.values.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final categorie = Categorie.values[index];
          return _CategoryCircle(
            categorie: categorie,
            isSelected: selected == categorie,
            diameter: compact ? 42 : 56,
            showLabel: !compact,
            // Recliquer la catégorie active la désélectionne : c'est le
            // second moyen de revenir à l'accueil, avec le glissement.
            onTap: () => ref.read(categoryFilterProvider.notifier).state =
                selected == categorie ? null : categorie,
          );
        },
      ),
    );
  }
}

class _CategoryCircle extends StatelessWidget {
  const _CategoryCircle({
    required this.categorie,
    required this.isSelected,
    required this.diameter,
    required this.showLabel,
    required this.onTap,
  });

  final Categorie categorie;
  final bool isSelected;
  final double diameter;
  final bool showLabel;
  final VoidCallback onTap;

  static const _icons = <Categorie, IconData>{
    Categorie.alimentation: Icons.restaurant,
    Categorie.vetementsTextile: Icons.checkroom,
    Categorie.electromenager: Icons.kitchen,
    Categorie.beauteHygiene: Icons.spa,
    Categorie.maisonAmeublement: Icons.chair,
    Categorie.autre: Icons.more_horiz,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: showLabel ? 64 : 46,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: kAppTransitionDuration,
              curve: Curves.easeOut,
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.surfaceContainerHighest,
                border: Border.all(
                  color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
                  // L'anneau s'épaissit à la sélection plutôt que de remplir
                  // le rond : avec une image dedans, un fond plein la
                  // masquerait complètement.
                  width: isSelected ? 2.5 : 1.5,
                ),
              ),
              child: ClipOval(
                child: Image.asset(
                  categorieAssetPath(categorie),
                  fit: BoxFit.cover,
                  width: diameter,
                  height: diameter,
                  // Repli sur l'icône Material tant que le visuel n'a pas été
                  // déposé dans `assets/images/categories/` — l'accueil doit
                  // rester utilisable sans ces images.
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Icon(
                      _icons[categorie] ?? Icons.local_offer_outlined,
                      size: diameter * 0.42,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            if (showLabel) ...[
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  categorieLabel(context, categorie),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Titre de la liste, plus une poignée de glissement en mode filtré : tirer
/// vers le bas ramène l'accueil, comme on referme une feuille.
class _ListHeader extends ConsumerWidget {
  const _ListHeader({
    required this.focused,
    required this.categorie,
    required this.favoritesOnly,
    required this.count,
  });

  final bool focused;
  final Categorie? categorie;
  final bool favoritesOnly;
  final int count;

  /// Ramène l'accueil : la liste se replie et tous les filtres retombent.
  void _reset(WidgetRef ref) {
    ref.read(listExpandedProvider.notifier).state = false;
    ref.read(categoryFilterProvider.notifier).state = null;
    ref.read(favoritesOnlyFilterProvider.notifier).state = false;
    ref.read(searchQueryProvider.notifier).state = '';
  }

  /// Vitesse minimale, en pixels par seconde, pour qu'un glissement compte.
  /// En dessous, c'est un frôlement en tentant de faire défiler la liste, pas
  /// une intention de replier ou déployer.
  static const _dragVelocityThreshold = 120.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final title = categorie != null
        ? categorieLabel(context, categorie!)
        : (favoritesOnly ? l10n.favoritesOnlyLabel : l10n.allPromosTitle);

    return GestureDetector(
      // Glissement dans les deux sens sur cet en-tête (demande 2026-07-29) :
      // vers le haut on déploie la liste, vers le bas on ramène l'accueil.
      // Le geste est capté ici et pas sur la liste elle-même, sinon il
      // entrerait en conflit avec le défilement des promos.
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > _dragVelocityThreshold) {
          if (focused) _reset(ref);
        } else if (velocity < -_dragVelocityThreshold) {
          if (!focused) ref.read(listExpandedProvider.notifier).state = true;
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Poignée visible dans les deux états : c'est ce qui signale
            // qu'on peut tirer, y compris pour déployer. La cacher en mode
            // découverte rendait le geste vers le haut indécouvrable.
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
            ),
            Row(
              children: [
                Expanded(child: Text(title, style: textTheme.titleSmall)),
                Text(
                  l10n.promoCount(count),
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                if (focused)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4),
                    child: InkWell(
                      onTap: () => _reset(ref),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 18, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Barre d'onglets du parcours client. La carte avait besoin d'un point
/// d'entrée permanent — c'est ce qui a motivé cette barre, absente jusqu'ici.
/// « Espace pro » reste le seul accès affiché : agent et admin gardent leur
/// accès par URL directe (décisions produit 2026-07-09 et 2026-07-14).
class _ClientTabBar extends ConsumerWidget {
  const _ClientTabBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final favoritesOnly = ref.watch(favoritesOnlyFilterProvider);

    return NavigationBar(
      selectedIndex: favoritesOnly ? 2 : 0,
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            ref.read(favoritesOnlyFilterProvider.notifier).state = false;
          case 1:
            context.push('/carte');
          case 2:
            ref.read(favoritesOnlyFilterProvider.notifier).state = !favoritesOnly;
          case 3:
            context.push('/commercant');
        }
      },
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: l10n.tabHome,
        ),
        NavigationDestination(icon: const Icon(Icons.map_outlined), label: l10n.tabMap),
        NavigationDestination(
          icon: const Icon(Icons.favorite_border),
          selectedIcon: const Icon(Icons.favorite),
          label: l10n.tabFavorites,
        ),
        NavigationDestination(
          icon: const Icon(Icons.storefront_outlined),
          label: l10n.commercantSpaceItem,
        ),
      ],
    );
  }
}
