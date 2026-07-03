import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';

/// Étape commune à l'auto-inscription et à la revendication d'un compte
/// créé par l'agent : OTP SMS puis définition du code PIN (specs §3.2).
class OtpConfirmScreen extends ConsumerStatefulWidget {
  const OtpConfirmScreen({super.key, required this.telephone, required this.purpose});

  final String telephone;

  /// 'inscription' ou 'revendication'.
  final String purpose;

  @override
  ConsumerState<OtpConfirmScreen> createState() => _OtpConfirmScreenState();
}

class _OtpConfirmScreenState extends ConsumerState<OtpConfirmScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _pinController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(commercantApiProvider);
      final token = widget.purpose == 'inscription'
          ? await api.confirmInscription(
              telephone: widget.telephone,
              code: _codeController.text.trim(),
              pin: _pinController.text.trim(),
            )
          : await api.confirmRevendication(
              telephone: widget.telephone,
              code: _codeController.text.trim(),
              pin: _pinController.text.trim(),
            );

      await ref.read(authControllerProvider.notifier).loginThenResolveId(
            role: AppRole.commercant,
            token: token,
            fetchId: () async => (await api.me()).id,
          );
      if (mounted) context.go('/commercant/dashboard');
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(error, fallback: 'Code invalide.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vérification du téléphone')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text('Un code a été envoyé au ${widget.telephone}.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'Code reçu par SMS'),
                keyboardType: TextInputType.number,
                maxLength: 6,
                validator: (v) => (v == null || v.length != 6) ? 'Code à 6 chiffres' : null,
              ),
              TextFormField(
                controller: _pinController,
                decoration: const InputDecoration(labelText: 'Choisissez un code PIN (4-6 chiffres)'),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                validator: (v) => (v == null || v.length < 4) ? 'PIN invalide' : null,
              ),
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
                    : const Text('Valider'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
