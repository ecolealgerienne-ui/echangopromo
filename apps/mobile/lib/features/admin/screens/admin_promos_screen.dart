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

final _searchProvider = StateProvider.autoDispose<String>((ref) => '');

// Filtres commune/wilaya retirés le 2026-08-13 : liste nationale, seule la
// recherche texte permet encore de la resserrer.

final _allPromosProvider = FutureProvider.autoDispose((ref) {
  final search = ref.watch(_searchProvider);
  return ref.watch(adminApiProvider).listAllPromos(search: search);
});

/// Même pattern que `ModerationQueueScreen._inFlightProvider` (audit UX 2026-07-11).
final _inFlightProvider = StateProvider.autoDispose<Set<String>>((ref) => {});

/// Vue globale de toutes les promos (plan de correction, Phase 2) —
/// contrairement à la file de modération, pas seulement celles ayant
/// atteint le seuil de signalements. Accessible admin + agent (le rôle du
/// JWT détermine côté backend le périmètre — global pour l'admin, scopé
/// national depuis le 2026-08-13, pour l'agent comme pour l'admin).
class AdminPromosScreen extends ConsumerWidget {
  const AdminPromosScreen({super.key});

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
      ref.invalidate(_allPromosProvider);
    } catch (error) {
      // Même raison qu'en file de modération : un conflit se rafraîchit, il ne
      // se réessaie pas — la ligne affichée décrit un état qui n'existe plus.
      if (apiErrorCode(error) == 'MODERATION_STATE_CHANGED') {
        ref.invalidate(_allPromosProvider);
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
    final promosAsync = ref.watch(_allPromosProvider);
    final inFlight = ref.watch(_inFlightProvider);
    final api = ref.read(adminApiProvider);
    final role = ref.read(authControllerProvider).value?.role;
    final detailPath =
        role == AppRole.agent ? '/agent/promo-detail' : '/admin/promo-detail';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.allPromosLabel),
        actions: const [AppSettingsActions()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) =>
                  ref.read(_searchProvider.notifier).state = value,
            ),
          ),
          Expanded(
            child: promosAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: ApiErrorText(error)),
              data: (items) {
                if (items.isEmpty) {
                  return Center(child: Text(l10n.noPromosFound));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(_allPromosProvider),
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
                            ref.invalidate(_allPromosProvider);
                          }
                        },
                        // ⚠️ **Troisième appelant, et le compilateur seul l'a
                        // trouvé.** Cette liste sert TOUTES les promos, pas
                        // seulement la file : les quatre statuts y passent.
                        // C'est la raison d'avoir fait de l'état attendu un
                        // paramètre obligatoire plutôt qu'un nommé optionnel —
                        // un défaut ici aurait fait échouer en silence toute
                        // décision prise sur une promo non signalée.
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
