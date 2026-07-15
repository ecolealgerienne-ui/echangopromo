import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../l10n/app_localizations.dart';

/// Un emplacement du sélecteur multi-photo : soit une photo déjà envoyée au
/// serveur (clé S3 connue, réutilisée telle quelle si l'utilisateur ne la
/// touche pas — évite un réupload inutile en édition), soit une photo tout
/// juste choisie sur l'appareil, pas encore envoyée.
sealed class PhotoSlotItem {
  const PhotoSlotItem();
}

class ExistingPhotoItem extends PhotoSlotItem {
  const ExistingPhotoItem(this.key, this.url);

  /// Clé S3 (`Promo.photoKeys`, propriétaire authentifié uniquement) —
  /// renvoyée telle quelle si la photo n'est pas retirée.
  final String key;
  final String url;
}

class NewPhotoItem extends PhotoSlotItem {
  const NewPhotoItem(this.file);

  final File file;
}

/// Sélection de 1 à [maxPhotos] photos pour une promo (décision produit
/// 2026-07-12 : une seule photo ne suffit pas à juger un produit). La
/// première est la photo principale (utilisée en liste/vignette), les
/// suivantes sont optionnelles. `cameraOnly: true` retire l'option galerie
/// (agent terrain, preuve de passage — même règle que l'ancien
/// `PhotoPickerField`, qui reste utilisé tel quel pour la photo de commerce
/// et le registre, hors scope ici).
class MultiPhotoPickerField extends StatelessWidget {
  const MultiPhotoPickerField({
    super.key,
    required this.items,
    required this.onChanged,
    this.cameraOnly = false,
    this.maxPhotos = 3,
  });

  final List<PhotoSlotItem> items;
  final ValueChanged<List<PhotoSlotItem>> onChanged;
  final bool cameraOnly;
  final int maxPhotos;

  Future<void> _pickFrom(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked != null) {
      onChanged([...items, NewPhotoItem(File(picked.path))]);
    }
  }

  Future<void> _addPhoto(BuildContext context) async {
    if (cameraOnly) {
      await _pickFrom(ImageSource.camera);
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(l10n.photoPickerTakePhoto),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.photoPickerGallery),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickFrom(source);
  }

  void _removeAt(int index) {
    final updated = [...items]..removeAt(index);
    onChanged(updated);
  }

  Widget _slot(BuildContext context, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    if (index >= items.length) {
      final isNext = index == items.length;
      return AspectRatio(
        aspectRatio: 1,
        child: Material(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          child: isNext
              ? InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _addPhoto(context),
                  child: Icon(Icons.add_a_photo_outlined, color: colorScheme.onSurfaceVariant),
                )
              : Icon(Icons.image_outlined, color: colorScheme.outlineVariant),
        ),
      );
    }

    final item = items[index];
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: switch (item) {
              ExistingPhotoItem(:final url) => Image.network(url, fit: BoxFit.cover),
              NewPhotoItem(:final file) => Image.file(file, fit: BoxFit.cover),
            },
          ),
          PositionedDirectional(
            top: 4,
            end: 4,
            child: GestureDetector(
              onTap: () => _removeAt(index),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < maxPhotos; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _slot(context, i)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(l10n.promoPhotosHint, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
