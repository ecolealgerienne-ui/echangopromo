import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/models/auth_session.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';

final _dashboardProvider = FutureProvider.autoDispose((ref) => ref.watch(adminApiProvider).dashboard());

/// Dashboard (specs §3.4) — partagé admin/agent (décision produit
/// 2026-07-12, agent = modérateur avec les mêmes écrans que l'admin) :
/// stats globales pour l'admin, restreintes aux communes de l'agent sinon
/// (backend scope automatiquement via `AdminController.scopedCommuneIds`).
/// Seules la gestion des agents et le journal d'audit restent admin-only —
/// le registre se consulte/valide depuis la fiche détail commerçant, plus
/// de menu dédié.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final statsAsync = ref.watch(_dashboardProvider);
    final isAdmin = ref.watch(authControllerProvider).value?.role == AppRole.admin;
    final rolePrefix = isAdmin ? '/admin' : '/agent';

    return Scaffold(
      appBar: AppBar(
        // Pas de bouton retour ici (retour terrain 2026-07-12) : cet écran
        // est l'accueil du rôle admin/agent, un bouton "retour à l'app
        // cliente" en dur porte à confusion (on garde la session pro active
        // tout en atterrissant sur l'app grand public) — sortir de cet
        // espace passe désormais par la déconnexion explicite (menu compte).
        automaticallyImplyLeading: false,
        title: Text(isAdmin ? l10n.adminSpaceTitle : l10n.agentSpaceTitle),
        actions: [
          const LanguageSwitcherButton(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (action) async {
              switch (action) {
                case 'logout':
                  await ref.read(authControllerProvider.notifier).logout();
                  if (context.mounted) context.go('/');
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'logout', child: Text(l10n.logoutTooltip)),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_dashboardProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            statsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => ApiErrorText(error),
              data: (stats) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 40) / 2,
                    child: _StatCard(
                      icon: Icons.storefront_outlined,
                      label: l10n.commercesActifsLabel,
                      value: stats.commercesActifs,
                    ),
                  ),
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 40) / 2,
                    child: _StatCard(
                      icon: Icons.local_offer_outlined,
                      label: l10n.promosPublieesLabel,
                      value: stats.promosPubliees,
                    ),
                  ),
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 40) / 2,
                    child: _StatCard(
                      icon: Icons.flag_outlined,
                      label: l10n.signalementsEnAttenteLabel,
                      value: stats.signalementsEnAttente,
                      onTap: () => context.push('$rolePrefix/moderation'),
                    ),
                  ),
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 40) / 2,
                    child: _StatCard(
                      icon: Icons.assignment_outlined,
                      label: l10n.registresEnAttenteLabel,
                      value: stats.registresEnAttente,
                      onTap: () => context.push('$rolePrefix/commercants'),
                    ),
                  ),
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 40) / 2,
                    child: _StatCard(
                      icon: Icons.edit_note_outlined,
                      label: l10n.profilsEnAttenteLabel,
                      value: stats.profilsEnAttente,
                      onTap: () => context.push('$rolePrefix/commercants'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.flag_outlined),
              label: Text(l10n.moderationLabel),
              onPressed: () => context.push('$rolePrefix/moderation'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.local_offer_outlined),
              label: Text(l10n.allPromosLabel),
              onPressed: () => context.push('$rolePrefix/promos'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.storefront_outlined),
              label: Text(l10n.commercantsLabel),
              onPressed: () => context.push('$rolePrefix/commercants'),
            ),
            if (!isAdmin) ...[
              const SizedBox(height: 8),
              // Tournée terrain (statut visité/à relancer par commune) —
              // fonctionnalité propre à l'agent, sans équivalent admin, donc
              // pas de bouton générique par rôle comme les autres ci-dessus.
              OutlinedButton.icon(
                icon: const Icon(Icons.map_outlined),
                label: Text(l10n.myCommunesTitle),
                onPressed: () => context.push('/agent/communes'),
              ),
            ],
            if (isAdmin) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.badge_outlined),
                label: Text(l10n.agentsLabel),
                onPressed: () => context.push('/admin/agents'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.history_outlined),
                label: Text(l10n.auditLogLabel),
                onPressed: () => context.push('/admin/audit-log'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value, this.onTap});

  final IconData icon;
  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon),
              const SizedBox(height: 4),
              Text('$value', style: Theme.of(context).textTheme.titleLarge),
              Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
