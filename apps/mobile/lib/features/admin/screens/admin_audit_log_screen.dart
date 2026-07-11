import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../domain/enums/audit_actor_type.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/widgets/language_switcher_button.dart';

final _auditLogProvider = FutureProvider.autoDispose((ref) => ref.watch(adminApiProvider).auditLog());

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
        actions: const [LanguageSwitcherButton()],
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.commonError(error.toString()))),
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
                final actorLabel = auditActorTypeLabel(context, entry.actorType);
                return ListTile(
                  leading: Icon(
                    entry.actorType == AuditActorType.admin
                        ? Icons.admin_panel_settings_outlined
                        : Icons.badge_outlined,
                  ),
                  title: Text(entry.action),
                  subtitle: Text(
                    [
                      '$actorLabel ${entry.actorId}',
                      if (entry.targetType != null) '${entry.targetType} ${entry.targetId}',
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
