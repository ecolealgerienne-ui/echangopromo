import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../../domain/models/promo.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/loading_button.dart';
import '../../shared/widgets/multi_photo_picker_field.dart';
import '../../shared/widgets/promo_form_fields.dart';
import '../../../providers/core_providers.dart';

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
  List<PhotoSlotItem> _photoItems = [];
  bool _loading = false;
  String? _error;

  bool get _isEditing => widget.existingPromo != null;

  @override
  void initState() {
    super.initState();
    _categorie = widget.existingPromo?.categorie;
    // `photoKeys` n'est renseigné que par `GET /promo/me/all` (voir
    // `Promo.photoKeys`) — c'est bien la source de `MyPromosScreen`, qui
    // ouvre cet écran en édition. Les clés existantes sont réutilisées
    // telles quelles tant que l'utilisateur ne les retire pas, sans
    // réupload (voir `_submit`).
    final existing = widget.existingPromo;
    final keys = existing?.photoKeys;
    if (existing != null && keys != null) {
      _photoItems = [
        for (var i = 0; i < keys.length && i < existing.photoUrls.length; i++)
          ExistingPhotoItem(keys[i], existing.photoUrls[i]),
      ];
    }
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

  Future<void> _submit({required bool asDraft}) async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    if (_photoItems.isEmpty) {
      setState(() => _error = l10n.photoRequired);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(promoApiProvider);
      final storageApi = ref.read(storageApiProvider);
      final photoKeys = <String>[];
      for (final item in _photoItems) {
        switch (item) {
          case ExistingPhotoItem(:final key):
            photoKeys.add(key);
          case NewPhotoItem(:final file):
            photoKeys.add(await storageApi.uploadPhoto(file, purpose: 'promo'));
        }
      }

      if (_isEditing) {
        await api.update(
          widget.existingPromo!.id,
          description: _descriptionController.text.trim(),
          prixAvant: double.parse(_prixAvantController.text.trim()),
          prixApres: double.parse(_prixApresController.text.trim()),
          categorie: _categorie!,
          photoKeys: photoKeys,
        );
      } else {
        await api.create(
          description: _descriptionController.text.trim(),
          prixAvant: double.parse(_prixAvantController.text.trim()),
          prixApres: double.parse(_prixApresController.text.trim()),
          categorie: _categorie!,
          photoKeys: photoKeys,
          dateFin: asDraft ? null : DateTime.now().add(Duration(days: _dureeJours)),
          asDraft: asDraft,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(
            error,
            fallback: l10n.operationFailed,
            locale: Localizations.localeOf(context),
          ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
      appBar: AppBar(
        title: Text(_isEditing ? l10n.editPromoTitle : l10n.newPromoTitle),
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
                descriptionController: _descriptionController,
                prixAvantController: _prixAvantController,
                prixApresController: _prixApresController,
                prixApresValidator: _validatePrixApres,
                categorie: _categorie,
                onCategorieChanged: (v) => setState(() => _categorie = v),
                dureeJours: _isEditing ? null : _dureeJours,
                maxDureeJours: _maxDureeJours,
                onDureeJoursChanged: (v) => setState(() => _dureeJours = v ?? _defaultDureeJours),
              ),
              ErrorText(_error),
              const SizedBox(height: 16),
              if (_isEditing)
                LoadingButton(
                  loading: _loading,
                  onPressed: () => _submit(asDraft: false),
                  label: l10n.saveLabel,
                )
              else ...[
                LoadingButton(
                  loading: _loading,
                  onPressed: () => _submit(asDraft: false),
                  label: l10n.publishLabel,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _loading ? null : () => _submit(asDraft: true),
                  child: Text(l10n.saveDraftLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
