import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/auth_session.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../widgets/promo_moderation_tile.dart';

final _moderationQueueProvider =
    FutureProvider.autoDispose((ref) => ref.watch(adminApiProvider).moderationQueue());

/// Id de la promo dont une action (masquer/vérifier/avertir) est en cours —
/// désactive le menu de sa ligne le temps de l'appel réseau, pour éviter un
/// double-tap qui déclencherait l'action deux fois (audit UX 2026-07-11).
final _inFlightProvider = StateProvider.autoDispose<Set<String>>((ref) => {});

/// File de modération (specs §3.4/§5.7) : promos signalées par des clients,
/// en attente d'une décision admin (masquer / vérifier OK / avertir).
class ModerationQueueScreen extends ConsumerWidget {
  const ModerationQueueScreen({super.key});

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    String promoId,
    Future<void> Function() action,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    ref.read(_inFlightProvider.notifier).update((ids) => {...ids, promoId});
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
    } finally {
      ref.read(_inFlightProvider.notifier).update((ids) => {...ids}..remove(promoId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final queueAsync = ref.watch(_moderationQueueProvider);
    final inFlight = ref.watch(_inFlightProvider);
    final api = ref.read(adminApiProvider);
    final role = ref.read(authControllerProvider).value?.role;
    final detailPath = role == AppRole.agent ? '/agent/promo-detail' : '/admin/promo-detail';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.moderationLabel),
        actions: const [LanguageSwitcherButton()],
      ),
      body: queueAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: ApiErrorText(error)),
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
                  loading: inFlight.contains(item.id),
                  onTap: () async {
                    final changed = await context.push<bool>(detailPath, extra: item);
                    if (changed == true) ref.invalidate(_moderationQueueProvider);
                  },
                  onMasquer: () => _act(context, ref, item.id, () => api.masquerPromo(item.id)),
                  onVerifierOk: () => _act(context, ref, item.id, () => api.verifierOkPromo(item.id)),
                  onAvertir: () => _act(context, ref, item.id, () => api.avertirPromo(item.id)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
