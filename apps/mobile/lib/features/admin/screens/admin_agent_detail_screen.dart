import 'package:flutter/material.dart';
import '../../../domain/models/agent.dart';
import '../../shared/widgets/app_settings_actions.dart';

/// Fiche agent côté admin.
///
/// ⚠️ **Cet écran n'a plus grand-chose à montrer depuis le 2026-08-13, et il
/// le dit lui-même.** Sa raison d'être était que la liste « tassait email et
/// communes dans un sous-titre tronqué » ; les communes ont disparu, le
/// sous-titre ne porte plus que l'e-mail, et cette fiche affiche donc
/// exactement ce que la ligne affichait déjà — un nom et un e-mail.
///
/// **Il est conservé volontairement, en attendant une décision produit**, pas
/// par oubli : le supprimer retire un écran et une route, ce qui dépasse le
/// retrait du découpage administratif. La question est ouverte dans
/// `docs/PLAN_SUPPRESSION_COMMUNE.md` §10.
class AdminAgentDetailScreen extends StatelessWidget {
  const AdminAgentDetailScreen({super.key, required this.agent});

  final Agent agent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(agent.nom),
        actions: const [AppSettingsActions()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(Icons.email_outlined,
                  size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(agent.email),
            ],
          ),
        ],
      ),
    );
  }
}
