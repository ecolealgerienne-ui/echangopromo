import 'package:flutter/material.dart';
import '../../../domain/enums/categorie.dart';
import '../../../l10n/app_localizations.dart';
import '../l10n/enum_labels.dart';

class CategoryDropdown extends StatelessWidget {
  const CategoryDropdown({super.key, required this.value, required this.onChanged});

  final Categorie? value;
  final ValueChanged<Categorie?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DropdownButtonFormField<Categorie>(
      // `initialValue` n'est lu qu'une fois par le FormField interne — sans
      // cette clé dépendant de `value`, un changement programmatique (ex.
      // pré-remplissage depuis la catégorie du commerçant) ne se
      // refléterait pas visuellement tant que l'utilisateur n'a pas
      // lui-même touché le menu.
      key: ValueKey(value),
      initialValue: value,
      decoration: InputDecoration(labelText: l10n.categoryLabel),
      items: [
        for (final categorie in Categorie.values)
          DropdownMenuItem(value: categorie, child: Text(categorieLabel(context, categorie))),
      ],
      onChanged: onChanged,
      validator: (value) => value == null ? l10n.categoryRequired : null,
    );
  }
}
