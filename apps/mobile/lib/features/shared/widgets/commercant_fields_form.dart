import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/enums/categorie.dart';
import '../../client/providers/commune_providers.dart';
import 'category_dropdown.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final communesAsync = ref.watch(communeListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhotoPickerField(file: photo, onChanged: onPhotoChanged),
        const SizedBox(height: 16),
        TextFormField(
          controller: telephoneController,
          decoration: const InputDecoration(labelText: 'Téléphone', hintText: '+213...'),
          keyboardType: TextInputType.phone,
          validator: (v) => (v == null || v.isEmpty) ? 'Téléphone requis' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: nomController,
          decoration: const InputDecoration(labelText: 'Nom du commerce'),
          validator: (v) => (v == null || v.isEmpty) ? 'Nom requis' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: adresseController,
          decoration: const InputDecoration(labelText: 'Adresse (optionnel)'),
        ),
        const SizedBox(height: 12),
        LocationCaptureField(latitude: latitude, longitude: longitude, onChanged: onLocationChanged),
        const SizedBox(height: 12),
        CategoryDropdown(value: categorie, onChanged: onCategorieChanged),
        const SizedBox(height: 12),
        communesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('Erreur communes : $error'),
          data: (communes) => CommuneCascadeField(
            communes: communes,
            selectedCommuneId: communeId,
            onChanged: onCommuneChanged,
          ),
        ),
      ],
    );
  }
}
