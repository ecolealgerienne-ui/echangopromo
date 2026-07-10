import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/enums/categorie.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../providers/favorites_provider.dart';
import '../providers/promo_providers.dart';
import '../widgets/promo_card.dart';

const _gridCrossAxisCount = 2;
const _gridSpacing = 12.0;
const _gridPadding = 12.0;

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
                return LayoutBuilder(
                  builder: (context, constraints) {
                    // `childAspectRatio` calculé pour correspondre
                    // exactement à la hauteur réelle de la carte (photo
                    // 16:9 à la largeur de la case + bloc texte de hauteur
                    // fixe, voir promo_card.dart) — pas de valeur figée qui
                    // laisserait un espace vide ou déborderait selon la
                    // largeur d'écran.
                    final availableWidth = constraints.maxWidth -
                        _gridPadding * 2 -
                        _gridSpacing * (_gridCrossAxisCount - 1);
                    final cardWidth = availableWidth / _gridCrossAxisCount;
                    final imageHeight = cardWidth * 9 / 16;
                    final cardHeight =
                        imageHeight + promoCardTextBlockHeight + promoCardPadding * 2;
                    final aspectRatio = cardWidth / cardHeight;

                    return RefreshIndicator(
                      onRefresh: () => ref.refresh(promoListProvider.future),
                      child: GridView.builder(
                        padding: const EdgeInsets.all(_gridPadding),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _gridCrossAxisCount,
                          mainAxisSpacing: _gridSpacing,
                          crossAxisSpacing: _gridSpacing,
                          childAspectRatio: aspectRatio,
                        ),
                        itemCount: promos.length,
                        itemBuilder: (context, index) {
                          final promo = promos[index];
                          return PromoCard(
                            promo: promo,
                            isFavorite: favorites.contains(promo.id),
                            onTap: () => context.push('/promo/${promo.id}'),
                          );
                        },
                      ),
                    );
                  },
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
