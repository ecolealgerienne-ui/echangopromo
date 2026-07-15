import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../shared/validators/pin_validator.dart';
import '../../shared/widgets/api_error_text.dart';
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

  /// Libre-service : le commerçant connaît encore son PIN actuel et veut le
  /// changer (décision produit 2026-07-13 — contrairement au flux "PIN
  /// oublié", qui passe par un admin/agent). Le token courant devient
  /// invalide dès l'appel réussi (tokenVersion incrémenté côté service) :
  /// on déconnecte et renvoie vers l'accueil plutôt que de laisser un futur
  /// appel échouer de façon inattendue.
  Future<void> _changePin() async {
    final l10n = AppLocalizations.of(context)!;
    final oldPinController = TextEditingController();
    final newPinController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.changePinDialogTitle),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: oldPinController,
                decoration: InputDecoration(labelText: l10n.oldPinLabel),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 12,
                validator: validateExistingPin(context),
              ),
              TextFormField(
                controller: newPinController,
                decoration: InputDecoration(labelText: l10n.newPinLabel),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 12,
                validator: validatePin(context),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context, true);
            },
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(commercantApiProvider).changePin(
            oldPin: oldPinController.text.trim(),
            newPin: newPinController.text.trim(),
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.changePinSuccessMessage),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonUnderstood)),
          ],
        ),
      );
      if (!mounted) return;
      await ref.read(authControllerProvider.notifier).logout();
      if (mounted) context.go('/');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(extractApiErrorMessage(
              error,
              fallback: l10n.operationFailed,
              locale: Localizations.localeOf(context),
            )),
          ),
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteAccountConfirmTitle),
        content: Text(l10n.deleteAccountConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.deleteAccountLabel,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(commercantApiProvider).deleteAccount();
      await ref.read(authControllerProvider.notifier).logout();
      if (mounted) context.go('/');
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(
            error,
            fallback: l10n.deleteAccountFailed,
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
        error: (error, _) => Center(child: ApiErrorText(error)),
        data: (me) => Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                PhotoPickerField(
                  file: _photo,
                  onChanged: (file) => setState(() => _photo = file),
                  existingImageUrl: me.photoUrl,
                ),
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
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _loading ? null : _changePin,
                  child: Text(l10n.changePinLabel),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => context.push('/legal/cgu'),
                      child: Text(l10n.legalCguLinkLabel),
                    ),
                    TextButton(
                      onPressed: () => context.push('/legal/confidentialite'),
                      child: Text(l10n.legalPrivacyLinkLabel),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(color: Theme.of(context).colorScheme.error),
                  ),
                  onPressed: _loading ? null : _deleteAccount,
                  child: Text(l10n.deleteAccountLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
