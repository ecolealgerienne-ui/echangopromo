import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/promo_providers.dart';

/// Feuille modale de **tri** (proposition 2026-07-11, inspirée de
/// Karrot/Bonial : appliqué en direct, pas de bouton « Valider » — un simple
/// reclassement local, pas une requête à confirmer).
///
/// ⚠️ **Elle portait aussi « Afficher seulement mes favoris » jusqu'au
/// 2026-08-16.** Cet interrupteur écrivait le même bit que l'onglet « Favoris »
/// de la barre du bas, en le racontant autrement : ici un filtre, là-bas une
/// destination — et l'écran affichait les deux lectures en même temps. Les
/// favoris sont devenus un lieu (`favoritesModeProvider`) ; il ne reste ici
/// que ce qui règle vraiment l'affichage courant.
Future<void> showPromoSortSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _PromoSortSheetContent(),
  );
}

class _PromoSortSheetContent extends ConsumerWidget {
  const _PromoSortSheetContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
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
                  child: Text(l10n.sortTitle,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: () => ref.read(promoSortProvider.notifier).state =
                      PromoSort.proximite,
                  child: Text(l10n.resetFiltersLabel),
                ),
              ],
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
      case PromoSort.proximite:
        return l10n.sortProximite;
      case PromoSort.expireBientot:
        return l10n.sortExpireBientot;
      case PromoSort.plusGrosseReduction:
        return l10n.sortPlusGrosseReduction;
      case PromoSort.nouveautes:
        return l10n.sortNouveautes;
    }
  }
}
