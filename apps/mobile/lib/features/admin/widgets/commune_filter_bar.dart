import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/models/commune.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';

final _communesProvider = FutureProvider.autoDispose((ref) => ref.watch(communeApiProvider).list());

/// Filtre wilaya → commune pour les écrans de liste admin/agent (retour
/// terrain 2026-07-14 : "il faut ajouter des filtres, wilaya, commune...").
/// Contrairement à `CommuneCascadeField` (formulaire, sélection obligatoire),
/// les deux niveaux sont ici optionnels ("Toutes") — le scope agent reste de
/// toute façon réappliqué côté backend (`AdminController.scopedCommuneIds`),
/// ce filtre ne fait qu'affiner la vue, jamais l'élargir.
class CommuneFilterBar extends ConsumerWidget {
  const CommuneFilterBar({
    super.key,
    required this.wilaya,
    required this.communeId,
    required this.onWilayaChanged,
    required this.onCommuneChanged,
  });

  final String? wilaya;
  final String? communeId;
  final ValueChanged<String?> onWilayaChanged;
  final ValueChanged<String?> onCommuneChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final communesAsync = ref.watch(_communesProvider);

    return communesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (communes) {
        final wilayas = communes.map((c) => c.wilaya).toSet().toList()..sort();
        final communesForWilaya =
            wilaya == null ? const <Commune>[] : communes.where((c) => c.wilaya == wilaya).toList();

        return Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: wilaya,
                decoration: InputDecoration(
                  labelText: l10n.wilayaLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.filterAllOption)),
                  for (final w in wilayas) DropdownMenuItem(value: w, child: Text(w)),
                ],
                onChanged: (value) {
                  onWilayaChanged(value);
                  onCommuneChanged(null);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: communeId,
                decoration: InputDecoration(
                  labelText: l10n.communeLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.filterAllOption)),
                  for (final c in communesForWilaya) DropdownMenuItem(value: c.id, child: Text(c.nom)),
                ],
                onChanged: wilaya == null ? null : onCommuneChanged,
              ),
            ),
          ],
        );
      },
    );
  }
}
