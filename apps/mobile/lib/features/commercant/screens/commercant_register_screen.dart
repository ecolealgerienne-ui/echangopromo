import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../../domain/models/auth_session.dart';
import '../../../providers/auth_provider.dart';
import '../../shared/widgets/commercant_fields_form.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/loading_button.dart';
import '../../../providers/core_providers.dart';

/// Auto-inscription (specs §3.2, voie 1) — sans passage agent requis, et sans
/// OTP : le compte est actif dès la saisie du PIN (décision produit assumée).
class CommercantRegisterScreen extends ConsumerStatefulWidget {
  const CommercantRegisterScreen({super.key});

  @override
  ConsumerState<CommercantRegisterScreen> createState() => _CommercantRegisterScreenState();
}

class _CommercantRegisterScreenState extends ConsumerState<CommercantRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _telephoneController = TextEditingController();
  final _nomController = TextEditingController();
  final _adresseController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  Categorie? _categorie;
  String? _communeId;
  File? _photo;
  double? _latitude;
  double? _longitude;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _telephoneController.dispose();
    _nomController.dispose();
    _adresseController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _communeId == null) {
      setState(() => _error = _communeId == null ? 'Commune requise' : null);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(commercantApiProvider);
      String? photoKey;
      if (_photo != null) {
        photoKey = await ref.read(storageApiProvider).uploadPhoto(_photo!, purpose: 'commercant');
      }
      final token = await api.register(
        telephone: _telephoneController.text.trim(),
        nom: _nomController.text.trim(),
        adresse: _adresseController.text.trim(),
        categorie: _categorie!,
        communeId: _communeId!,
        pin: _pinController.text.trim(),
        photoKey: photoKey,
        latitude: _latitude,
        longitude: _longitude,
      );
      await ref.read(authControllerProvider.notifier).loginThenResolveId(
            role: AppRole.commercant,
            token: token,
            fetchId: () async => (await api.me()).id,
          );
      if (mounted) context.go('/commercant/dashboard');
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(error, fallback: 'Inscription impossible.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte commerçant')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              CommercantFieldsForm(
                photo: _photo,
                onPhotoChanged: (file) => setState(() => _photo = file),
                telephoneController: _telephoneController,
                nomController: _nomController,
                adresseController: _adresseController,
                latitude: _latitude,
                longitude: _longitude,
                onLocationChanged: (lat, lng) => setState(() {
                  _latitude = lat;
                  _longitude = lng;
                }),
                categorie: _categorie,
                onCategorieChanged: (v) => setState(() => _categorie = v),
                communeId: _communeId,
                onCommuneChanged: (v) => setState(() => _communeId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pinController,
                decoration: const InputDecoration(labelText: 'Choisissez un code PIN (4-6 chiffres)'),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                validator: (v) => (v == null || v.length < 4) ? 'PIN invalide' : null,
              ),
              TextFormField(
                controller: _pinConfirmController,
                decoration: const InputDecoration(labelText: 'Confirmez le code PIN'),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                validator: (v) =>
                    (v != _pinController.text) ? 'Les deux codes PIN ne correspondent pas' : null,
              ),
              ErrorText(_error),
              const SizedBox(height: 16),
              LoadingButton(loading: _loading, onPressed: _submit, label: "S'inscrire"),
            ],
          ),
        ),
      ),
    );
  }
}
