import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../domain/enums/audit_actor_type.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/app_settings_actions.dart';

final _auditLogProvider =
    FutureProvider.autoDispose((ref) => ref.watch(adminApiProvider).auditLog());

/// Journal d'audit (plan de correction, Phase 3) — traçabilité des actions
/// agent/admin, jusqu'ici enregistrées en base mais jamais consultables
/// autrement que par une requête SQL directe sur le VPS.
class AdminAuditLogScreen extends ConsumerWidget {
  const AdminAuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final entriesAsync = ref.watch(_auditLogProvider);
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.auditLogLabel),
        actions: const [AppSettingsActions()],
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: ApiErrorText(error)),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(child: Text(l10n.noAuditLogItems));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_auditLogProvider),
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final roleLabel = auditActorTypeLabel(context, entry.actorType);
                // ⚠️ **Le repli sur l'UUID est la bonne réponse, pas un pis-aller.**
                // Le serveur rend `null` quand il n'a pas su résoudre l'acteur ou
                // la cible, plutôt que d'inventer un libellé — afficher alors
                // l'identifiant montre la seule vérité disponible. Écrire
                // « inconnu » à la place ferait passer « je ne sais pas » pour
                // « il n'existe plus » (règle 29).
                final acteur = entry.actorLabel ?? entry.actorId;
                final cible = entry.targetLabel ?? entry.targetId;
                return ListTile(
                  leading: Icon(
                    entry.actorType == AuditActorType.admin
                        ? Icons.admin_panel_settings_outlined
                        : Icons.badge_outlined,
                  ),
                  title: Text(entry.action),
                  subtitle: Text(
                    [
                      '$roleLabel · $acteur',
                      if (entry.targetType != null)
                        '${entry.targetType} · $cible',
                      dateFormat.format(entry.createdAt),
                    ].join(' · '),
                  ),
                  isThreeLine: true,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
