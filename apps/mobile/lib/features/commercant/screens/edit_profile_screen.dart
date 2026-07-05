import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/widgets/category_dropdown.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/loading_button.dart';
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
    final l10n = AppLocalizations.of(context)!;
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
      setState(() => _error = extractApiErrorMessage(
            error,
            fallback: l10n.modifyFailed,
            locale: Localizations.localeOf(context),
          ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
      appBar: AppBar(
        title: Text(l10n.editProfileTitle),
        actions: const [LanguageSwitcherButton()],
      ),
      body: meAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.commonError(error.toString()))),
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
                  decoration: InputDecoration(labelText: l10n.nomCommerceLabel),
                  validator: (v) => (v == null || v.isEmpty) ? l10n.nomRequired : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adresseController,
                  decoration: InputDecoration(labelText: l10n.adresseLabel),
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
                ErrorText(_error),
                const SizedBox(height: 16),
                LoadingButton(loading: _loading, onPressed: _submit, label: l10n.saveLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
