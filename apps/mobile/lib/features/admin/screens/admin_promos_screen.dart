import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/auth_session.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../widgets/promo_moderation_tile.dart';

final _searchProvider = StateProvider.autoDispose<String>((ref) => '');

final _allPromosProvider = FutureProvider.autoDispose((ref) {
  final search = ref.watch(_searchProvider);
  return ref.watch(adminApiProvider).listAllPromos(search: search);
});

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
    Future<void> Function() action,
  ) async {
    final l10n = AppLocalizations.of(context)!;
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
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final promosAsync = ref.watch(_allPromosProvider);
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
          Expanded(
            child: promosAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(l10n.commonError(error.toString()))),
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
                        onTap: () async {
                          final changed = await context.push<bool>(detailPath, extra: item);
                          if (changed == true) ref.invalidate(_allPromosProvider);
                        },
                        onMasquer: () => _act(context, ref, () => api.masquerPromo(item.id)),
                        onVerifierOk: () => _act(context, ref, () => api.verifierOkPromo(item.id)),
                        onAvertir: () => _act(context, ref, () => api.avertirPromo(item.id)),
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
