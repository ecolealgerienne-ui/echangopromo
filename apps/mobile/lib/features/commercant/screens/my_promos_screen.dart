import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/promo.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/widgets/language_switcher_button.dart';

final myPromosProvider = FutureProvider.autoDispose((ref) => ref.watch(promoApiProvider).listMine());

/// Jusqu'à 5 promos actives simultanément (specs §3.2/§5.3). Workflow
/// brouillon → publiée → arrêtée, édition toujours possible quel que soit
/// le statut (specs §3.2).
class MyPromosScreen extends ConsumerWidget {
  const MyPromosScreen({super.key});

  Future<void> _editPromo(BuildContext context, WidgetRef ref, Promo promo) async {
    final updated = await context.push<bool>('/commercant/promos/new', extra: promo);
    if (updated == true && context.mounted) {
      ref.invalidate(myPromosProvider);
    }
  }

  Future<void> _publish(BuildContext context, WidgetRef ref, Promo promo) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref.read(promoApiProvider).publish(promo.id);
      ref.invalidate(myPromosProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(extractApiErrorMessage(
              error,
              fallback: l10n.publishFailed,
              locale: Localizations.localeOf(context),
            )),
          ),
        );
      }
    }
  }

  Future<void> _stop(BuildContext context, WidgetRef ref, Promo promo) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref.read(promoApiProvider).stop(promo.id);
      ref.invalidate(myPromosProvider);
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
    final promosAsync = ref.watch(myPromosProvider);
    final dateFormat = DateFormat('dd/MM/yyyy');
    final activeCount = promosAsync.valueOrNull?.where((p) => p.isPublished).length ?? 0;
    final atCap = activeCount >= 5;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myPromosTitle),
        actions: const [LanguageSwitcherButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(atCap ? l10n.capReachedLabel : l10n.newPromoTitle),
        onPressed: atCap
            ? null
            : () async {
                final created =
                    await context.push<bool>('/commercant/promos/new');
                if (created == true && context.mounted) {
                  ref.invalidate(myPromosProvider);
                }
              },
      ),
      body: promosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.commonError(error.toString()))),
        data: (promos) {
          if (promos.isEmpty) {
            return Center(child: Text(l10n.noPromosYet));
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l10n.activeCountLabel(activeCount)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: promos.length,
                  itemBuilder: (context, index) {
                    final promo = promos[index];
                    final dateLabel = promo.dateFin != null
                        ? l10n.untilDate(dateFormat.format(promo.dateFin!))
                        : l10n.notPublishedYet;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            promo.photoUrl != null ? CachedNetworkImageProvider(promo.photoUrl!) : null,
                      ),
                      title: Text(promo.description),
                      subtitle: Text(
                        '${promoLifecycleLabel(context, promo.lifecycleStatus, isExpired: promo.isExpired)}'
                        ' · $dateLabel · ${l10n.myPromosViewsCount(promo.viewCount ?? 0)}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          switch (action) {
                            case 'edit':
                              _editPromo(context, ref, promo);
                            case 'publish':
                              _publish(context, ref, promo);
                            case 'stop':
                              _stop(context, ref, promo);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(value: 'edit', child: Text(l10n.editItem)),
                          if (promo.isPublished)
                            PopupMenuItem(value: 'stop', child: Text(l10n.stopItem))
                          else
                            PopupMenuItem(value: 'publish', child: Text(l10n.publishLabel)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
