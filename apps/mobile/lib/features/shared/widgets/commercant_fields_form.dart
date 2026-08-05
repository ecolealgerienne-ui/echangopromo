import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/enums/categorie.dart';
import '../../../l10n/app_localizations.dart';
import '../../client/providers/commune_providers.dart';
import 'api_error_text.dart';
import 'category_dropdown.dart';
import 'form_section.dart';
import 'commune_cascade_field.dart';
import 'location_capture_field.dart';
import 'photo_picker_field.dart';

/// Champs communs à la création d'une fiche commerçant (auto-inscription et
/// création par l'agent) : photo, téléphone, nom, adresse, position GPS,
/// catégorie, commune — factorisé pour éviter la duplication entre
/// `CommercantRegisterScreen`/`CreateCommercantScreen` (audit qualité de
/// code). Le PIN (uniquement à l'auto-inscription) reste géré par l'écran
/// appelant, ajouté après ce widget dans le formulaire.
class CommercantFieldsForm extends ConsumerWidget {
  const CommercantFieldsForm({
    super.key,
    required this.photo,
    required this.onPhotoChanged,
    required this.telephoneController,
    required this.nomController,
    required this.adresseController,
    required this.latitude,
    required this.longitude,
    required this.onLocationChanged,
    required this.categorie,
    required this.onCategorieChanged,
    required this.communeId,
    required this.onCommuneChanged,
    this.startIndex,
  });

  final File? photo;
  final ValueChanged<File> onPhotoChanged;
  final TextEditingController telephoneController;
  final TextEditingController nomController;
  final TextEditingController adresseController;
  final double? latitude;
  final double? longitude;
  final void Function(double latitude, double longitude) onLocationChanged;
  final Categorie? categorie;
  final ValueChanged<Categorie?> onCategorieChanged;
  final String? communeId;
  final ValueChanged<String?> onCommuneChanged;

  /// Numéro de la première section. `null` pour un formulaire sans étapes
  /// numérotées (création par un agent, qui n'est pas un parcours guidé).
  final int? startIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final communesAsync = ref.watch(communeListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormSection(
          index: startIndex,
          title: l10n.commercantSectionShop,
          subtitle: l10n.commercantSectionShopHint,
          children: [
            PhotoPickerField(file: photo, onChanged: onPhotoChanged),
            const SizedBox(height: 16),
            TextFormField(
              controller: nomController,
              decoration: InputDecoration(labelText: l10n.nomCommerceLabel),
              validator: (v) =>
                  (v == null || v.isEmpty) ? l10n.nomRequired : null,
            ),
            const SizedBox(height: 12),
            CategoryDropdown(value: categorie, onChanged: onCategorieChanged),
            const SizedBox(height: 12),
            TextFormField(
              controller: telephoneController,
              decoration: InputDecoration(
                labelText: l10n.telephoneLabel,
                hintText: l10n.telephoneHint,
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
              validator: (v) =>
                  (v == null || v.isEmpty) ? l10n.telephoneRequired : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        FormSection(
          index: startIndex == null ? null : startIndex! + 1,
          title: l10n.commercantSectionWhere,
          subtitle: l10n.commercantSectionWhereHint,
          children: [
            TextFormField(
              controller: adresseController,
              decoration: InputDecoration(labelText: l10n.adresseLabel),
            ),
            const SizedBox(height: 12),
            communesAsync.when(
              loading: () => const LinearProgressIndicator(),
              // Dernier `error.toString()` du dépôt — et sur le tout premier
              // écran de saisie du produit : un `GET /commune` en échec y
              // affichait le message backend, **toujours en français**, quelle
              // que soit la langue choisie, plus le dump Dio en première ligne.
              // Les 15 autres sites passent par ce widget depuis longtemps
              // (revue 2026-08-05, règle #26).
              error: (error, _) => ApiErrorText(error),
              data: (communes) => CommuneCascadeField(
                communes: communes,
                selectedCommuneId: communeId,
                onChanged: onCommuneChanged,
              ),
            ),
            const SizedBox(height: 12),
            LocationCaptureField(
              latitude: latitude,
              longitude: longitude,
              onChanged: onLocationChanged,
            ),
          ],
        ),
      ],
    );
  }
}
