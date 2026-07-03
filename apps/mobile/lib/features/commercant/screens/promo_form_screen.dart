import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../shared/widgets/category_dropdown.dart';
import '../../shared/widgets/photo_picker_field.dart';
import '../../../providers/core_providers.dart';

/// Création d'une promo par le commerçant lui-même. Durée par défaut de 5
/// jours appliquée côté backend si aucune date de fin n'est fournie (specs
/// §3.2 — point ouvert §7.6 sur l'ajustabilité, non exposé ici en V0).
class PromoFormScreen extends ConsumerStatefulWidget {
  const PromoFormScreen({super.key});

  @override
  ConsumerState<PromoFormScreen> createState() => _PromoFormScreenState();
}

class _PromoFormScreenState extends ConsumerState<PromoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _produitController = TextEditingController();
  final _prixAvantController = TextEditingController();
  final _prixApresController = TextEditingController();
  Categorie? _categorie;
  File? _photo;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _produitController.dispose();
    _prixAvantController.dispose();
    _prixApresController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_photo == null) {
      setState(() => _error = 'Une photo est requise.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final photoKey = await ref.read(storageApiProvider).uploadPhoto(_photo!);
      await ref.read(promoApiProvider).create(
            produit: _produitController.text.trim(),
            prixAvant: double.parse(_prixAvantController.text.trim()),
            prixApres: double.parse(_prixApresController.text.trim()),
            categorie: _categorie!,
            photoKey: photoKey,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(error, fallback: 'Publication impossible.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle promo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              PhotoPickerField(file: _photo, onChanged: (file) => setState(() => _photo = file)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _produitController,
                decoration: const InputDecoration(labelText: 'Produit'),
                validator: (v) => (v == null || v.isEmpty) ? 'Produit requis' : null,
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
                      validator: (v) => (double.tryParse(v ?? '') == null) ? 'Invalide' : null,
                    ),
                  ),
                ],
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
                    : const Text('Publier'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
