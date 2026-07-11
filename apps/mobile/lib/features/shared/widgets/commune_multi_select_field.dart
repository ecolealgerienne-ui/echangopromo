import 'package:flutter/material.dart';
import '../../../domain/models/commune.dart';
import '../../../l10n/app_localizations.dart';

/// Sélection multiple de communes (assignation de territoire à un agent —
/// remplace l'ancienne Zone opérationnelle, abandonnée : un agent doit
/// pouvoir couvrir plusieurs communes). "Assigner toute la wilaya" est une
/// simple commodité qui coche en masse toutes les communes de la wilaya
/// affichée — pas un champ séparé, pour garder cette liste comme unique
/// source de vérité.
class CommuneMultiSelectField extends StatefulWidget {
  const CommuneMultiSelectField({
    super.key,
    required this.communes,
    required this.selectedCommuneIds,
    required this.onChanged,
  });

  final List<Commune> communes;
  final Set<String> selectedCommuneIds;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<CommuneMultiSelectField> createState() => _CommuneMultiSelectFieldState();
}

class _CommuneMultiSelectFieldState extends State<CommuneMultiSelectField> {
  String? _wilaya;

  @override
  void initState() {
    super.initState();
    final wilayas = widget.communes.map((c) => c.wilaya).toSet().toList()..sort();
    _wilaya = wilayas.isNotEmpty ? wilayas.first : null;
  }

  void _toggle(Iterable<String> communeIds, bool checked) {
    final updated = Set<String>.from(widget.selectedCommuneIds);
    for (final id in communeIds) {
      if (checked) {
        updated.add(id);
      } else {
        updated.remove(id);
      }
    }
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final wilayas = widget.communes.map((c) => c.wilaya).toSet().toList()..sort();
    final communesForWilaya = widget.communes.where((c) => c.wilaya == _wilaya).toList();
    final allSelectedInWilaya = communesForWilaya.isNotEmpty &&
        communesForWilaya.every((c) => widget.selectedCommuneIds.contains(c.id));

    return Column(
      // `mainAxisSize.min` — sans ça, ce Column (mainAxisSize.max par
      // défaut) s'étire sur toute la hauteur disponible dans l'AlertDialog
      // (proche de l'écran entier) au lieu de ne prendre que la hauteur de
      // son contenu, laissant un grand espace vide entre la liste (bornée à
      // 240px) et les boutons Annuler/Valider.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _wilaya,
          decoration: InputDecoration(labelText: l10n.wilayaLabel),
          items: [for (final w in wilayas) DropdownMenuItem(value: w, child: Text(w))],
          onChanged: (v) => setState(() => _wilaya = v),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.communesSelectedCount(widget.selectedCommuneIds.length),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        CheckboxListTile(
          value: allSelectedInWilaya,
          title: Text(l10n.selectAllInWilayaLabel),
          onChanged: communesForWilaya.isEmpty
              ? null
              : (checked) => _toggle(communesForWilaya.map((c) => c.id), checked ?? false),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          // `Column` + `SingleChildScrollView` plutôt que `ListView` — même
          // avec `shrinkWrap: true` et une hauteur bornée, un `ListView`
          // reste un viewport qui refuse toute requête de dimension
          // intrinsèque (`RenderShrinkWrappingViewport does not support
          // returning intrinsic dimensions`), qui plante dès que le champ
          // est placé dans un `AlertDialog` (celui-ci calcule une largeur
          // intrinsèque pour dimensionner le dialogue). Liste de communes
          // par wilaya de taille modeste, pas besoin de virtualisation.
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final commune in communesForWilaya)
                  CheckboxListTile(
                    dense: true,
                    value: widget.selectedCommuneIds.contains(commune.id),
                    title: Text(commune.nom),
                    onChanged: (checked) => _toggle([commune.id], checked ?? false),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
