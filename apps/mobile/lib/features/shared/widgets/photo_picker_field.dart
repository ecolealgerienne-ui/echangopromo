import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../l10n/app_localizations.dart';

/// Sélection de la photo d'une promo. `cameraOnly: true` retire l'option
/// galerie — utilisé pour l'agent terrain, où la photo doit obligatoirement
/// être prise dans l'app comme preuve de passage (specs §3.3/§5.5).
class PhotoPickerField extends StatelessWidget {
  const PhotoPickerField({
    super.key,
    required this.file,
    required this.onChanged,
    this.cameraOnly = false,
    this.existingImageUrl,
  });

  final File? file;
  final ValueChanged<File> onChanged;
  final bool cameraOnly;

  /// Photo déjà enregistrée côté serveur (édition) — affichée tant que
  /// l'utilisateur n'a pas choisi de nouvelle photo locale (`file`). Sans
  /// ça, un écran d'édition n'affiche qu'un placeholder vide même quand une
  /// photo existe déjà.
  final String? existingImageUrl;

  Future<void> _pick(ImageSource source) async {
    // Pas de `imageQuality` ici : `StorageApi._compress` recompresse de
    // toute façon par paliers jusqu'à la cible finale (~250 Ko) juste avant
    // l'upload — un premier passage JPEG qualité 90 ici n'aurait fait que
    // décoder/réencoder l'image pour rien.
    final picked = await ImagePicker().pickImage(source: source);
    if (picked != null) onChanged(File(picked.path));
  }

  Widget _buildPreview(BuildContext context) {
    if (file != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(file!, fit: BoxFit.cover),
      );
    }
    if (existingImageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          existingImageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Center(child: Icon(Icons.photo_camera_outlined, size: 48)),
        ),
      );
    }
    return const Center(child: Icon(Icons.photo_camera_outlined, size: 48));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _buildPreview(context),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(l10n.photoPickerTakePhoto),
                onPressed: () => _pick(ImageSource.camera),
              ),
            ),
            if (!cameraOnly) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(l10n.photoPickerGallery),
                  onPressed: () => _pick(ImageSource.gallery),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
