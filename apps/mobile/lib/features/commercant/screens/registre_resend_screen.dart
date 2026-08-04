import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/form_section.dart';
import '../../shared/widgets/app_settings_actions.dart';
import '../../shared/widgets/loading_button.dart';
import '../../shared/widgets/photo_picker_field.dart';

/// Renvoi du registre après un rejet admin — sans cet écran, un commerçant
/// auto-inscrit rejeté restait bloqué indéfiniment, sans recours dans l'app
/// (audit fonctionnel 2026-07-11), alors que le blocage de publication est
/// désormais définitif tant que le registre n'est pas validé (voir
/// `CommercantService.assertRegistreValidated`).
class RegistreResendScreen extends ConsumerStatefulWidget {
  const RegistreResendScreen({super.key});

  @override
  ConsumerState<RegistreResendScreen> createState() =>
      _RegistreResendScreenState();
}

class _RegistreResendScreenState extends ConsumerState<RegistreResendScreen> {
  File? _photo;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (_photo == null) {
      setState(() => _error = l10n.registrePhotoRequired);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final storage = ref.read(storageApiProvider);
      final registreKey =
          await storage.uploadPhoto(_photo!, purpose: 'registre');
      await ref
          .read(commercantApiProvider)
          .requestRegistreVerification(registreKey);
      if (mounted) context.pop(true);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.registreResendTitle),
        actions: const [AppSettingsActions()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          FormSection(
            title: l10n.registrePhotoLabel,
            subtitle: l10n.registreResendHelperText,
            icon: Icons.description_outlined,
            children: [
              PhotoPickerField(
                file: _photo,
                onChanged: (file) => setState(() => _photo = file),
              ),
            ],
          ),
          ErrorText(_error),
        ],
      ),
      bottomNavigationBar: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 3,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: LoadingButton(
              loading: _loading,
              onPressed: _submit,
              label: l10n.registreResendSubmit,
            ),
          ),
        ),
      ),
    );
  }
}
