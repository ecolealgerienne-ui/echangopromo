import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/auth_session.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';
import '../../shared/validators/pin_validator.dart';
import '../../shared/widgets/echango_wordmark.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/app_settings_actions.dart';
import '../../shared/widgets/loading_button.dart';

/// Authentification téléphone + code PIN, sans SMS (specs §3.2).
///
/// Pas d'`AppBar` : la marque tient le haut de l'écran, comme sur le splash.
/// Un commerçant arrive ici depuis l'app grand public, il doit voir
/// immédiatement qu'il change d'espace.
class CommercantLoginScreen extends ConsumerStatefulWidget {
  const CommercantLoginScreen({super.key});

  @override
  ConsumerState<CommercantLoginScreen> createState() =>
      _CommercantLoginScreenState();
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

  /// Point d'entrée **pro** volontairement caché plutôt qu'une entrée de menu
  /// (un seul compte admin en V0, CLAUDE.md dette connue) : saisir un email
  /// au lieu d'un numéro de téléphone bascule ce même écran vers
  /// l'authentification par email + mot de passe, sans rien changer à
  /// l'apparence du champ "téléphone" ni du reste de l'écran commerçant.
  ///
  /// ⚠️ **Admin ET agent passent par ici** — un agent, c'est un admin avec deux
  /// fonctionnalités en moins, pas un autre produit. Jusqu'au 2026-08-05, cette
  /// bascule n'essayait que `POST /admin/login`, dont le service ne lit que la
  /// table `admins` : un agent y recevait « Identifiants invalides », et
  /// `AgentLoginScreen` — qui existe, et que les bancs couvrent — n'était
  /// atteint par **rien** dans l'app (règle #31). Un agent de terrain ne
  /// pouvait tout simplement pas ouvrir son espace.
  ///
  /// L'admin est essayé d'abord, l'agent ensuite, et **uniquement** si le
  /// refus porte le code « identifiants invalides » : un compte bloqué, un
  /// serveur en panne ou un 429 doivent remonter tels quels, pas déclencher une
  /// seconde tentative qui masquerait la vraie cause.
  ///
  /// ⚠️ Coût assumé : une connexion d'agent consomme **deux** requêtes du seau
  /// strict (5/min/IP), contre une pour l'admin. C'est le prix d'une porte
  /// unique tant que le serveur n'expose pas un point d'entrée pro commun.
  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isAdminMode) {
        final email = _telephoneController.text.trim();
        final password = _pinController.text;
        String? token;
        var role = AppRole.admin;
        try {
          token = await ref.read(adminApiProvider).login(
                email: email,
                password: password,
              );
        } catch (error) {
          // ⚠️ `on ApiException catch` ne marcherait PAS : l'intercepteur de
          // `ApiClient` enveloppe l'`ApiException` dans une `DioException`.
          // C'est ce piège qui a fait échouer le premier essai de ce repli.
          //
          // Seul « identifiants invalides » justifie de retenter en agent :
          // tout autre refus (429, panne, réseau) doit remonter tel quel,
          // sinon on masquerait la vraie cause derrière un second échec.
          if (apiErrorCode(error) != 'AUTH_INVALID_CREDENTIALS') rethrow;
          token = await ref.read(agentApiProvider).login(
                email: email,
                password: password,
              );
          role = AppRole.agent;
        }
        await ref
            .read(authControllerProvider.notifier)
            .login(AuthSession(role: role, token: token));
        if (mounted) {
          context.go(
            role == AppRole.admin ? '/admin/dashboard' : '/agent/dashboard',
          );
        }
      } else {
        final token = await ref.read(commercantApiProvider).login(
              telephone: _telephoneController.text.trim(),
              pin: _pinController.text.trim(),
            );
        await ref
            .read(authControllerProvider.notifier)
            .login(AuthSession(role: AppRole.commercant, token: token));
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

  void _showForgotPinInfo(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.forgotPinTitle),
        content: Text(l10n.forgotPinBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.commonUnderstood)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Retour et langue en clair mais discrets : la marque doit rester
            // le premier élément lu.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const BackButtonIcon(),
                    tooltip: l10n.backToHomeTooltip,
                    // Cet écran est atteint par `push()` depuis l'accueil,
                    // mais aussi par `go('/commercant')` (redirection du
                    // routeur) où la pile est vide — d'où le repli sur '/'.
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/'),
                  ),
                  const Spacer(),
                  const AppSettingsActions(),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  children: [
                    const EchangoWordmark(fontSize: 26),
                    const SizedBox(height: 28),
                    Text(l10n.commercantSpaceTitle,
                        style: textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      l10n.commercantLoginSubtitle,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _telephoneController,
                      decoration: InputDecoration(
                        labelText: l10n.telephoneLabel,
                        hintText: l10n.telephoneHint,
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                      // `emailAddress` plutôt que `phone` : un clavier numérique
                      // pur empêcherait de taper le "@" qui déclenche le bascule
                      // admin ci-dessous ; les chiffres restent tapables
                      // normalement sur ce clavier, un numéro de téléphone n'est
                      // donc pas plus difficile à saisir.
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (v) =>
                          setState(() => _isAdminMode = v.contains('@')),
                      validator: (v) => (v == null || v.isEmpty)
                          ? l10n.telephoneRequired
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pinController,
                      decoration: InputDecoration(
                        labelText:
                            _isAdminMode ? l10n.passwordLabel : l10n.pinLabel,
                        prefixIcon: const Icon(Icons.lock_outline),
                        // Le compteur de caractères par défaut réservait une
                        // ligne sous le champ pour une information dont le
                        // commerçant n'a rien à faire.
                        counterText: '',
                      ),
                      keyboardType: _isAdminMode
                          ? TextInputType.visiblePassword
                          : TextInputType.number,
                      obscureText: true,
                      maxLength: _isAdminMode ? null : 12,
                      // Validateur permissif (4-12 chiffres) : un PIN valide fixé
                      // avant le relèvement du minimum à 6 (2026-07-13) doit
                      // rester utilisable pour se connecter.
                      validator: _isAdminMode
                          ? (v) => (v == null || v.length < 8)
                              ? l10n.passwordRequired
                              : null
                          : validateExistingPin(context),
                    ),
                    ErrorText(_error),
                    const SizedBox(height: 20),
                    LoadingButton(
                        loading: _loading,
                        onPressed: _submit,
                        label: l10n.loginLabel),
                    // Liens spécifiques au parcours commerçant — sans objet une
                    // fois basculé en mode admin, et inutilement déroutants.
                    if (!_isAdminMode) ...[
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => _showForgotPinInfo(context),
                        child: Text(l10n.forgotPin),
                      ),
                      // Séparateur explicite plutôt qu'un simple lien : un
                      // commerçant sans compte doit voir qu'il y a une autre
                      // porte, pas la deviner sous le bouton de connexion.
                      const SizedBox(height: 8),
                      _OrSeparator(label: l10n.commonOr),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add_business_outlined),
                        label: Text(l10n.notRegisteredYet),
                        onPressed: () => context.push('/commercant/register'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrSeparator extends StatelessWidget {
  const _OrSeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(child: Divider(color: colorScheme.outlineVariant, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(child: Divider(color: colorScheme.outlineVariant, height: 1)),
      ],
    );
  }
}
