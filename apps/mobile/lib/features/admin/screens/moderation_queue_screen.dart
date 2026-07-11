import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../widgets/promo_moderation_tile.dart';

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
                return PromoModerationTile(
                  item: item,
                  onMasquer: () => _act(context, ref, () => api.masquerPromo(item.id)),
                  onVerifierOk: () => _act(context, ref, () => api.verifierOkPromo(item.id)),
                  onAvertir: () => _act(context, ref, () => api.avertirPromo(item.id)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
