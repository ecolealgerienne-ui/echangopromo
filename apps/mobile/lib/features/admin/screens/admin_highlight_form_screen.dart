import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/highlight.dart';
import '../../../domain/models/moderation_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/form_section.dart';
import '../../shared/widgets/loading_button.dart';
import '../../shared/widgets/photo_picker_field.dart';
import '../providers/highlight_providers.dart';

/// Composition d'une diapositive du bandeau d'accueil.
///
/// Deux choses indépendantes s'y règlent, d'où deux sections distinctes :
/// **ce qui s'ouvre au clic** (une promo, ou rien) et **ce qui s'affiche**
/// (l'image importée prend le pas sur la photo de la promo, sans jamais
/// toucher à la fiche promo elle-même).
class AdminHighlightFormScreen extends ConsumerStatefulWidget {
  const AdminHighlightFormScreen({super.key, this.existing});

  /// `null` en création.
  final Highlight? existing;

  @override
  ConsumerState<AdminHighlightFormScreen> createState() =>
      _AdminHighlightFormScreenState();
}

class _AdminHighlightFormScreenState
    extends ConsumerState<AdminHighlightFormScreen> {
  late final TextEditingController _titreController =
      TextEditingController(text: widget.existing?.titre ?? '');
  late final TextEditingController _sousTitreController =
      TextEditingController(text: widget.existing?.sousTitre ?? '');

  late String? _promoId = widget.existing?.promoId;
  late String? _promoLabel = widget.existing?.promoDescription;
  late String? _promoShop = widget.existing?.commercantNom;
  late String? _promoPhotoUrl = widget.existing?.promoPhotoUrl;

  /// Image déjà en ligne (édition) — remplacée par [_imageFile] dès que
  /// l'admin en choisit une nouvelle, effacée quand il la retire.
  late String? _imageKey = widget.existing?.imageKey;
  late String? _imageUrl = widget.existing?.imageUrl;
  File? _imageFile;

  late bool _active = widget.existing?.active ?? true;

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _titreController.dispose();
    _sousTitreController.dispose();
    super.dispose();
  }

  Future<void> _pickPromo() async {
    final selected = await showModalBottomSheet<ModerationItem>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _PromoPickerSheet(),
    );
    if (selected == null) return;
    setState(() {
      _promoId = selected.id;
      _promoLabel = selected.description;
      _promoShop = selected.commercantNom;
      _promoPhotoUrl = selected.thumbnailUrl ?? selected.photoUrl;
    });
  }

  void _clearPromo() {
    setState(() {
      _promoId = null;
      _promoLabel = null;
      _promoShop = null;
      _promoPhotoUrl = null;
    });
  }

  void _clearImage() {
    setState(() {
      _imageFile = null;
      _imageKey = null;
      _imageUrl = null;
    });
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    // Une diapositive sans promo ni image n'a rien à afficher — le backend
    // le refuse aussi (`HIGHLIGHT_EMPTY_CONTENT`), mais l'admin n'a pas à
    // faire un aller-retour réseau pour l'apprendre.
    if (_promoId == null && _imageFile == null && _imageKey == null) {
      setState(() => _error = l10n.highlightContentRequired);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final api = ref.read(highlightApiProvider);
      String? uploadedKey;
      if (_imageFile != null) {
        uploadedKey = await ref
            .read(storageApiProvider)
            .uploadPhoto(_imageFile!, purpose: 'highlight');
      }

      if (_isEditing) {
        // L'écran porte l'état complet voulu : on l'envoie tel quel plutôt
        // que de deviner quels champs ont bougé — d'où les drapeaux `clear*`
        // pour distinguer « effacer » de « ne pas toucher ».
        await api.update(
          widget.existing!.id,
          promoId: _promoId,
          clearPromo: _promoId == null,
          imageKey: uploadedKey,
          clearImage: uploadedKey == null && _imageKey == null,
          titre: _titreController.text.trim(),
          sousTitre: _sousTitreController.text.trim(),
          active: _active,
        );
      } else {
        await api.create(
          promoId: _promoId,
          imageKey: uploadedKey,
          titre: _titreController.text.trim(),
          sousTitre: _sousTitreController.text.trim(),
          active: _active,
        );
      }

      ref.invalidate(adminHighlightsProvider);
      if (mounted) context.pop();
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(
            error,
            fallback: l10n.operationFailed,
            locale: Localizations.localeOf(context),
          ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title:
            Text(_isEditing ? l10n.highlightEditTitle : l10n.highlightNewTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          FormSection(
            title: l10n.highlightSectionPromo,
            subtitle: l10n.highlightSectionPromoHint,
            icon: Icons.local_offer_outlined,
            children: [
              if (_promoId == null)
                OutlinedButton.icon(
                  onPressed: _pickPromo,
                  icon: const Icon(Icons.search),
                  label: Text(l10n.highlightPickPromo),
                )
              else ...[
                _SelectedPromoCard(
                  label: _promoLabel,
                  shop: _promoShop,
                  photoUrl: _promoPhotoUrl,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _pickPromo,
                        child: Text(l10n.highlightChangePromo),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton(
                        onPressed: _clearPromo,
                        child: Text(l10n.highlightRemovePromo),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          FormSection(
            title: l10n.highlightSectionImage,
            subtitle: l10n.highlightSectionImageHint,
            icon: Icons.image_outlined,
            children: [
              PhotoPickerField(
                file: _imageFile,
                existingImageUrl: _imageUrl,
                onChanged: (file) => setState(() => _imageFile = file),
              ),
              if (_imageFile != null || _imageUrl != null)
                TextButton(
                  onPressed: _clearImage,
                  child: Text(l10n.highlightRemoveImage),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FormSection(
            title: l10n.highlightSectionTexts,
            subtitle: l10n.highlightSectionTextsHint,
            icon: Icons.title,
            children: [
              TextField(
                controller: _titreController,
                maxLength: 60,
                decoration: InputDecoration(
                  labelText: l10n.highlightTitreLabel,
                  hintText: _promoLabel,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sousTitreController,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: l10n.highlightSousTitreLabel,
                  hintText: _promoShop,
                  counterText: '',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FormSection(
            title: l10n.highlightSectionPublication,
            icon: Icons.visibility_outlined,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (value) => setState(() => _active = value),
                title:
                    Text(l10n.highlightActiveLabel, style: textTheme.bodyLarge),
                subtitle: Text(
                  l10n.highlightActiveHint,
                  style: textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          ErrorText(_error),
          const SizedBox(height: 20),
          LoadingButton(
              loading: _saving, onPressed: _submit, label: l10n.saveLabel),
        ],
      ),
    );
  }
}

class _SelectedPromoCard extends StatelessWidget {
  const _SelectedPromoCard(
      {required this.label, required this.shop, required this.photoUrl});

  final String? label;
  final String? shop;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: SizedBox(
            width: 56,
            height: 56,
            child: photoUrl == null
                ? Container(color: colorScheme.surfaceContainerHighest)
                : CachedNetworkImage(imageUrl: photoUrl!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null)
                Text(label!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall),
              if (shop != null)
                Text(
                  shop!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sélecteur de promo : la recherche admin existante (`GET /admin/promo`),
/// pas une liste complète — l'admin cherche une promo précise dont il
/// connaît le produit ou le commerce, faire défiler tout le catalogue
/// n'aurait aucun sens passé le pilote.
class _PromoPickerSheet extends ConsumerStatefulWidget {
  const _PromoPickerSheet();

  @override
  ConsumerState<_PromoPickerSheet> createState() => _PromoPickerSheetState();
}

class _PromoPickerSheetState extends ConsumerState<_PromoPickerSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _search = '';

  /// Future conservée en état plutôt que créée dans `build` : sans ça,
  /// chaque reconstruction (ouverture du clavier, changement de taille)
  /// relancerait la requête de recherche.
  late Future<List<ModerationItem>> _results = _fetch();

  Future<List<ModerationItem>> _fetch() =>
      ref.read(adminApiProvider).listAllPromos(search: _search);

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Même délai que la barre de recherche de l'accueil : frapper un nom de
    // commerce ne doit pas déclencher une requête par caractère.
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _search = value.trim();
        _results = _fetch();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(l10n.highlightSearchPromoTitle,
                          style: textTheme.titleMedium),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: _onChanged,
                  decoration: InputDecoration(
                    hintText: l10n.highlightSearchPromoHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<ModerationItem>>(
                  future: _results,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = snapshot.data ?? const <ModerationItem>[];
                    if (items.isEmpty) {
                      return Center(child: Text(l10n.noSearchResults(_search)));
                    }
                    return ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final photo = item.thumbnailUrl ?? item.photoUrl;
                        return ListTile(
                          leading: SizedBox(
                            width: 48,
                            height: 48,
                            child: photo == null
                                ? const Icon(Icons.image_outlined)
                                : ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(AppRadii.sm),
                                    child: CachedNetworkImage(
                                      imageUrl: photo,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                          ),
                          title: Text(item.description,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(item.commercantNom),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
