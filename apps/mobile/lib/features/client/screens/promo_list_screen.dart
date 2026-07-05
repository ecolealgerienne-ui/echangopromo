import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/enums/categorie.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../providers/favorites_provider.dart';
import '../providers/promo_providers.dart';
import '../widgets/promo_card.dart';

class PromoListScreen extends ConsumerWidget {
  const PromoListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final promosAsync = ref.watch(promoListProvider);
    final favorites = ref.watch(favoritesProvider);
    final selectedCategorie = ref.watch(categoryFilterProvider);

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
          _CategoryFilterBar(selected: selectedCategorie),
          Expanded(
            child: promosAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(l10n.commonError(error.toString()))),
              data: (promos) {
                if (promos.isEmpty) {
                  return Center(child: Text(l10n.noActivePromos));
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(promoListProvider.future),
                  // MasonryGridView (pas GridView) : chaque carte garde sa
                  // hauteur naturelle — un `childAspectRatio` fixe imposait
                  // la même hauteur à toutes les cases et laissait un
                  // espace vide sous les cartes plus courtes (photo + texte
                  // dont la hauteur varie selon la description et la
                  // langue).
                  child: MasonryGridView.count(
                    padding: const EdgeInsets.all(12),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    itemCount: promos.length,
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
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(l10n.allCategoriesChip),
              selected: selected == null,
              onSelected: (_) => ref.read(categoryFilterProvider.notifier).state = null,
            ),
          ),
          for (final categorie in Categorie.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
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
