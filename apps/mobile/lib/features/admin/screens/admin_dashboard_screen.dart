import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';

final _dashboardProvider = FutureProvider.autoDispose((ref) => ref.watch(adminApiProvider).dashboard());

/// Dashboard admin (specs §3.4) : stats globales + accès aux files de
/// travail (modération, agents) — le registre se consulte/valide désormais
/// depuis la fiche détail commerçant, plus de menu dédié.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final statsAsync = ref.watch(_dashboardProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const BackButtonIcon(),
          tooltip: l10n.backToHomeTooltip,
          onPressed: () => context.go('/'),
        ),
        title: Text(l10n.adminSpaceTitle),
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
                      onTap: () => context.push('/admin/moderation'),
                    ),
                  ),
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 40) / 2,
                    child: _StatCard(
                      icon: Icons.assignment_outlined,
                      label: l10n.registresEnAttenteLabel,
                      value: stats.registresEnAttente,
                      onTap: () => context.push('/admin/commercants'),
                    ),
                  ),
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 40) / 2,
                    child: _StatCard(
                      icon: Icons.edit_note_outlined,
                      label: l10n.profilsEnAttenteLabel,
                      value: stats.profilsEnAttente,
                      onTap: () => context.push('/admin/commercants'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.flag_outlined),
              label: Text(l10n.moderationLabel),
              onPressed: () => context.push('/admin/moderation'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.local_offer_outlined),
              label: Text(l10n.allPromosLabel),
              onPressed: () => context.push('/admin/promos'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.storefront_outlined),
              label: Text(l10n.commercantsLabel),
              onPressed: () => context.push('/admin/commercants'),
            ),
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
