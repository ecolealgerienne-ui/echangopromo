import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/agent.dart';
import '../../../domain/models/zone.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/language_switcher_button.dart';

final _agentsProvider = FutureProvider.autoDispose((ref) => ref.watch(adminApiProvider).listAgents());
final _zonesProvider = FutureProvider.autoDispose((ref) => ref.watch(adminApiProvider).listZones());

/// Gestion des agents (specs §3.4) : création, assignation/retrait de zone,
/// révocation de session, transfert de zone entre deux agents.
class AgentListScreen extends ConsumerWidget {
  const AgentListScreen({super.key});

  String _zoneName(List<Zone> zones, String? zoneId) {
    if (zoneId == null) return '';
    for (final zone in zones) {
      if (zone.id == zoneId) return zone.nom;
    }
    return '';
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

  Future<void> _assignZone(BuildContext context, WidgetRef ref, Agent agent, List<Zone> zones) async {
    final l10n = AppLocalizations.of(context)!;
    String? selected = agent.zoneId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.assignZoneLabel),
          content: DropdownButtonFormField<String?>(
            initialValue: selected,
            decoration: InputDecoration(labelText: l10n.zoneLabel),
            items: [
              DropdownMenuItem(value: null, child: Text(l10n.noZoneLabel)),
              for (final zone in zones) DropdownMenuItem(value: zone.id, child: Text(zone.nom)),
            ],
            onChanged: (v) => setState(() => selected = v),
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
    try {
      await ref.read(adminApiProvider).assignZone(agentId: agent.id, zoneId: selected);
      await _reload(ref);
    } catch (error) {
      if (context.mounted) await _showError(context, error);
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
    try {
      await ref.read(adminApiProvider).revokeAgentToken(agent.id);
    } catch (error) {
      if (context.mounted) await _showError(context, error);
    }
  }

  Future<void> _transferZone(BuildContext context, WidgetRef ref, List<Agent> agents, List<Zone> zones) async {
    final l10n = AppLocalizations.of(context)!;
    String? zoneId;
    String? fromAgentId;
    String? toAgentId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.transferZoneLabel),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: l10n.zoneLabel),
                items: [for (final z in zones) DropdownMenuItem(value: z.id, child: Text(z.nom))],
                onChanged: (v) => setState(() => zoneId = v),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: l10n.fromAgentLabel),
                items: [for (final a in agents) DropdownMenuItem(value: a.id, child: Text(a.nom))],
                onChanged: (v) => setState(() => fromAgentId = v),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: l10n.toAgentLabel),
                items: [for (final a in agents) DropdownMenuItem(value: a.id, child: Text(a.nom))],
                onChanged: (v) => setState(() => toAgentId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: zoneId != null && fromAgentId != null && toAgentId != null
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: Text(l10n.commonConfirm),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || zoneId == null || fromAgentId == null || toAgentId == null) return;
    try {
      await ref.read(adminApiProvider).transferZone(
            zoneId: zoneId!,
            fromAgentId: fromAgentId!,
            toAgentId: toAgentId!,
          );
      await _reload(ref);
    } catch (error) {
      if (context.mounted) await _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final agentsAsync = ref.watch(_agentsProvider);
    final zonesAsync = ref.watch(_zonesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.agentsLabel),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: l10n.transferZoneLabel,
            onPressed: agentsAsync.valueOrNull == null || zonesAsync.valueOrNull == null
                ? null
                : () => _transferZone(context, ref, agentsAsync.value!, zonesAsync.value!),
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
        error: (error, _) => Center(child: Text(l10n.commonError(error.toString()))),
        data: (agents) {
          final zones = zonesAsync.valueOrNull ?? const <Zone>[];
          if (agents.isEmpty) {
            return Center(child: Text(l10n.noAgentsYet));
          }
          return RefreshIndicator(
            onRefresh: () => _reload(ref),
            child: ListView.builder(
              itemCount: agents.length,
              itemBuilder: (context, index) {
                final agent = agents[index];
                final zoneName = _zoneName(zones, agent.zoneId);
                return ListTile(
                  title: Text(agent.nom),
                  subtitle: Text('${agent.email}${zoneName.isNotEmpty ? ' · $zoneName' : ''}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      switch (action) {
                        case 'assignZone':
                          _assignZone(context, ref, agent, zones);
                        case 'revoke':
                          _revokeToken(context, ref, agent);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'assignZone', child: Text(l10n.assignZoneLabel)),
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
