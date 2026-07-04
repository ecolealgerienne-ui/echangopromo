import 'dart:io';

import 'package:flutter/material.dart';
import '../../../domain/enums/categorie.dart';
import 'category_dropdown.dart';
import 'photo_picker_field.dart';

const promoDescriptionMaxLength = 140;

/// Champs communs aux formulaires de promo (commerçant et agent) : photo,
/// description, prix avant/après, catégorie, et éventuellement la durée de
/// validité — factorisé pour éviter la duplication entre
/// `PromoFormScreen`/`AgentPromoFormScreen` (audit qualité de code).
class PromoFormFields extends StatelessWidget {
  const PromoFormFields({
    super.key,
    required this.photo,
    required this.onPhotoChanged,
    this.cameraOnly = false,
    required this.descriptionController,
    required this.prixAvantController,
    required this.prixApresController,
    required this.prixApresValidator,
    required this.categorie,
    required this.onCategorieChanged,
    this.dureeJours,
    this.onDureeJoursChanged,
    this.maxDureeJours = 7,
  });

  final File? photo;
  final ValueChanged<File> onPhotoChanged;
  final bool cameraOnly;
  final TextEditingController descriptionController;
  final TextEditingController prixAvantController;
  final TextEditingController prixApresController;
  final FormFieldValidator<String> prixApresValidator;
  final Categorie? categorie;
  final ValueChanged<Categorie?> onCategorieChanged;

  /// Null pour ne pas afficher le sélecteur de durée (ex. édition de contenu).
  final int? dureeJours;
  final ValueChanged<int?>? onDureeJoursChanged;
  final int maxDureeJours;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhotoPickerField(file: photo, cameraOnly: cameraOnly, onChanged: onPhotoChanged),
        const SizedBox(height: 16),
        TextFormField(
          controller: descriptionController,
          decoration: const InputDecoration(labelText: 'Description'),
          maxLines: 3,
          maxLength: promoDescriptionMaxLength,
          validator: (v) => (v == null || v.isEmpty) ? 'Description requise' : null,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: prixAvantController,
                decoration: const InputDecoration(labelText: 'Prix avant (DA)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => (double.tryParse(v ?? '') == null) ? 'Invalide' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: prixApresController,
                decoration: const InputDecoration(labelText: 'Prix après (DA)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: prixApresValidator,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CategoryDropdown(value: categorie, onChanged: onCategorieChanged),
        if (dureeJours != null) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: dureeJours,
            decoration: const InputDecoration(labelText: 'Durée de validité'),
            items: [
              for (var jours = 1; jours <= maxDureeJours; jours++)
                DropdownMenuItem(value: jours, child: Text('$jours jour${jours > 1 ? 's' : ''}')),
            ],
            onChanged: onDureeJoursChanged,
          ),
        ],
      ],
    );
  }
}
