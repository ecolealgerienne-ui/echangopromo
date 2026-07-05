import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/widgets/commercant_fields_form.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/loading_button.dart';
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
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate() || _communeId == null) {
      setState(() => _error = _communeId == null ? l10n.communeRequired : null);
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
            title: Text(l10n.commercantCreatedTitle),
            content: Text(l10n.addFirstPromoQuestion),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.laterLabel)),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.yesLabel)),
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
      setState(() => _error = extractApiErrorMessage(
            error,
            fallback: l10n.createFailed,
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
        title: Text(l10n.newCommercantScreenTitle),
        actions: const [LanguageSwitcherButton()],
      ),
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
              ErrorText(_error),
              const SizedBox(height: 16),
              LoadingButton(loading: _loading, onPressed: _submit, label: l10n.createLabel),
            ],
          ),
        ),
      ),
    );
  }
}
