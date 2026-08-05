import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../app/theme.dart';
import '../../../domain/enums/categorie.dart';
import '../../../domain/promo_rules.dart';
import '../../../l10n/app_localizations.dart';
import 'category_dropdown.dart';
import 'form_section.dart';
import 'multi_photo_picker_field.dart';

const promoDescriptionMaxLength = 140;

/// Champs communs aux formulaires de promo (commerçant et agent) : photos,
/// description, prix avant/après, catégorie, et éventuellement la durée de
/// validité — factorisé pour éviter la duplication entre
/// `PromoFormScreen`/`AgentPromoFormScreen` (audit qualité de code).
///
/// Découpé en sections depuis la refonte 2026-07-29 : sept champs à la suite
/// ne disaient pas où l'on en était. Chaque section correspond à une question
/// que se pose le commerçant — quoi montrer, quoi vendre, à quel prix,
/// jusqu'à quand.
class PromoFormFields extends StatelessWidget {
  const PromoFormFields({
    super.key,
    required this.photoItems,
    required this.onPhotoItemsChanged,
    this.cameraOnly = false,
    required this.descriptionController,
    required this.prixAvantController,
    required this.prixApresController,
    required this.prixApresValidator,
    required this.categorie,
    required this.onCategorieChanged,
    this.dureeJours,
    this.onDureeJoursChanged,
    this.maxDureeJours = promoMaxDureeJours,
  });

  final List<PhotoSlotItem> photoItems;
  final ValueChanged<List<PhotoSlotItem>> onPhotoItemsChanged;
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
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormSection(
          title: l10n.promoSectionPhotos,
          subtitle: l10n.promoSectionPhotosHint,
          icon: Icons.photo_camera_outlined,
          children: [
            MultiPhotoPickerField(
              items: photoItems,
              onChanged: onPhotoItemsChanged,
              cameraOnly: cameraOnly,
            ),
          ],
        ),
        const SizedBox(height: 12),
        FormSection(
          title: l10n.promoSectionProduct,
          icon: Icons.label_outline,
          children: [
            TextFormField(
              controller: descriptionController,
              decoration: InputDecoration(labelText: l10n.descriptionLabel),
              maxLines: 3,
              maxLength: promoDescriptionMaxLength,
              validator: (v) =>
                  (v == null || v.isEmpty) ? l10n.descriptionRequired : null,
            ),
            const SizedBox(height: 4),
            CategoryDropdown(value: categorie, onChanged: onCategorieChanged),
          ],
        ),
        const SizedBox(height: 12),
        FormSection(
          title: l10n.promoSectionPrice,
          icon: Icons.sell_outlined,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: prixAvantController,
                    decoration: InputDecoration(labelText: l10n.prixAvantLabel),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) => (double.tryParse(v ?? '') == null)
                        ? l10n.commonInvalid
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: prixApresController,
                    decoration: InputDecoration(labelText: l10n.prixApresLabel),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: prixApresValidator,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DiscountPreview(
              prixAvantController: prixAvantController,
              prixApresController: prixApresController,
            ),
          ],
        ),
        if (dureeJours != null) ...[
          const SizedBox(height: 12),
          FormSection(
            title: l10n.promoSectionDuration,
            icon: Icons.schedule,
            children: [
              DropdownButtonFormField<int>(
                initialValue: dureeJours,
                decoration: InputDecoration(labelText: l10n.dureeValiditeLabel),
                items: [
                  for (var jours = 1; jours <= maxDureeJours; jours++)
                    DropdownMenuItem(
                        value: jours,
                        child: Text(l10n.dureeJoursOption(jours))),
                ],
                onChanged: onDureeJoursChanged,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Réduction telle que le client la verra, recalculée à chaque frappe.
///
/// Le commerçant saisissait ses deux prix sans jamais voir le pourcentage
/// affiché côté client — or c'est ce pourcentage qui décide du clic, et une
/// remise de 3 % ne vaut pas la peine d'être publiée. L'afficher pendant la
/// saisie lui permet d'ajuster avant de valider.
class _DiscountPreview extends StatelessWidget {
  const _DiscountPreview({
    required this.prixAvantController,
    required this.prixApresController,
  });

  final TextEditingController prixAvantController;
  final TextEditingController prixApresController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final currency =
        NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0);

    // `Listenable.merge` plutôt que deux `ValueListenableBuilder` imbriqués :
    // un `TextEditingController` est un `ValueNotifier`, les écouter ensemble
    // suffit à se redessiner dès que l'un des deux prix change.
    return AnimatedBuilder(
      animation: Listenable.merge([prixAvantController, prixApresController]),
      builder: (context, _) {
        final avant = double.tryParse(prixAvantController.text.trim());
        final apres = double.tryParse(prixApresController.text.trim());

        // Tant que les deux prix ne forment pas une remise valable, on reste
        // muet : la validation du formulaire dira quoi corriger, un aperçu
        // en erreur pendant la frappe ne ferait que du bruit.
        if (avant == null || apres == null || avant <= 0 || apres >= avant) {
          return const SizedBox.shrink();
        }

        final percent = ((avant - apres) / avant * 100).round();
        final saved = avant - apres;

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  '−$percent%',
                  style: textTheme.labelLarge?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.discountPreview(currency.format(saved)),
                  style: textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onPrimaryContainer),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
