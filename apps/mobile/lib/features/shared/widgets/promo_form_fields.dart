import 'dart:io';

import 'package:flutter/material.dart';
import '../../../domain/enums/categorie.dart';
import '../../../l10n/app_localizations.dart';
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
    this.existingPhotoUrl,
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

  /// Photo déjà enregistrée (édition) — affichée tant qu'aucune nouvelle
  /// photo locale n'a été choisie. Null en création (rien à afficher).
  final String? existingPhotoUrl;
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
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhotoPickerField(
          file: photo,
          cameraOnly: cameraOnly,
          onChanged: onPhotoChanged,
          existingImageUrl: existingPhotoUrl,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: descriptionController,
          decoration: InputDecoration(labelText: l10n.descriptionLabel),
          maxLines: 3,
          maxLength: promoDescriptionMaxLength,
          validator: (v) => (v == null || v.isEmpty) ? l10n.descriptionRequired : null,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: prixAvantController,
                decoration: InputDecoration(labelText: l10n.prixAvantLabel),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => (double.tryParse(v ?? '') == null) ? l10n.commonInvalid : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: prixApresController,
                decoration: InputDecoration(labelText: l10n.prixApresLabel),
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
            decoration: InputDecoration(labelText: l10n.dureeValiditeLabel),
            items: [
              for (var jours = 1; jours <= maxDureeJours; jours++)
                DropdownMenuItem(value: jours, child: Text(l10n.dureeJoursOption(jours))),
            ],
            onChanged: onDureeJoursChanged,
          ),
        ],
      ],
    );
  }
}
