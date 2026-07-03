import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/auth_session.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';

/// Authentification téléphone + code PIN, sans SMS (specs §3.2).
class CommercantLoginScreen extends ConsumerStatefulWidget {
  const CommercantLoginScreen({super.key});

  @override
  ConsumerState<CommercantLoginScreen> createState() => _CommercantLoginScreenState();
}

class _CommercantLoginScreenState extends ConsumerState<CommercantLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _telephoneController = TextEditingController();
  final _pinController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _telephoneController.dispose();
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
      final token = await ref.read(commercantApiProvider).login(
            telephone: _telephoneController.text.trim(),
            pin: _pinController.text.trim(),
          );
      await ref.read(authControllerProvider.notifier).loginThenResolveId(
            role: AppRole.commercant,
            token: token,
            fetchId: () async => (await ref.read(commercantApiProvider).me()).id,
          );
      if (mounted) context.go('/commercant/dashboard');
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(error, fallback: 'Connexion impossible.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// L'agent initie la revendication depuis son propre appareil (envoi de
  /// l'OTP) ; le commerçant doit ensuite, de son côté, saisir son numéro
  /// pour atteindre l'écran de confirmation (specs §3.2/§3.3).
  Future<void> _confirmClaim(BuildContext context) async {
    final controller = TextEditingController();
    final telephone = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer la revendication'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Téléphone', hintText: '+213...'),
          keyboardType: TextInputType.phone,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );

    if (telephone != null && telephone.isNotEmpty && context.mounted) {
      context.push('/commercant/otp', extra: {'telephone': telephone, 'purpose': 'revendication'});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Espace commerçant')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _telephoneController,
                decoration: const InputDecoration(labelText: 'Téléphone', hintText: '+213...'),
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.isEmpty) ? 'Téléphone requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pinController,
                decoration: const InputDecoration(labelText: 'Code PIN'),
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
                    : const Text('Se connecter'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.push('/commercant/register'),
                child: const Text('Pas encore inscrit ? Créer un compte'),
              ),
              TextButton(
                onPressed: () => context.push('/commercant/forgot-pin'),
                child: const Text('PIN oublié ?'),
              ),
              TextButton(
                onPressed: () => _confirmClaim(context),
                child: const Text('Compte créé par un agent ? Confirmer la revendication'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
