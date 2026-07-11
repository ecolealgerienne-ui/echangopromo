import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final promosAsync = ref.watch(promoListProvider);
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: l10n.professionalSpaceTooltip,
            onSelected: (route) => context.push(route),
            itemBuilder: (context) => [
              PopupMenuItem(value: '/commercant', child: Text(l10n.commercantSpaceItem)),
              PopupMenuItem(value: '/agent', child: Text(l10n.agentSpaceItem)),
            ],
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
            child: promosAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: ApiErrorText(error)),
              data: (promos) {
                if (promos.isEmpty) {
                  return Center(child: Text(l10n.noActivePromos));
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(promoListProvider.future),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(_listPadding),
                    itemCount: promos.length,
                    separatorBuilder: (context, index) => const SizedBox(height: _listSpacing),
                    itemBuilder: (context, index) {
                      final promo = promos[index];
                      return PromoCard(
                        promo: promo,
                        isFavorite: favorites.contains(promo.commercantId),
                        onTap: () => context.push('/promo/${promo.id}'),
                      );
                    },
                  ),
                );
              },
            ),
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
