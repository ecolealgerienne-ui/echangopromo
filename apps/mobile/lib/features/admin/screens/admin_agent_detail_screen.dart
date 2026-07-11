import 'package:flutter/material.dart';
import '../../../domain/models/agent.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/widgets/language_switcher_button.dart';

/// Fiche agent côté admin — la liste (`AgentListScreen`) tassait email et
/// communes dans un sous-titre tronqué, sans vue détail dédiée. Les actions
/// (assigner des communes, révoquer la session) restent sur la liste — pas
/// dupliquées ici, `Agent` ne porte que les champs affichés ci-dessous.
class AdminAgentDetailScreen extends StatelessWidget {
  const AdminAgentDetailScreen({super.key, required this.agent});

  final Agent agent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(agent.nom),
        actions: const [LanguageSwitcherButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(Icons.email_outlined, size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(agent.email),
            ],
          ),
          const SizedBox(height: 16),
          Text(l10n.assignedCommunesLabel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (agent.communes.isEmpty)
            Text(
              l10n.noCommunesAssignedLabel,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final commune in agent.communes)
                  Chip(label: Text(commune.nom)),
              ],
            ),
        ],
      ),
    );
  }
}
