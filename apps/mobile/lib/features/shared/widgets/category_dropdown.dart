import 'package:flutter/material.dart';
import '../../../domain/enums/categorie.dart';

class CategoryDropdown extends StatelessWidget {
  const CategoryDropdown({super.key, required this.value, required this.onChanged});

  final Categorie? value;
  final ValueChanged<Categorie?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Categorie>(
      value: value,
      decoration: const InputDecoration(labelText: 'Catégorie'),
      items: [
        for (final categorie in Categorie.values)
          DropdownMenuItem(value: categorie, child: Text(categorie.label)),
      ],
      onChanged: onChanged,
      validator: (value) => value == null ? 'Catégorie requise' : null,
    );
  }
}
