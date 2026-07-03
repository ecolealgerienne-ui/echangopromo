import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../providers/core_providers.dart';

/// Récupération de PIN oublié — repasse obligatoirement par un nouvel OTP
/// SMS (specs §3.2).
class ForgotPinScreen extends ConsumerStatefulWidget {
  const ForgotPinScreen({super.key});

  @override
  ConsumerState<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends ConsumerState<ForgotPinScreen> {
  final _telephoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPinController = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _telephoneController.dispose();
    _codeController.dispose();
    _newPinController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(commercantApiProvider).forgotPinRequest(_telephoneController.text.trim());
      setState(() {
        _otpSent = true;
        _info = 'Un code a été envoyé par SMS.';
      });
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(error, fallback: 'Numéro introuvable.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(commercantApiProvider).forgotPinConfirm(
            telephone: _telephoneController.text.trim(),
            code: _codeController.text.trim(),
            newPin: _newPinController.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('PIN modifié, connectez-vous.')));
        context.go('/commercant/login');
      }
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(error, fallback: 'Code invalide.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PIN oublié')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextFormField(
              controller: _telephoneController,
              enabled: !_otpSent,
              decoration: const InputDecoration(labelText: 'Téléphone', hintText: '+213...'),
              keyboardType: TextInputType.phone,
            ),
            if (_otpSent) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'Code reçu par SMS'),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              TextFormField(
                controller: _newPinController,
                decoration: const InputDecoration(labelText: 'Nouveau code PIN'),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
              ),
            ],
            if (_info != null) ...[
              const SizedBox(height: 8),
              Text(_info!, style: const TextStyle(color: Colors.green)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : (_otpSent ? _confirm : _requestOtp),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_otpSent ? 'Valider le nouveau PIN' : 'Recevoir le code par SMS'),
            ),
          ],
        ),
      ),
    );
  }
}
