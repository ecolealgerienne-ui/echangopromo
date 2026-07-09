import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/language_switcher_button.dart';

final _moderationQueueProvider =
    FutureProvider.autoDispose((ref) => ref.watch(adminApiProvider).moderationQueue());

/// File de modération (specs §3.4/§5.7) : promos signalées par des clients,
/// en attente d'une décision admin (masquer / vérifier OK / avertir).
class ModerationQueueScreen extends ConsumerWidget {
  const ModerationQueueScreen({super.key});

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await action();
      ref.invalidate(_moderationQueueProvider);
    } catch (error) {
      if (context.mounted) {
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
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final queueAsync = ref.watch(_moderationQueueProvider);
    final api = ref.read(adminApiProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.moderationLabel),
        actions: const [LanguageSwitcherButton()],
      ),
      body: queueAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.commonError(error.toString()))),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(l10n.noModerationItems));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_moderationQueueProvider),
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage:
                        item.photoUrl != null ? CachedNetworkImageProvider(item.photoUrl!) : null,
                  ),
                  title: Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${item.commercantNom} · ${item.commercantTelephone}\n'
                    '${l10n.reportCountLabel(item.activeReportCount)}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      switch (action) {
                        case 'masquer':
                          _act(context, ref, () => api.masquerPromo(item.id));
                        case 'verifier':
                          _act(context, ref, () => api.verifierOkPromo(item.id));
                        case 'avertir':
                          _act(context, ref, () => api.avertirPromo(item.id));
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'masquer', child: Text(l10n.masquerLabel)),
                      PopupMenuItem(value: 'verifier', child: Text(l10n.verifierOkLabel)),
                      PopupMenuItem(value: 'avertir', child: Text(l10n.avertirLabel)),
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
