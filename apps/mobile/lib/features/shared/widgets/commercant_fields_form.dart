import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/enums/categorie.dart';
import '../../../l10n/app_localizations.dart';
import '../data/pays.dart';
import 'category_dropdown.dart';
import 'form_section.dart';
import 'location_capture_field.dart';
import 'photo_picker_field.dart';
import 'telephone_field.dart';

/// Champs communs à la création d'une fiche commerçant (auto-inscription et
/// création par l'agent) : photo, téléphone, nom, adresse, position GPS,
/// catégorie — factorisé pour éviter la duplication entre
/// `CommercantRegisterScreen`/`CreateCommercantScreen` (audit qualité de
/// code). Le PIN (uniquement à l'auto-inscription) reste géré par l'écran
/// appelant, ajouté après ce widget dans le formulaire.
///
/// ⚠️ **Le sélecteur wilaya → commune a disparu le 2026-08-13.** Le lieu du
/// commerce ne s'exprime plus que de deux façons : sa **position** sur la
/// carte, qui décide de tout, et son **adresse** en texte libre, facultative
/// et purement indicative. Retirer la cascade ferme au passage le dernier
/// `error.toString()` du dépôt (règle #26) : un `GET /commune` en échec y
/// affichait le message backend brut, toujours en français, dans une app
/// trilingue — et sur le tout premier écran de saisie du produit.
class CommercantFieldsForm extends ConsumerWidget {
  const CommercantFieldsForm({
    super.key,
    required this.photo,
    required this.onPhotoChanged,
    required this.telephoneController,
    required this.pays,
    required this.onPaysChanged,
    required this.nomController,
    this.positionRequise = false,
    required this.adresseController,
    required this.latitude,
    required this.longitude,
    required this.onLocationChanged,
    required this.categorie,
    required this.onCategorieChanged,
    this.startIndex,
  });

  final File? photo;
  final ValueChanged<File> onPhotoChanged;
  final TextEditingController telephoneController;

  /// Pays de l'indicatif — porté par l'écran appelant, parce que c'est lui qui
  /// l'envoie au serveur avec le reste de la fiche.
  final Pays pays;
  final ValueChanged<Pays> onPaysChanged;

  final TextEditingController nomController;

  /// ⚠️ Vrai sur l'écran de l'agent uniquement : il est physiquement dans le
  /// commerce, c'est la seule capture juste par construction. L'auto-inscription
  /// garde une position facultative — c'est la PUBLICATION qui la réclamera.
  final bool positionRequise;

  final TextEditingController adresseController;
  final double? latitude;
  final double? longitude;
  final void Function(double latitude, double longitude) onLocationChanged;
  final Categorie? categorie;
  final ValueChanged<Categorie?> onCategorieChanged;

  /// Numéro de la première section. `null` pour un formulaire sans étapes
  /// numérotées (création par un agent, qui n'est pas un parcours guidé).
  final int? startIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

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
            TelephoneField(
              controller: telephoneController,
              pays: pays,
              onPaysChanged: onPaysChanged,
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
            LocationCaptureField(
              latitude: latitude,
              longitude: longitude,
              // ⚠️ **Ce `requis:` a manqué du 2026-08-12 au 2026-08-13**, et rien
              // ne pouvait le dire : `LocationCaptureField.requis` a une valeur
              // par défaut, donc l'oubli compile. Le drapeau existait, l'écran de
              // l'agent le passait à `true`, et il mourait ici — l'écran affichait
              // « (optionnel) » tout en refusant la validation sans position.
              //
              // C'est le défaut que ce drapeau avait été créé pour corriger,
              // reproduit un cran plus haut dans la chaîne. Un paramètre optionnel
              // non transmis est invisible : ni compilation, ni analyse, ni test.
              requis: positionRequise,
              onChanged: onLocationChanged,
            ),
          ],
        ),
      ],
    );
  }
}
