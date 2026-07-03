import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Sélection de la photo d'une promo. `cameraOnly: true` retire l'option
/// galerie — utilisé pour l'agent terrain, où la photo doit obligatoirement
/// être prise dans l'app comme preuve de passage (specs §3.3/§5.5).
class PhotoPickerField extends StatelessWidget {
  const PhotoPickerField({
    super.key,
    required this.file,
    required this.onChanged,
    this.cameraOnly = false,
  });

  final File? file;
  final ValueChanged<File> onChanged;
  final bool cameraOnly;

  Future<void> _pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 90);
    if (picked != null) onChanged(File(picked.path));
  }

  @override
  Widget build(BuildContext context) {
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
            child: file != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(file!, fit: BoxFit.cover),
                  )
                : const Center(child: Icon(Icons.photo_camera_outlined, size: 48)),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Prendre une photo'),
                onPressed: () => _pick(ImageSource.camera),
              ),
            ),
            if (!cameraOnly) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galerie'),
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
