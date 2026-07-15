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
import '../widgets/commune_filter_bar.dart';
import '../widgets/promo_moderation_tile.dart';

final _searchProvider = StateProvider.autoDispose<String>((ref) => '');

/// Filtre commune/wilaya (retour terrain 2026-07-14), en plus de la recherche.
final _wilayaFilterProvider = StateProvider.autoDispose<String?>((ref) => null);
final _communeFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

final _allPromosProvider = FutureProvider.autoDispose((ref) {
  final search = ref.watch(_searchProvider);
  final wilaya = ref.watch(_wilayaFilterProvider);
  final communeId = ref.watch(_communeFilterProvider);
  return ref.watch(adminApiProvider).listAllPromos(search: search, wilaya: wilaya, communeId: communeId);
});

/// Même pattern que `ModerationQueueScreen._inFlightProvider` (audit UX 2026-07-11).
final _inFlightProvider = StateProvider.autoDispose<Set<String>>((ref) => {});

/// Vue globale de toutes les promos (plan de correction, Phase 2) —
/// contrairement à la file de modération, pas seulement celles ayant
/// atteint le seuil de signalements. Accessible admin + agent (le rôle du
/// JWT détermine côté backend le périmètre — global pour l'admin, scopé
/// aux communes de l'agent sinon, voir AdminController.scopedCommuneIds).
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
    final promosAsync = ref.watch(_allPromosProvider);
    final inFlight = ref.watch(_inFlightProvider);
    final api = ref.read(adminApiProvider);
    final role = ref.read(authControllerProvider).value?.role;
    final detailPath = role == AppRole.agent ? '/agent/promo-detail' : '/admin/promo-detail';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.allPromosLabel),
        actions: const [LanguageSwitcherButton()],
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
              onChanged: (value) => ref.read(_searchProvider.notifier).state = value,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: CommuneFilterBar(
              wilaya: ref.watch(_wilayaFilterProvider),
              communeId: ref.watch(_communeFilterProvider),
              onWilayaChanged: (value) => ref.read(_wilayaFilterProvider.notifier).state = value,
              onCommuneChanged: (value) => ref.read(_communeFilterProvider.notifier).state = value,
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
                          final changed = await context.push<bool>(detailPath, extra: item);
                          if (changed == true) ref.invalidate(_allPromosProvider);
                        },
                        onMasquer: () => _act(context, ref, item.id, () => api.masquerPromo(item.id)),
                        onVerifierOk: () =>
                            _act(context, ref, item.id, () => api.verifierOkPromo(item.id)),
                        onAvertir: () => _act(context, ref, item.id, () => api.avertirPromo(item.id)),
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
