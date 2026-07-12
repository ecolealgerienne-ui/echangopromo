import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/registre_status.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/status_chip.dart';

final _commercantSearchProvider = StateProvider.autoDispose<String>((ref) => '');

/// Filtre "en attente de validation registre" — remplace l'ancienne file
/// dédiée (`/admin/registre`, retirée le 2026-07-11), la fiche commerçant
/// affiche désormais le registre et permet de le valider/rejeter.
final _registrePendingFilterProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Même pattern que `ModerationQueueScreen._inFlightProvider` (audit UX 2026-07-11).
final _inFlightProvider = StateProvider.autoDispose<Set<String>>((ref) => {});

final _commercantsProvider = FutureProvider.autoDispose((ref) {
  final search = ref.watch(_commercantSearchProvider);
  final pendingOnly = ref.watch(_registrePendingFilterProvider);
  return ref.watch(adminApiProvider).listCommercants(
        search: search,
        registreStatus: pendingOnly ? RegistreStatus.enAttente : null,
      );
});

/// Liste + recherche sur l'ensemble des commerçants (plan de correction,
/// Phase 2), avec filtre "en attente de validation registre".
class AdminCommercantsScreen extends ConsumerWidget {
  const AdminCommercantsScreen({super.key});

  Future<void> _confirmAndSuspend(BuildContext context, WidgetRef ref, String commercantId) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.suspendConfirmTitle),
        content: Text(l10n.suspendConfirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.suspendLabel)),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _act(
      context,
      ref,
      commercantId,
      () => ref.read(adminApiProvider).suspendCommercant(commercantId),
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    String commercantId,
    Future<void> Function() action,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    ref.read(_inFlightProvider.notifier).update((ids) => {...ids, commercantId});
    try {
      await action();
      ref.invalidate(_commercantsProvider);
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
      ref.read(_inFlightProvider.notifier).update((ids) => {...ids}..remove(commercantId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final commercantsAsync = ref.watch(_commercantsProvider);
    final pendingOnly = ref.watch(_registrePendingFilterProvider);
    final inFlight = ref.watch(_inFlightProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.commercantsLabel),
        actions: const [LanguageSwitcherButton()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => ref.read(_commercantSearchProvider.notifier).state = value,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilterChip(
                label: Text(l10n.pendingRegistreFilterLabel),
                selected: pendingOnly,
                onSelected: (v) => ref.read(_registrePendingFilterProvider.notifier).state = v,
              ),
            ),
          ),
          Expanded(
            child: commercantsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: ApiErrorText(error)),
              data: (items) {
                if (items.isEmpty) {
                  return Center(child: Text(l10n.noCommercantsFound));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(_commercantsProvider),
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        onTap: () async {
                          final changed = await context
                              .push<bool>('/admin/commercants/detail', extra: item);
                          if (changed == true) ref.invalidate(_commercantsProvider);
                        },
                        title: Text(item.nom),
                        // Statut visible d'un coup d'œil dans la liste — avant, seul
                        // "en attente" avait un indicateur, "validé"/"rejeté"/"suspendu"
                        // n'étaient visibles qu'en ouvrant la fiche détail (retour terrain
                        // 2026-07-12).
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(item.telephone),
                              if (item.registreStatus != null)
                                StatusChip(
                                  label: registreStatusLabel(context, item.registreStatus!),
                                  color: registreStatusColor(context, item.registreStatus!),
                                ),
                              if (item.suspended)
                                StatusChip(
                                  label: l10n.suspendedBadge,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                            ],
                          ),
                        ),
                        isThreeLine: item.registreStatus != null || item.suspended,
                        trailing: inFlight.contains(item.id)
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : item.suspended
                                ? TextButton(
                                    onPressed: () => _act(
                                      context,
                                      ref,
                                      item.id,
                                      () => ref.read(adminApiProvider).reactivateCommercant(item.id),
                                    ),
                                    child: Text(l10n.reactivateLabel),
                                  )
                                : TextButton(
                                    onPressed: () => _confirmAndSuspend(context, ref, item.id),
                                    child: Text(l10n.suspendLabel),
                                  ),
                        leading: item.suspended
                            ? Icon(Icons.block, color: Theme.of(context).colorScheme.error)
                            : const Icon(Icons.storefront_outlined),
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
