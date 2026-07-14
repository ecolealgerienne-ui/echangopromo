// ÉCRAN TEMPORAIRE DE TEST — À SUPPRIMER avant l'ouverture publique.
// Bascule rapide entre les 4 profils (commerçant/admin/agent/client sans
// connexion) en gardant les identifiants de chacun en mémoire (stockage
// sécurisé, jamais en clair) pour ne pas avoir à les retaper à chaque test.
// Accès direct par URL uniquement (/dev/profiles), jamais lié depuis un
// menu — même pattern que l'entrée admin cachée.
//
// Pas de passage par AppLocalizations ici (texte français en dur) :
// délibéré, pour que la suppression future se limite à ce fichier + la
// ligne de route dans router.dart, sans ménage à faire dans les .arb.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/auth_session.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';

class DevProfileSwitcherScreen extends ConsumerStatefulWidget {
  const DevProfileSwitcherScreen({super.key});

  @override
  ConsumerState<DevProfileSwitcherScreen> createState() => _DevProfileSwitcherScreenState();
}

class _DevProfileSwitcherScreenState extends ConsumerState<DevProfileSwitcherScreen> {
  static const _keyCommercantTelephone = 'dev_switcher_commercant_telephone';
  static const _keyCommercantPin = 'dev_switcher_commercant_pin';
  static const _keyAgentEmail = 'dev_switcher_agent_email';
  static const _keyAgentPassword = 'dev_switcher_agent_password';
  static const _keyAdminEmail = 'dev_switcher_admin_email';
  static const _keyAdminPassword = 'dev_switcher_admin_password';

  // Identifiants du pilote pré-remplis pour ne pas avoir à les ressaisir à
  // chaque test — écrasés par les valeurs sauvegardées si elles diffèrent
  // (voir _loadSaved).
  final _commercantTelephone = TextEditingController(text: '0555545352');
  final _commercantPin = TextEditingController(text: '010203');
  final _agentEmail = TextEditingController(text: 'agent1@echangopromo.com');
  final _agentPassword = TextEditingController(text: '123456789');
  final _adminEmail = TextEditingController(text: 'superadmin@echangopromo.com');
  final _adminPassword = TextEditingController(text: '123456789');

  bool _loading = false;
  String? _busyProfile;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _commercantTelephone.dispose();
    _commercantPin.dispose();
    _agentEmail.dispose();
    _agentPassword.dispose();
    _adminEmail.dispose();
    _adminPassword.dispose();
    super.dispose();
  }

  FlutterSecureStorage get _storage => ref.read(secureStorageProvider);

  Future<void> _loadSaved() async {
    final values = await Future.wait([
      _storage.read(key: _keyCommercantTelephone),
      _storage.read(key: _keyCommercantPin),
      _storage.read(key: _keyAgentEmail),
      _storage.read(key: _keyAgentPassword),
      _storage.read(key: _keyAdminEmail),
      _storage.read(key: _keyAdminPassword),
    ]);
    if (!mounted) return;
    // Ne remplace le préremplissage par défaut que si une valeur a déjà été
    // sauvegardée explicitement — sinon `read()` renvoie `null` et
    // effacerait les identifiants pilote pré-remplis ci-dessus.
    if (values[0] != null) _commercantTelephone.text = values[0]!;
    if (values[1] != null) _commercantPin.text = values[1]!;
    if (values[2] != null) _agentEmail.text = values[2]!;
    if (values[3] != null) _agentPassword.text = values[3]!;
    if (values[4] != null) _adminEmail.text = values[4]!;
    if (values[5] != null) _adminPassword.text = values[5]!;
    setState(() {});
  }

  Future<void> _save(String key, String value) => _storage.write(key: key, value: value);

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(extractApiErrorMessage(error, fallback: 'Connexion impossible.', locale: Localizations.localeOf(context)))),
    );
  }

  Future<void> _loginCommercant() async {
    await _save(_keyCommercantTelephone, _commercantTelephone.text.trim());
    await _save(_keyCommercantPin, _commercantPin.text.trim());
    setState(() {
      _loading = true;
      _busyProfile = 'commercant';
    });
    try {
      final api = ref.read(commercantApiProvider);
      final token = await api.login(
        telephone: _commercantTelephone.text.trim(),
        pin: _commercantPin.text.trim(),
      );
      await ref.read(authControllerProvider.notifier).loginThenResolveId(
            role: AppRole.commercant,
            token: token,
            fetchId: () async => (await api.me()).id,
          );
      // `push` plutôt que `go` : contrairement aux écrans de connexion
      // normaux, ici on veut explicitement pouvoir revenir en arrière vers
      // le sélecteur de profil pour enchaîner les tests (`go` viderait la
      // pile de navigation et ferait disparaître le bouton retour).
      if (mounted) context.push('/commercant/dashboard');
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginAgent() async {
    await _save(_keyAgentEmail, _agentEmail.text.trim());
    await _save(_keyAgentPassword, _agentPassword.text);
    setState(() {
      _loading = true;
      _busyProfile = 'agent';
    });
    try {
      final api = ref.read(agentApiProvider);
      final token = await api.login(email: _agentEmail.text.trim(), password: _agentPassword.text);
      await ref.read(authControllerProvider.notifier).loginThenResolveId(
            role: AppRole.agent,
            token: token,
            fetchId: () async => (await api.me()).id,
          );
      if (mounted) context.push('/agent/dashboard');
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginAdmin() async {
    await _save(_keyAdminEmail, _adminEmail.text.trim());
    await _save(_keyAdminPassword, _adminPassword.text);
    setState(() {
      _loading = true;
      _busyProfile = 'admin';
    });
    try {
      final api = ref.read(adminApiProvider);
      final token = await api.login(email: _adminEmail.text.trim(), password: _adminPassword.text);
      await ref.read(authControllerProvider.notifier).loginThenResolveId(
            role: AppRole.admin,
            token: token,
            fetchId: () async => (await api.me()).id,
          );
      if (mounted) context.push('/admin/dashboard');
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _useClientWithoutLogin() async {
    setState(() {
      _loading = true;
      _busyProfile = 'client';
    });
    try {
      await ref.read(authControllerProvider.notifier).logout();
      if (mounted) context.push('/');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Test — Changer de profil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Écran de test temporaire, à supprimer avant l\'ouverture publique. '
              'Les identifiants saisis ici sont mémorisés (stockage sécurisé local) '
              'pour basculer rapidement entre profils.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            session == null
                ? 'Session actuelle : aucune (client sans connexion)'
                : 'Session actuelle : ${session.role.name}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _ProfileSection(
            title: 'Commerçant',
            loading: _loading && _busyProfile == 'commercant',
            onLogin: _loginCommercant,
            fields: [
              TextField(
                controller: _commercantTelephone,
                decoration: const InputDecoration(labelText: 'Téléphone'),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: _commercantPin,
                decoration: const InputDecoration(labelText: 'PIN'),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 12,
              ),
            ],
          ),
          _ProfileSection(
            title: 'Agent',
            loading: _loading && _busyProfile == 'agent',
            onLogin: _loginAgent,
            fields: [
              TextField(
                controller: _agentEmail,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextField(
                controller: _agentPassword,
                decoration: const InputDecoration(labelText: 'Mot de passe'),
                obscureText: true,
              ),
            ],
          ),
          _ProfileSection(
            title: 'Admin',
            loading: _loading && _busyProfile == 'admin',
            onLogin: _loginAdmin,
            fields: [
              TextField(
                controller: _adminEmail,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextField(
                controller: _adminPassword,
                decoration: const InputDecoration(labelText: 'Mot de passe'),
                obscureText: true,
              ),
            ],
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Client (sans connexion)', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('Déconnecte la session en cours et ouvre l\'app grand public.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _loading ? null : _useClientWithoutLogin,
                    child: _loading && _busyProfile == 'client'
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Utiliser en client'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.title,
    required this.fields,
    required this.onLogin,
    required this.loading,
  });

  final String title;
  final List<Widget> fields;
  final Future<void> Function() onLogin;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...fields,
            const SizedBox(height: 8),
            FilledButton(
              onPressed: loading ? null : onLogin,
              child: loading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Se connecter'),
            ),
          ],
        ),
      ),
    );
  }
}
