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
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/app_settings_actions.dart';
import '../../../app/theme.dart';
import '../../shared/widgets/status_chip.dart';
import '../providers/commercant_providers.dart';

// `myPromosProvider` vit désormais dans `providers/commercant_providers.dart` :
// le tableau de bord l'utilise aussi (règle d'audit #21).

/// Jusqu'à 5 promos actives simultanément (specs §3.2/§5.3). Workflow
/// brouillon → publiée → arrêtée, édition toujours possible quel que soit
/// le statut (specs §3.2).
class MyPromosScreen extends ConsumerWidget {
  const MyPromosScreen({super.key});

  Future<void> _editPromo(
      BuildContext context, WidgetRef ref, Promo promo) async {
    final updated =
        await context.push<bool>('/commercant/promos/new', extra: promo);
    if (updated == true && context.mounted) {
      ref.invalidate(myPromosProvider);
    }
  }

  Future<void> _publish(
      BuildContext context, WidgetRef ref, Promo promo) async {
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
    final activeCount =
        promosAsync.valueOrNull?.where((p) => p.isPublished).length ?? 0;
    final atCap = activeCount >= kMaxPromosActives;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myPromosTitle),
        actions: const [AppSettingsActions()],
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
        error: (error, _) => Center(child: ApiErrorText(error)),
        data: (promos) {
          if (promos.isEmpty) {
            return Center(child: Text(l10n.noPromosYet));
          }
          return Column(
            children: [
              // Le plafond rappelé en tête, comme sur le tableau de bord :
              // c'est ici qu'on décide d'arrêter une promo pour en publier
              // une autre, la contrainte doit être sous les yeux.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.activeCountLabel(activeCount),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    for (var i = 0; i < kMaxPromosActives; i++)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 4),
                        child: Container(
                          width: 14,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i < activeCount
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: promos.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final promo = promos[index];
                    final dateLabel = promo.dateFin != null
                        ? l10n.untilDate(dateFormat.format(promo.dateFin!))
                        : l10n.notPublishedYet;
                    final photo = promo.thumbnailUrl ?? promo.photoUrl;
                    // Décodage limité à la taille réellement affichée plutôt
                    // qu'à la résolution source de l'image.
                    final thumbCachePx =
                        (56 * MediaQuery.of(context).devicePixelRatio).round();

                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: photo == null
                                  ? Container(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: photo,
                                      fit: BoxFit.cover,
                                      memCacheWidth: thumbCachePx,
                                      errorWidget: (context, url, error) =>
                                          Container(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  promo.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                // Statut et échéance sur une ligne à part :
                                // en `title` d'un ListTile, la puce de statut
                                // rognait la description dès qu'elle
                                // dépassait quelques mots.
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    StatusChip(
                                      label: promoLifecycleLabel(
                                        context,
                                        promo.lifecycleStatus,
                                        isExpired: promo.isExpired,
                                      ),
                                      color: promoLifecycleColor(
                                        context,
                                        promo.lifecycleStatus,
                                        isExpired: promo.isExpired,
                                      ),
                                    ),
                                    Text(
                                      '$dateLabel · ${l10n.myPromosViewsCount(promo.viewCount ?? 0)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
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
                              PopupMenuItem(
                                  value: 'edit', child: Text(l10n.editItem)),
                              if (promo.isPublished)
                                PopupMenuItem(
                                    value: 'stop', child: Text(l10n.stopItem))
                              else
                                PopupMenuItem(
                                    value: 'publish',
                                    child: Text(l10n.publishLabel)),
                            ],
                          ),
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
