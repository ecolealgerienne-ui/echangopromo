import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/loading_button.dart';
import '../../shared/widgets/multi_photo_picker_field.dart';
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
  List<PhotoSlotItem> _photoItems = [];
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
    final l10n = AppLocalizations.of(context)!;
    final prixApres = double.tryParse(v ?? '');
    if (prixApres == null) return l10n.commonInvalid;
    final prixAvant = double.tryParse(_prixAvantController.text);
    if (prixAvant != null && prixApres >= prixAvant) {
      return l10n.prixApresMustBeLower;
    }
    return null;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    if (_photoItems.isEmpty) {
      setState(() => _error = l10n.photoRequiredCamera);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final storageApi = ref.read(storageApiProvider);
      // Upload en parallèle plutôt qu'en série, ordre préservé par
      // `Future.wait` (audit performance 2026-07-12).
      final photoKeys = await Future.wait(_photoItems.map((item) async {
        return switch (item) {
          ExistingPhotoItem(:final key) => key,
          NewPhotoItem(:final file) => await storageApi.uploadPhoto(file),
        };
      }));
      await ref.read(promoApiProvider).createForCommercant(
            widget.commercantId,
            description: _descriptionController.text.trim(),
            prixAvant: double.parse(_prixAvantController.text.trim()),
            prixApres: double.parse(_prixApresController.text.trim()),
            categorie: _categorie!,
            photoKeys: photoKeys,
            dateFin: DateTime.now().add(Duration(days: _dureeJours)),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(
            error,
            fallback: l10n.publishFailed,
            locale: Localizations.localeOf(context),
          ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.newPromoTitle),
        actions: const [LanguageSwitcherButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              PromoFormFields(
                photoItems: _photoItems,
                onPhotoItemsChanged: (items) => setState(() => _photoItems = items),
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
              LoadingButton(loading: _loading, onPressed: _submit, label: l10n.publishLabel),
            ],
          ),
        ),
      ),
    );
  }
}
