import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../client/providers/commune_providers.dart';
import '../../shared/widgets/category_dropdown.dart';
import '../../shared/widgets/commune_cascade_field.dart';
import '../../shared/widgets/location_capture_field.dart';
import '../../shared/widgets/photo_picker_field.dart';
import '../../../providers/core_providers.dart';

/// Création assistée par l'agent (specs §3.2, voie 2) : numéro de
/// téléphone, nom, adresse, catégorie. Le commerçant active lui-même son
/// compte plus tard, sans OTP, en définissant son PIN depuis l'écran de
/// connexion commerçant.
class CreateCommercantScreen extends ConsumerStatefulWidget {
  const CreateCommercantScreen({super.key});

  @override
  ConsumerState<CreateCommercantScreen> createState() => _CreateCommercantScreenState();
}

class _CreateCommercantScreenState extends ConsumerState<CreateCommercantScreen> {
  final _formKey = GlobalKey<FormState>();
  final _telephoneController = TextEditingController();
  final _nomController = TextEditingController();
  final _adresseController = TextEditingController();
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
      String? photoKey;
      if (_photo != null) {
        photoKey = await ref.read(storageApiProvider).uploadPhoto(_photo!, purpose: 'commercant');
      }
      final commercant = await ref.read(agentApiProvider).createCommercant(
            telephone: _telephoneController.text.trim(),
            nom: _nomController.text.trim(),
            adresse: _adresseController.text.trim(),
            categorie: _categorie!,
            communeId: _communeId!,
            photoKey: photoKey,
            latitude: _latitude,
            longitude: _longitude,
          );
      if (mounted) {
        final addPromo = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Commerçant créé'),
            content: const Text('Ajouter la première promo maintenant ?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Plus tard')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Oui')),
            ],
          ),
        );

        if (!mounted) return;
        if (addPromo == true) {
          // `push` (pas `pushReplacement`) : on attend le résultat du
          // formulaire promo avant de dépiler cet écran, sinon le `Future`
          // de l'appel `context.push` initial se résoudrait immédiatement
          // sans attendre la création de la promo.
          await context.push<bool>(
            '/agent/promo/new/${commercant.id}',
            extra: commercant.categorie,
          );
          if (!mounted) return;
          Navigator.of(context).pop(true);
        } else {
          Navigator.of(context).pop(true);
        }
      }
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(error, fallback: 'Création impossible.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final communesAsync = ref.watch(communeListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau commerçant')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              PhotoPickerField(file: _photo, onChanged: (file) => setState(() => _photo = file)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telephoneController,
                decoration: const InputDecoration(labelText: 'Téléphone', hintText: '+213...'),
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.isEmpty) ? 'Téléphone requis' : null,
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              communesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('Erreur communes : $error'),
                data: (communes) => CommuneCascadeField(
                  communes: communes,
                  selectedCommuneId: _communeId,
                  onChanged: (v) => setState(() => _communeId = v),
                ),
              ),
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
                    : const Text('Créer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
