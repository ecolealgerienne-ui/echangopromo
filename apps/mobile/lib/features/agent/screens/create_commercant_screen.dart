import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/validators/pin_validator.dart';
import '../../shared/widgets/commercant_fields_form.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/app_settings_actions.dart';
import '../../shared/widgets/loading_button.dart';
import '../../../providers/core_providers.dart';

/// Création assistée par l'agent (specs §3.2, voie 2) : numéro de
/// téléphone, nom, adresse, catégorie. L'agent choisit aussi le PIN et le
/// communique en personne au commerçant (décision produit 2026-07-13,
/// remplace l'ancienne revendication publique par téléphone seul,
/// exploitable par un tiers connaissant juste le numéro).
class CreateCommercantScreen extends ConsumerStatefulWidget {
  const CreateCommercantScreen({super.key});

  @override
  ConsumerState<CreateCommercantScreen> createState() =>
      _CreateCommercantScreenState();
}

class _CreateCommercantScreenState
    extends ConsumerState<CreateCommercantScreen> {
  final _formKey = GlobalKey<FormState>();
  final _telephoneController = TextEditingController();
  final _nomController = TextEditingController();
  final _adresseController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  Categorie? _categorie;
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
    final l10n = AppLocalizations.of(context)!;
    // ⚠️ La position est **obligatoire ici**, alors qu'elle reste facultative à
    // l'auto-inscription. L'agent est physiquement dans le commerce : c'est la
    // seule capture juste par construction. Sans cette garde, chaque tournée
    // recréerait des fiches invisibles — 40 des 44 commerçants sans position
    // mesurés le 2026-08-12 venaient de cette route.
    //
    // Refusé côté serveur aussi (`CreateCommercantByAgentDto`) : cette
    // vérification-ci évite un aller-retour réseau pour rien, elle ne le
    // remplace pas — une garde uniquement client se contourne en appelant
    // l'API directement.
    if (!_formKey.currentState!.validate() ||
        _latitude == null ||
        _longitude == null) {
      setState(() => _error = l10n.positionRequired);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String? photoKey;
      if (_photo != null) {
        photoKey = await ref
            .read(storageApiProvider)
            .uploadPhoto(_photo!, purpose: 'commercant');
      }
      final commercant = await ref.read(agentApiProvider).createCommercant(
            telephone: _telephoneController.text.trim(),
            nom: _nomController.text.trim(),
            adresse: _adresseController.text.trim(),
            categorie: _categorie!,
            pin: _pinController.text.trim(),
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
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.laterLabel)),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.yesLabel)),
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
        actions: const [AppSettingsActions()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              CommercantFieldsForm(
                positionRequise: true,
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
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pinController,
                decoration: InputDecoration(labelText: l10n.choosePinLabel),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 12,
                validator: validatePin(context),
              ),
              TextFormField(
                controller: _pinConfirmController,
                decoration: InputDecoration(labelText: l10n.confirmPinLabel),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 12,
                validator: (v) =>
                    (v != _pinController.text) ? l10n.pinMismatch : null,
              ),
              ErrorText(_error),
              const SizedBox(height: 16),
              LoadingButton(
                  loading: _loading,
                  onPressed: _submit,
                  label: l10n.createLabel),
            ],
          ),
        ),
      ),
    );
  }
}
