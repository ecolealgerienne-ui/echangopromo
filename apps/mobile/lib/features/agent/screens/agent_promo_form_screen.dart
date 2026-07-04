import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/loading_button.dart';
import '../../shared/widgets/promo_form_fields.dart';
import '../../../providers/core_providers.dart';

const _defaultDureeJours = 5;
const _maxDureeJours = 7;

/// Création/mise à jour d'une promo par l'agent. Photo obligatoirement
/// prise dans l'app (pas de galerie), avec horodatage côté serveur — preuve
/// minimale de passage, sans géolocalisation (specs §3.3/§5.5).
class AgentPromoFormScreen extends ConsumerStatefulWidget {
  const AgentPromoFormScreen({super.key, required this.commercantId, this.defaultCategorie});

  final String commercantId;

  /// Catégorie du commerçant, passée par l'écran appelant — pré-remplit le
  /// champ (modifiable ensuite) plutôt que de la redemander à chaque promo.
  final Categorie? defaultCategorie;

  @override
  ConsumerState<AgentPromoFormScreen> createState() => _AgentPromoFormScreenState();
}

class _AgentPromoFormScreenState extends ConsumerState<AgentPromoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _prixAvantController = TextEditingController();
  final _prixApresController = TextEditingController();
  Categorie? _categorie;
  int _dureeJours = _defaultDureeJours;
  File? _photo;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _categorie = widget.defaultCategorie;
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_photo == null) {
      setState(() => _error = 'La photo doit être prise avec l\'appareil photo.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final photoKey = await ref.read(storageApiProvider).uploadPhoto(_photo!);
      await ref.read(promoApiProvider).createForCommercant(
            widget.commercantId,
            description: _descriptionController.text.trim(),
            prixAvant: double.parse(_prixAvantController.text.trim()),
            prixApres: double.parse(_prixApresController.text.trim()),
            categorie: _categorie!,
            photoKey: photoKey,
            dateFin: DateTime.now().add(Duration(days: _dureeJours)),
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
              PromoFormFields(
                photo: _photo,
                onPhotoChanged: (file) => setState(() => _photo = file),
                cameraOnly: true,
                descriptionController: _descriptionController,
                prixAvantController: _prixAvantController,
                prixApresController: _prixApresController,
                prixApresValidator: _validatePrixApres,
                categorie: _categorie,
                onCategorieChanged: (v) => setState(() => _categorie = v),
                dureeJours: _dureeJours,
                maxDureeJours: _maxDureeJours,
                onDureeJoursChanged: (v) => setState(() => _dureeJours = v ?? _defaultDureeJours),
              ),
              ErrorText(_error),
              const SizedBox(height: 16),
              LoadingButton(loading: _loading, onPressed: _submit, label: 'Publier'),
            ],
          ),
        ),
      ),
    );
  }
}
