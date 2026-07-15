import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/promo_providers.dart';

/// Feuille modale "Filtres et tri" (proposition 2026-07-11, inspirée de
/// Karrot/Bonial : filtre appliqué en direct, pas de bouton "Valider" — un
/// simple reclassement/filtrage local, pas une requête à confirmer).
Future<void> showPromoFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _PromoFilterSheetContent(),
  );
}

class _PromoFilterSheetContent extends ConsumerWidget {
  const _PromoFilterSheetContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final favoritesOnly = ref.watch(favoritesOnlyFilterProvider);
    final sort = ref.watch(promoSortProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(l10n.filtersSortTitle, style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(favoritesOnlyFilterProvider.notifier).state = false;
                    ref.read(promoSortProvider.notifier).state = PromoSort.nouveautes;
                  },
                  child: Text(l10n.resetFiltersLabel),
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: Text(l10n.favoritesOnlyLabel),
            secondary: const Icon(Icons.favorite_outline),
            value: favoritesOnly,
            onChanged: (v) => ref.read(favoritesOnlyFilterProvider.notifier).state = v,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.sortByLabel,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          RadioGroup<PromoSort>(
            groupValue: sort,
            onChanged: (v) => ref.read(promoSortProvider.notifier).state = v!,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in PromoSort.values)
                  RadioListTile<PromoSort>(
                    title: Text(_sortLabel(l10n, option)),
                    value: option,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _sortLabel(AppLocalizations l10n, PromoSort sort) {
    switch (sort) {
      case PromoSort.expireBientot:
        return l10n.sortExpireBientot;
      case PromoSort.plusGrosseReduction:
        return l10n.sortPlusGrosseReduction;
      case PromoSort.nouveautes:
        return l10n.sortNouveautes;
    }
  }
}
