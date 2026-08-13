import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/auth_session.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/app_settings_actions.dart';
import '../widgets/promo_moderation_tile.dart';

// Filtres commune/wilaya retirés le 2026-08-13 : la file est nationale.

final _moderationQueueProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(adminApiProvider).moderationQueue();
});

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
      // ⚠️ **Un conflit de modération se rafraîchit, il ne se réessaie pas.**
      // `MODERATION_STATE_CHANGED` dit qu'un autre modérateur a tranché entre
      // l'affichage et le tap : la ligne à l'écran décrit un état qui n'existe
      // plus. Laisser la file telle quelle ferait retaper le même bouton sur la
      // même donnée périmée, indéfiniment — et le message promet justement que
      // la liste vient d'être rafraîchie. Une promesse dans une traduction que
      // le code ne tient pas serait pire que pas de message du tout.
      //
      // ⚠️ Et il faut passer par `apiErrorCode`, jamais par un `on ApiException
      // catch` : l'intercepteur de `ApiClient` enveloppe l'exception dans une
      // `DioException` (règle 26).
      if (apiErrorCode(error) == 'MODERATION_STATE_CHANGED') {
        ref.invalidate(_moderationQueueProvider);
      }
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
      ref
          .read(_inFlightProvider.notifier)
          .update((ids) => {...ids}..remove(promoId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final queueAsync = ref.watch(_moderationQueueProvider);
    final inFlight = ref.watch(_inFlightProvider);
    final api = ref.read(adminApiProvider);
    final role = ref.read(authControllerProvider).value?.role;
    final detailPath =
        role == AppRole.agent ? '/agent/promo-detail' : '/admin/promo-detail';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.moderationLabel),
        actions: const [AppSettingsActions()],
      ),
      body: Column(
        children: [
          // ⚠️ La `CommuneFilterBar` était ici jusqu'au 2026-08-13. Cette file
          // est désormais **nationale et partagée par tous les agents**, sans
          // aucun cadrage ni partition du travail : deux modérateurs peuvent
          // traiter la même promo, et les résolutions serveur sont des `update`
          // inconditionnels. C'est un point ouvert, pas un aboutissement.
          Expanded(
            child: queueAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: ApiErrorText(error)),
              data: (items) {
                if (items.isEmpty) {
                  return Center(child: Text(l10n.noModerationItems));
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(_moderationQueueProvider),
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return PromoModerationTile(
                        item: item,
                        loading: inFlight.contains(item.id),
                        onTap: () async {
                          final changed =
                              await context.push<bool>(detailPath, extra: item);
                          if (changed == true) {
                            ref.invalidate(_moderationQueueProvider);
                          }
                        },
                        // `item.moderationStatus` et non `signalee` en dur :
                        // c'est l'état AFFICHÉ qui fait foi, et c'est lui que
                        // le serveur compare (voir `AdminApi.masquerPromo`).
                        onMasquer: () => _act(
                            context,
                            ref,
                            item.id,
                            () => api.masquerPromo(
                                item.id, item.moderationStatus)),
                        onVerifierOk: () => _act(
                            context,
                            ref,
                            item.id,
                            () => api.verifierOkPromo(
                                item.id, item.moderationStatus)),
                        onAvertir: () => _act(
                            context,
                            ref,
                            item.id,
                            () => api.avertirPromo(
                                item.id, item.moderationStatus)),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
