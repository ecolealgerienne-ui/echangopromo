import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/auth_session.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';
import '../../shared/validators/pin_validator.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';
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
  bool _isAdminMode = false;
  String? _error;

  @override
  void dispose() {
    _telephoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  /// Point d'entrée admin volontairement caché plutôt qu'une entrée de menu
  /// (un seul compte admin en V0, CLAUDE.md dette connue) : saisir un email
  /// au lieu d'un numéro de téléphone bascule ce même écran vers
  /// l'authentification admin (email + mot de passe) sans rien changer à
  /// l'apparence du champ "téléphone" ni du reste de l'écran commerçant.
  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isAdminMode) {
        final api = ref.read(adminApiProvider);
        final token = await api.login(
          email: _telephoneController.text.trim(),
          password: _pinController.text,
        );
        await ref.read(authControllerProvider.notifier).loginThenResolveId(
              role: AppRole.admin,
              token: token,
              fetchId: () async => (await api.me()).id,
            );
        if (mounted) context.go('/admin/dashboard');
      } else {
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
      }
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

  /// Active un compte créé par un agent : pas d'OTP, le commerçant définit
  /// directement son PIN pour le numéro que l'agent a enregistré (specs §3.2/§3.3).
  Future<void> _claim(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final telephoneController = TextEditingController();
    final pinController = TextEditingController();
    final pinConfirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.setMyPinTitle),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: telephoneController,
                decoration: InputDecoration(labelText: l10n.telephoneLabel, hintText: l10n.telephoneHint),
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.isEmpty) ? l10n.telephoneRequired : null,
              ),
              TextFormField(
                controller: pinController,
                decoration: InputDecoration(labelText: l10n.newPinLabel),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                validator: validatePin(context),
              ),
              TextFormField(
                controller: pinConfirmController,
                decoration: InputDecoration(labelText: l10n.confirmPinLabel),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                validator: (v) => (v != pinController.text) ? l10n.pinMismatch : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                (telephoneController.text.trim(), pinController.text.trim()),
              );
            },
            child: Text(l10n.commonConfirm),
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
          SnackBar(
            content: Text(extractApiErrorMessage(
              error,
              fallback: l10n.activationFailed,
              locale: Localizations.localeOf(context),
            )),
          ),
        );
      }
    }
  }

  void _showForgotPinInfo(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.forgotPinTitle),
        content: Text(l10n.forgotPinBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonUnderstood)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.commercantSpaceTitle),
        actions: const [LanguageSwitcherButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _telephoneController,
                decoration: InputDecoration(labelText: l10n.telephoneLabel, hintText: l10n.telephoneHint),
                // `emailAddress` plutôt que `phone` : un clavier numérique
                // pur empêcherait de taper le "@" qui déclenche le bascule
                // admin ci-dessous ; les chiffres restent tapables
                // normalement sur ce clavier, un numéro de téléphone n'est
                // donc pas plus difficile à saisir.
                keyboardType: TextInputType.emailAddress,
                onChanged: (v) => setState(() => _isAdminMode = v.contains('@')),
                validator: (v) => (v == null || v.isEmpty) ? l10n.telephoneRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pinController,
                decoration: InputDecoration(labelText: _isAdminMode ? l10n.passwordLabel : l10n.pinLabel),
                keyboardType: _isAdminMode ? TextInputType.visiblePassword : TextInputType.number,
                obscureText: true,
                maxLength: _isAdminMode ? null : 6,
                validator: _isAdminMode
                    ? (v) => (v == null || v.length < 8) ? l10n.passwordRequired : null
                    : validatePin(context),
              ),
              ErrorText(_error),
              const SizedBox(height: 16),
              LoadingButton(loading: _loading, onPressed: _submit, label: l10n.loginLabel),
              // Liens spécifiques au parcours commerçant — sans objet une
              // fois basculé en mode admin, et inutilement déroutants.
              if (!_isAdminMode) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.push('/commercant/register'),
                  child: Text(l10n.notRegisteredYet),
                ),
                TextButton(
                  onPressed: () => _showForgotPinInfo(context),
                  child: Text(l10n.forgotPin),
                ),
                TextButton(
                  onPressed: () => _claim(context),
                  child: Text(l10n.claimAccount),
                ),
              ],
              // TEMPORAIRE — accès à l'écran de test de changement de
              // profil, à supprimer avant l'ouverture publique (même écran
              // que /dev/profiles, inaccessible autrement dans l'app).
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => context.push('/dev/profiles'),
                child: const Text('[TEST] Changer de profil'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
