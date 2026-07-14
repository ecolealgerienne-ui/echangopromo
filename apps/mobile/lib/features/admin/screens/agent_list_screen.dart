import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/agent.dart';
import '../../../domain/models/commune.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/commune_multi_select_field.dart';
import '../../shared/widgets/language_switcher_button.dart';

final _agentsProvider = FutureProvider.autoDispose((ref) => ref.watch(adminApiProvider).listAgents());
final _communesProvider = FutureProvider.autoDispose((ref) => ref.watch(communeApiProvider).list());

/// Même pattern que `ModerationQueueScreen._inFlightProvider` (audit UX
/// 2026-07-11) : agent dont une action (assigner/révoquer) est en cours.
final _inFlightAgentsProvider = StateProvider.autoDispose<Set<String>>((ref) => {});
final _transferInFlightProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Gestion des agents (specs §3.4) : création, assignation/retrait de
/// communes, révocation de session, transfert de communes entre deux agents.
class AgentListScreen extends ConsumerWidget {
  const AgentListScreen({super.key});

  String _communeNames(List<Commune> communes) {
    if (communes.isEmpty) return '';
    return communes.map((c) => c.nom).join(', ');
  }

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

  Future<void> _assignCommunes(
    BuildContext context,
    WidgetRef ref,
    Agent agent,
    List<Commune> communes,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    var selected = agent.communes.map((c) => c.id).toSet();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.assignCommunesLabel),
          content: SizedBox(
            width: double.maxFinite,
            child: CommuneMultiSelectField(
              communes: communes,
              selectedCommuneIds: selected,
              onChanged: (v) => setState(() => selected = v),
            ),
          ),
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
      ),
    );
    if (confirmed != true) return;
    ref.read(_inFlightAgentsProvider.notifier).update((ids) => {...ids, agent.id});
    try {
      await ref.read(adminApiProvider).assignCommunes(
            agentId: agent.id,
            communeIds: selected.toList(),
          );
      await _reload(ref);
    } catch (error) {
      if (context.mounted) await _showError(context, error);
    } finally {
      ref.read(_inFlightAgentsProvider.notifier).update((ids) => {...ids}..remove(agent.id));
    }
  }

  /// Mot de passe vraiment oublié — l'agent ne peut pas le changer
  /// lui-même (décision produit 2026-07-14), seul l'admin en fixe un
  /// nouveau, à communiquer de vive voix après avoir identifié l'agent
  /// (même schéma que `_confirmAndResetPin` côté commerçant).
  Future<void> _resetPassword(BuildContext context, WidgetRef ref, Agent agent) async {
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
              Text(l10n.resetAgentPasswordDialogBody, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordController,
                decoration: InputDecoration(labelText: l10n.passwordLabel),
                obscureText: true,
                validator: (v) => (v == null || v.length < 8) ? l10n.passwordRequired : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
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
    ref.read(_inFlightAgentsProvider.notifier).update((ids) => {...ids, agent.id});
    try {
      await ref.read(adminApiProvider).resetAgentPassword(agent.id, newPassword);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.resetAgentPasswordSuccessMessage)),
        );
      }
    } catch (error) {
      if (context.mounted) await _showError(context, error);
    } finally {
      ref.read(_inFlightAgentsProvider.notifier).update((ids) => {...ids}..remove(agent.id));
    }
  }

  Future<void> _revokeToken(BuildContext context, WidgetRef ref, Agent agent) async {
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
    ref.read(_inFlightAgentsProvider.notifier).update((ids) => {...ids, agent.id});
    try {
      await ref.read(adminApiProvider).revokeAgentToken(agent.id);
    } catch (error) {
      if (context.mounted) await _showError(context, error);
    } finally {
      ref.read(_inFlightAgentsProvider.notifier).update((ids) => {...ids}..remove(agent.id));
    }
  }

  Future<void> _transferCommunes(
    BuildContext context,
    WidgetRef ref,
    List<Agent> agents,
    List<Commune> communes,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    String? fromAgentId;
    String? toAgentId;
    var selected = <String>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          Agent? fromAgent;
          for (final a in agents) {
            if (a.id == fromAgentId) fromAgent = a;
          }
          final availableCommunes = fromAgent?.communes ?? const <Commune>[];
          return AlertDialog(
            title: Text(l10n.transferCommunesLabel),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(labelText: l10n.fromAgentLabel),
                    items: [for (final a in agents) DropdownMenuItem(value: a.id, child: Text(a.nom))],
                    onChanged: (v) => setState(() {
                      fromAgentId = v;
                      selected = {};
                    }),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(labelText: l10n.toAgentLabel),
                    items: [for (final a in agents) DropdownMenuItem(value: a.id, child: Text(a.nom))],
                    onChanged: (v) => setState(() => toAgentId = v),
                  ),
                  const SizedBox(height: 8),
                  if (availableCommunes.isNotEmpty)
                    CommuneMultiSelectField(
                      communes: availableCommunes,
                      selectedCommuneIds: selected,
                      onChanged: (v) => setState(() => selected = v),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: fromAgentId != null && toAgentId != null && selected.isNotEmpty
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: Text(l10n.commonConfirm),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || fromAgentId == null || toAgentId == null || selected.isEmpty) return;
    ref.read(_transferInFlightProvider.notifier).state = true;
    try {
      await ref.read(adminApiProvider).transferCommunes(
            communeIds: selected.toList(),
            fromAgentId: fromAgentId!,
            toAgentId: toAgentId!,
          );
      await _reload(ref);
    } catch (error) {
      if (context.mounted) await _showError(context, error);
    } finally {
      ref.read(_transferInFlightProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final agentsAsync = ref.watch(_agentsProvider);
    final communesAsync = ref.watch(_communesProvider);
    final inFlightAgents = ref.watch(_inFlightAgentsProvider);
    final transferInFlight = ref.watch(_transferInFlightProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.agentsLabel),
        actions: [
          IconButton(
            icon: transferInFlight
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.swap_horiz),
            tooltip: l10n.transferCommunesLabel,
            onPressed: transferInFlight ||
                    agentsAsync.valueOrNull == null ||
                    communesAsync.valueOrNull == null
                ? null
                : () => _transferCommunes(context, ref, agentsAsync.value!, communesAsync.value!),
          ),
          const LanguageSwitcherButton(),
        ],
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
          final communes = communesAsync.valueOrNull ?? const <Commune>[];
          if (agents.isEmpty) {
            return Center(child: Text(l10n.noAgentsYet));
          }
          return RefreshIndicator(
            onRefresh: () => _reload(ref),
            child: ListView.builder(
              itemCount: agents.length,
              itemBuilder: (context, index) {
                final agent = agents[index];
                final communeNames = _communeNames(agent.communes);
                return ListTile(
                  onTap: () => context.push('/admin/agents/detail', extra: agent),
                  title: Text(agent.nom),
                  subtitle: Text('${agent.email}${communeNames.isNotEmpty ? ' · $communeNames' : ''}'),
                  trailing: inFlightAgents.contains(agent.id)
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : PopupMenuButton<String>(
                          onSelected: (action) {
                            switch (action) {
                              case 'assignCommunes':
                                _assignCommunes(context, ref, agent, communes);
                              case 'resetPassword':
                                _resetPassword(context, ref, agent);
                              case 'revoke':
                                _revokeToken(context, ref, agent);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                                value: 'assignCommunes', child: Text(l10n.assignCommunesLabel)),
                            PopupMenuItem(
                                value: 'resetPassword', child: Text(l10n.resetAgentPasswordLabel)),
                            PopupMenuItem(value: 'revoke', child: Text(l10n.revokeTokenLabel)),
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
