import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/loading_button.dart';

final _zonesForCreateAgentProvider =
    FutureProvider.autoDispose((ref) => ref.watch(adminApiProvider).listZones());

/// Création d'un compte agent — pas d'auto-inscription (specs §3.3), seul
/// l'admin en crée.
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
  String? _zoneId;
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
            zoneId: _zoneId,
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
    final zonesAsync = ref.watch(_zonesForCreateAgentProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.newAgentLabel),
        actions: const [LanguageSwitcherButton()],
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
                validator: (v) => (v == null || v.isEmpty) ? l10n.nomRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(labelText: l10n.emailLabel),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v == null || !v.contains('@')) ? l10n.emailInvalid : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: l10n.passwordLabel),
                obscureText: true,
                validator: (v) => (v == null || v.length < 8) ? l10n.passwordRequired : null,
              ),
              const SizedBox(height: 12),
              zonesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text(l10n.commonError(error.toString())),
                data: (zones) => DropdownButtonFormField<String?>(
                  initialValue: _zoneId,
                  decoration: InputDecoration(labelText: l10n.zoneLabel),
                  items: [
                    DropdownMenuItem(value: null, child: Text(l10n.noZoneLabel)),
                    for (final zone in zones)
                      DropdownMenuItem(value: zone.id, child: Text(zone.nom)),
                  ],
                  onChanged: (v) => setState(() => _zoneId = v),
                ),
              ),
              ErrorText(_error),
              const SizedBox(height: 16),
              LoadingButton(loading: _loading, onPressed: _submit, label: l10n.saveLabel),
            ],
          ),
        ),
      ),
    );
  }
}
