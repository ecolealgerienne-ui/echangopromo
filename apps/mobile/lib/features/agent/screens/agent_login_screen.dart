import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/auth_session.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/loading_button.dart';

/// Authentification email + mot de passe — compte créé exclusivement par
/// l'admin, pas d'auto-inscription agent (specs §3.3).
class AgentLoginScreen extends ConsumerStatefulWidget {
  const AgentLoginScreen({super.key});

  @override
  ConsumerState<AgentLoginScreen> createState() => _AgentLoginScreenState();
}

class _AgentLoginScreenState extends ConsumerState<AgentLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
      final api = ref.read(agentApiProvider);
      final token = await api.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await ref.read(authControllerProvider.notifier).loginThenResolveId(
            role: AppRole.agent,
            token: token,
            fetchId: () async => (await api.me()).id,
          );
      if (mounted) context.go('/agent/dashboard');
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(
            error,
            fallback: l10n.loginFailed,
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
        title: Text(l10n.agentSpaceTitle),
        actions: const [LanguageSwitcherButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
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
                validator: (v) => (v == null || v.isEmpty) ? l10n.passwordRequired : null,
              ),
              ErrorText(_error),
              const SizedBox(height: 16),
              LoadingButton(loading: _loading, onPressed: _submit, label: l10n.loginLabel),
            ],
          ),
        ),
      ),
    );
  }
}
