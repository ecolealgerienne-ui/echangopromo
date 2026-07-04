import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../../domain/models/promo.dart';
import '../../shared/widgets/category_dropdown.dart';
import '../../shared/widgets/photo_picker_field.dart';
import '../../../providers/core_providers.dart';

const _descriptionMaxLength = 140;
const _defaultDureeJours = 5;
const _maxDureeJours = 7;

final _promoFormMeProvider = FutureProvider.autoDispose((ref) => ref.watch(commercantApiProvider).me());

/// Création (brouillon ou publication immédiate) ou édition d'une promo par
/// le commerçant lui-même (specs §3.2). Durée de validité choisie entre 1 et
/// `_maxDureeJours` jours à la publication — non applicable en édition, où
/// seul le contenu change (le cycle de vie se gère depuis `my_promos_screen`).
class PromoFormScreen extends ConsumerStatefulWidget {
  const PromoFormScreen({super.key, this.existingPromo});

  /// Non nul en mode édition — l'écran adapte alors son formulaire et son
  /// bouton unique "Enregistrer" (pas de choix brouillon/durée).
  final Promo? existingPromo;

  @override
  ConsumerState<PromoFormScreen> createState() => _PromoFormScreenState();
}

class _PromoFormScreenState extends ConsumerState<PromoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _descriptionController = TextEditingController(text: widget.existingPromo?.description);
  late final _prixAvantController =
      TextEditingController(text: widget.existingPromo?.prixAvant.toString());
  late final _prixApresController =
      TextEditingController(text: widget.existingPromo?.prixApres.toString());
  Categorie? _categorie;
  int _dureeJours = _defaultDureeJours;
  File? _photo;
  bool _loading = false;
  String? _error;

  bool get _isEditing => widget.existingPromo != null;

  @override
  void initState() {
    super.initState();
    _categorie = widget.existingPromo?.categorie;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _prixAvantController.dispose();
    _prixApresController.dispose();
    super.dispose();
  }

  String? _validatePrixApres(String? v) {
    final prixApres = double.tryParse(v ?? '');
    if (prixApres == null) return 'Invalide';
    final prixAvant = double.tryParse(_prixAvantController.text);
    if (prixAvant != null && prixApres >= prixAvant) {
      return 'Doit être inférieur au prix avant';
    }
    return null;
  }

  Future<void> _submit({required bool asDraft}) async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isEditing && _photo == null) {
      setState(() => _error = 'Une photo est requise.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(promoApiProvider);
      String? photoKey;
      if (_photo != null) {
        photoKey = await ref.read(storageApiProvider).uploadPhoto(_photo!, purpose: 'promo');
      }

      if (_isEditing) {
        await api.update(
          widget.existingPromo!.id,
          description: _descriptionController.text.trim(),
          prixAvant: double.parse(_prixAvantController.text.trim()),
          prixApres: double.parse(_prixApresController.text.trim()),
          categorie: _categorie!,
          photoKey: photoKey,
        );
      } else {
        await api.create(
          description: _descriptionController.text.trim(),
          prixAvant: double.parse(_prixAvantController.text.trim()),
          prixApres: double.parse(_prixApresController.text.trim()),
          categorie: _categorie!,
          photoKey: photoKey!,
          dateFin: asDraft ? null : DateTime.now().add(Duration(days: _dureeJours)),
          asDraft: asDraft,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(error, fallback: 'Opération impossible.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pré-remplit la catégorie avec celle du commerçant (modifiable ensuite),
    // une seule fois quand le profil est chargé — seulement à la création.
    if (!_isEditing) {
      ref.listen(_promoFormMeProvider, (previous, next) {
        if (_categorie == null) {
          next.whenData((me) => setState(() => _categorie = me.categorie));
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Modifier la promo' : 'Nouvelle promo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              PhotoPickerField(file: _photo, onChanged: (file) => setState(() => _photo = file)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
                maxLength: _descriptionMaxLength,
                validator: (v) => (v == null || v.isEmpty) ? 'Description requise' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _prixAvantController,
                      decoration: const InputDecoration(labelText: 'Prix avant (DA)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => (double.tryParse(v ?? '') == null) ? 'Invalide' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _prixApresController,
                      decoration: const InputDecoration(labelText: 'Prix après (DA)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: _validatePrixApres,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CategoryDropdown(value: _categorie, onChanged: (v) => setState(() => _categorie = v)),
              if (!_isEditing) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _dureeJours,
                  decoration: const InputDecoration(labelText: 'Durée de validité'),
                  items: [
                    for (var jours = 1; jours <= _maxDureeJours; jours++)
                      DropdownMenuItem(value: jours, child: Text('$jours jour${jours > 1 ? 's' : ''}')),
                  ],
                  onChanged: (v) => setState(() => _dureeJours = v ?? _defaultDureeJours),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              if (_isEditing)
                FilledButton(
                  onPressed: _loading ? null : () => _submit(asDraft: false),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enregistrer'),
                )
              else ...[
                FilledButton(
                  onPressed: _loading ? null : () => _submit(asDraft: false),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Publier'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _loading ? null : () => _submit(asDraft: true),
                  child: const Text('Enregistrer en brouillon'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
