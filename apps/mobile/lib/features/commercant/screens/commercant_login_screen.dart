import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/auth_session.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/loading_button.dart';

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

  /// Active un compte créé par un agent : pas d'OTP, le commerçant définit
  /// directement son PIN pour le numéro que l'agent a enregistré (specs §3.2/§3.3).
  Future<void> _claim(BuildContext context) async {
    final telephoneController = TextEditingController();
    final pinController = TextEditingController();
    final pinConfirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Définir mon PIN'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: telephoneController,
                decoration: const InputDecoration(labelText: 'Téléphone', hintText: '+213...'),
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.isEmpty) ? 'Téléphone requis' : null,
              ),
              TextFormField(
                controller: pinController,
                decoration: const InputDecoration(labelText: 'Nouveau code PIN'),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                validator: (v) => (v == null || v.length < 4) ? 'PIN invalide' : null,
              ),
              TextFormField(
                controller: pinConfirmController,
                decoration: const InputDecoration(labelText: 'Confirmez le code PIN'),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                validator: (v) =>
                    (v != pinController.text) ? 'Les deux codes PIN ne correspondent pas' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                (telephoneController.text.trim(), pinController.text.trim()),
              );
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );

    if (result == null || result.$1.isEmpty || result.$2.isEmpty || !context.mounted) return;

    try {
      final api = ref.read(commercantApiProvider);
      final token = await api.claim(telephone: result.$1, pin: result.$2);
      await ref.read(authControllerProvider.notifier).loginThenResolveId(
            role: AppRole.commercant,
            token: token,
            fetchId: () async => (await api.me()).id,
          );
      if (context.mounted) context.go('/commercant/dashboard');
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractApiErrorMessage(error, fallback: 'Activation impossible.'))),
        );
      }
    }
  }

  void _showForgotPinInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PIN oublié'),
        content: const Text(
          "Il n'y a pas de réinitialisation automatique. Contactez l'administrateur : "
          "il réinitialise votre PIN, puis vous en définissez un nouveau via "
          "« Compte créé par un agent ? Définir mon PIN ».",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Compris')),
        ],
      ),
    );
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
              ErrorText(_error),
              const SizedBox(height: 16),
              LoadingButton(loading: _loading, onPressed: _submit, label: 'Se connecter'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.push('/commercant/register'),
                child: const Text('Pas encore inscrit ? Créer un compte'),
              ),
              TextButton(
                onPressed: () => _showForgotPinInfo(context),
                child: const Text('PIN oublié ?'),
              ),
              TextButton(
                onPressed: () => _claim(context),
                child: const Text('Compte créé par un agent ? Définir mon PIN'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
