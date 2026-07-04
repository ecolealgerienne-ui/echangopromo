import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../shared/widgets/category_dropdown.dart';
import '../../shared/widgets/location_capture_field.dart';
import '../../shared/widgets/photo_picker_field.dart';
import '../../../providers/core_providers.dart';

final _editProfileMeProvider =
    FutureProvider.autoDispose((ref) => ref.watch(commercantApiProvider).me());

/// Édition du profil commerçant après inscription (nom, adresse, catégorie,
/// photo, position GPS) — téléphone volontairement non modifiable ici.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _adresseController = TextEditingController();
  Categorie? _categorie;
  double? _latitude;
  double? _longitude;
  File? _photo;
  bool _loading = false;
  bool _prefilled = false;
  String? _error;

  @override
  void dispose() {
    _nomController.dispose();
    _adresseController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String? photoKey;
      if (_photo != null) {
        photoKey = await ref.read(storageApiProvider).uploadPhoto(_photo!, purpose: 'commercant');
      }
      await ref.read(commercantApiProvider).updateProfile(
            nom: _nomController.text.trim(),
            adresse: _adresseController.text.trim(),
            categorie: _categorie,
            photoKey: photoKey,
            latitude: _latitude,
            longitude: _longitude,
          );
      ref.invalidate(_editProfileMeProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(error, fallback: 'Modification impossible.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meAsync = ref.watch(_editProfileMeProvider);

    ref.listen(_editProfileMeProvider, (previous, next) {
      if (_prefilled) return;
      next.whenData((me) {
        _prefilled = true;
        _nomController.text = me.nom;
        _adresseController.text = me.adresse ?? '';
        setState(() {
          _categorie = me.categorie;
          _latitude = me.latitude;
          _longitude = me.longitude;
        });
      });
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Modifier mon profil')),
      body: meAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (_) => Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                PhotoPickerField(file: _photo, onChanged: (file) => setState(() => _photo = file)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nomController,
                  decoration: const InputDecoration(labelText: 'Nom du commerce'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Nom requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adresseController,
                  decoration: const InputDecoration(labelText: 'Adresse (optionnel)'),
                ),
                const SizedBox(height: 12),
                LocationCaptureField(
                  latitude: _latitude,
                  longitude: _longitude,
                  onChanged: (lat, lng) => setState(() {
                    _latitude = lat;
                    _longitude = lng;
                  }),
                ),
                const SizedBox(height: 12),
                CategoryDropdown(value: _categorie, onChanged: (v) => setState(() => _categorie = v)),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enregistrer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
