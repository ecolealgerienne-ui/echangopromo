import 'package:flutter/material.dart';
import '../../../domain/models/commune.dart';

/// Sélection guidée wilaya → commune (specs §3.1 : "pour les grandes villes,
/// sélection affinée par commune") plutôt qu'une liste plate de communes —
/// ne change rien au pilote Djelfa (une seule wilaya) mais prépare
/// l'extension multi-wilaya sans reprendre l'écran.
class CommuneCascadeField extends StatefulWidget {
  const CommuneCascadeField({
    super.key,
    required this.communes,
    required this.selectedCommuneId,
    required this.onChanged,
  });

  final List<Commune> communes;
  final String? selectedCommuneId;
  final ValueChanged<String?> onChanged;

  @override
  State<CommuneCascadeField> createState() => _CommuneCascadeFieldState();
}

class _CommuneCascadeFieldState extends State<CommuneCascadeField> {
  String? _wilaya;

  @override
  void initState() {
    super.initState();
    _wilaya = _wilayaOf(widget.selectedCommuneId);
  }

  String? _wilayaOf(String? communeId) {
    if (communeId == null) return null;
    for (final commune in widget.communes) {
      if (commune.id == communeId) return commune.wilaya;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final wilayas = widget.communes.map((c) => c.wilaya).toSet().toList()..sort();
    final communesForWilaya =
        widget.communes.where((c) => c.wilaya == _wilaya).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _wilaya,
          decoration: const InputDecoration(labelText: 'Wilaya'),
          items: [
            for (final wilaya in wilayas) DropdownMenuItem(value: wilaya, child: Text(wilaya)),
          ],
          onChanged: (value) {
            setState(() => _wilaya = value);
            widget.onChanged(null);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: widget.selectedCommuneId,
          decoration: const InputDecoration(labelText: 'Commune'),
          items: [
            for (final commune in communesForWilaya)
              DropdownMenuItem(value: commune.id, child: Text(commune.nom)),
          ],
          onChanged: _wilaya == null ? null : widget.onChanged,
        ),
      ],
    );
  }
}
