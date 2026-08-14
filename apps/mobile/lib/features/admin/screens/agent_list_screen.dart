import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/agent.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/app_settings_actions.dart';

final _agentsProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(adminApiProvider).listAgents());

/// Même pattern que `ModerationQueueScreen._inFlightProvider` (audit UX
/// 2026-07-11) : agent dont une action est en cours.
final _inFlightAgentsProvider =
    StateProvider.autoDispose<Set<String>>((ref) => {});

/// Gestion des agents (specs §3.4) : création, réinitialisation de mot de
/// passe, révocation de session.
///
/// ⚠️ **Cet écran a perdu sa moitié territoriale le 2026-08-13** : plus
/// d'assignation de communes, plus de transfert entre agents, plus de
/// sous-titre listant un secteur. Ce qui reste — créer, réinitialiser,
/// révoquer — est désormais **tout ce dont l'admin dispose** face à un agent :
/// il n'existe plus aucune granularité entre « agent » et « admin moins deux
/// écrans », et la révocation est le seul frein réel.
class AgentListScreen extends ConsumerWidget {
  const AgentListScreen({super.key});

  Future<void> _reload(WidgetRef ref) async {
    ref.invalidate(_agentsProvider);
  }

  Future<void> _showError(BuildContext context, Object error) async {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(extractApiErrorMessage(
          error,
          fallback: l10n.operationFailed,
          locale: Localizations.localeOf(context),
        )),
      ),
    );
  }

  /// Mot de passe vraiment oublié — l'agent ne peut pas le changer
  /// lui-même (décision produit 2026-07-14), seul l'admin en fixe un
  /// nouveau, à communiquer de vive voix après avoir identifié l'agent
  /// (même schéma que `_confirmAndResetPin` côté commerçant).
  Future<void> _resetPassword(
      BuildContext context, WidgetRef ref, Agent agent) async {
    final l10n = AppLocalizations.of(context)!;
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final newPassword = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.resetAgentPasswordDialogTitle),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.resetAgentPasswordDialogBody,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordController,
                decoration: InputDecoration(labelText: l10n.passwordLabel),
                obscureText: true,
                validator: (v) =>
                    (v == null || v.length < 8) ? l10n.passwordRequired : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.commonCancel)),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context, passwordController.text);
            },
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (newPassword == null || !context.mounted) return;
    ref
        .read(_inFlightAgentsProvider.notifier)
        .update((ids) => {...ids, agent.id});
    try {
      await ref
          .read(adminApiProvider)
          .resetAgentPassword(agent.id, newPassword);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.resetAgentPasswordSuccessMessage)),
        );
      }
    } catch (error) {
      if (context.mounted) await _showError(context, error);
    } finally {
      ref
          .read(_inFlightAgentsProvider.notifier)
          .update((ids) => {...ids}..remove(agent.id));
    }
  }

  Future<void> _revokeToken(
      BuildContext context, WidgetRef ref, Agent agent) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.revokeTokenLabel),
        content: Text(l10n.revokeTokenConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref
        .read(_inFlightAgentsProvider.notifier)
        .update((ids) => {...ids, agent.id});
    try {
      await ref.read(adminApiProvider).revokeAgentToken(agent.id);
    } catch (error) {
      if (context.mounted) await _showError(context, error);
    } finally {
      ref
          .read(_inFlightAgentsProvider.notifier)
          .update((ids) => {...ids}..remove(agent.id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final agentsAsync = ref.watch(_agentsProvider);
    final inFlightAgents = ref.watch(_inFlightAgentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.agentsLabel),
        // ⚠️ L'action « transférer des communes » était ici. Elle répondait à un
        // besoin métier réel — le départ d'un agent, pour que ses commerces ne
        // cessent pas d'être suivis en silence — que **rien ne reprend** depuis
        // le 2026-08-13. Sans territoire la question ne se pose plus ; c'est la
        // question inverse qui s'ouvre, celle de l'attribution du travail.
        actions: const [AppSettingsActions()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_outlined),
        label: Text(l10n.newAgentLabel),
        onPressed: () async {
          final created = await context.push<bool>('/admin/agents/new');
          if (created == true) await _reload(ref);
        },
      ),
      body: agentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: ApiErrorText(error)),
        data: (agents) {
          if (agents.isEmpty) {
            return Center(child: Text(l10n.noAgentsYet));
          }
          return RefreshIndicator(
            onRefresh: () => _reload(ref),
            child: ListView.builder(
              itemCount: agents.length,
              itemBuilder: (context, index) {
                final agent = agents[index];
                return ListTile(
                  onTap: () =>
                      context.push('/admin/agents/detail', extra: agent),
                  title: Text(agent.nom),
                  subtitle: Text(agent.email),
                  trailing: inFlightAgents.contains(agent.id)
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : PopupMenuButton<String>(
                          onSelected: (action) {
                            switch (action) {
                              case 'resetPassword':
                                _resetPassword(context, ref, agent);
                              case 'revoke':
                                _revokeToken(context, ref, agent);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                                value: 'resetPassword',
                                child: Text(l10n.resetAgentPasswordLabel)),
                            PopupMenuItem(
                                value: 'revoke',
                                child: Text(l10n.revokeTokenLabel)),
                          ],
                        ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
