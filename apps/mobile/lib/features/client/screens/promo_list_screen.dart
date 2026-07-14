import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../providers/favorites_provider.dart';
import '../providers/promo_providers.dart';
import '../widgets/promo_card.dart';
import '../widgets/promo_filter_sheet.dart';

const _listPadding = 12.0;
const _listSpacing = 10.0;

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
    // Un filtre "non défaut" allume le point sur le bouton — repère rapide
    // façon Airbnb/Deliveroo, sans avoir à ouvrir la feuille pour savoir si
    // un filtre est actif.
    final filtersActive = ref.watch(favoritesOnlyFilterProvider) ||
        ref.watch(promoSortProvider) != PromoSort.expireBientot;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          const LanguageSwitcherButton(),
          IconButton(
            icon: const Icon(Icons.location_on_outlined),
            tooltip: l10n.changeCommuneTooltip,
            onPressed: () => context.push('/select-commune'),
          ),
          // Espace agent terrain retiré de ce menu (2026-07-14, même
          // décision produit que l'admin) : accès direct par URL `/agent`
          // uniquement, pas de découverte possible depuis l'app grand
          // public.
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: l10n.commercantSpaceItem,
            onPressed: () => context.push('/commercant'),
          ),
        ],
      ),
      body: Column(
        children: [
          Row(
            children: [
              Expanded(child: _CategoryFilterBar(selected: selectedCategorie)),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: IconButton(
                  icon: Badge(
                    isLabelVisible: filtersActive,
                    smallSize: 8,
                    child: const Icon(Icons.tune),
                  ),
                  tooltip: l10n.filtersSortTooltip,
                  onPressed: () => showPromoFilterSheet(context),
                ),
              ),
            ],
          ),
          Expanded(
            child: switch (promoListState.status) {
              PromoListStatus.loading => const Center(child: CircularProgressIndicator()),
              PromoListStatus.error => Center(child: ApiErrorText(promoListState.error!)),
              PromoListStatus.loaded => RefreshIndicator(
                  onRefresh: () => ref.read(promoListProvider.notifier).refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(_listPadding),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: promos.isEmpty
                        ? 1
                        : promos.length + (promoListState.hasMore ? 1 : 0),
                    separatorBuilder: (context, index) => const SizedBox(height: _listSpacing),
                    itemBuilder: (context, index) {
                      if (promos.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: Center(child: Text(l10n.noActivePromos)),
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
                      );
                    },
                  ),
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _CategoryFilterBar extends ConsumerWidget {
  const _CategoryFilterBar({required this.selected});

  final Categorie? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: ChoiceChip(
              label: Text(l10n.allCategoriesChip),
              selected: selected == null,
              onSelected: (_) => ref.read(categoryFilterProvider.notifier).state = null,
            ),
          ),
          for (final categorie in Categorie.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(categorieLabel(context, categorie)),
                selected: selected == categorie,
                onSelected: (_) => ref.read(categoryFilterProvider.notifier).state = categorie,
              ),
            ),
        ],
      ),
    );
  }
}
