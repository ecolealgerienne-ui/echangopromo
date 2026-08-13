import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/app_settings_actions.dart';
import '../../shared/widgets/loading_button.dart';

/// Création d'un compte agent — pas d'auto-inscription (specs §3.3), seul
/// l'admin en crée.
///
/// ⚠️ **Plus aucun territoire à choisir depuis le 2026-08-13.** L'écran se
/// réduit à e-mail, mot de passe et nom : un agent créé ici a d'emblée les
/// mêmes droits d'écriture que tous les autres, sur tout le parc. Il n'existe
/// plus de compte agent « inoffensif » — c'était le sens d'une création sans
/// commune assignée.
class CreateAgentScreen extends ConsumerStatefulWidget {
  const CreateAgentScreen({super.key});

  @override
  ConsumerState<CreateAgentScreen> createState() => _CreateAgentScreenState();
}

class _CreateAgentScreenState extends ConsumerState<CreateAgentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nomController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nomController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(adminApiProvider).createAgent(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            nom: _nomController.text.trim(),
          );
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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.newAgentLabel),
        actions: const [AppSettingsActions()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nomController,
                decoration: InputDecoration(labelText: l10n.nomLabel),
                validator: (v) =>
                    (v == null || v.isEmpty) ? l10n.nomRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(labelText: l10n.emailLabel),
                keyboardType: TextInputType.emailAddress,
                validator: (v) =>
                    (v == null || !v.contains('@')) ? l10n.emailInvalid : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: l10n.passwordLabel),
                obscureText: true,
                validator: (v) =>
                    (v == null || v.length < 8) ? l10n.passwordRequired : null,
              ),
              const SizedBox(height: 12),
              ErrorText(_error),
              const SizedBox(height: 16),
              LoadingButton(
                  loading: _loading, onPressed: _submit, label: l10n.saveLabel),
            ],
          ),
        ),
      ),
    );
  }
}
