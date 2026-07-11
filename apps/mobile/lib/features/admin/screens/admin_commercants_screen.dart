import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/language_switcher_button.dart';

final _commercantSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final _commercantsProvider = FutureProvider.autoDispose((ref) {
  final search = ref.watch(_commercantSearchProvider);
  return ref.watch(adminApiProvider).listCommercants(search: search);
});

/// Liste + recherche sur l'ensemble des commerçants (plan de correction,
/// Phase 2) — jusqu'ici seule la file registre (en attente) était
/// consultable côté admin.
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
    if (confirmed != true) return;
    await _act(context, ref, () => ref.read(adminApiProvider).suspendCommercant(commercantId));
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    final l10n = AppLocalizations.of(context)!;
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
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final commercantsAsync = ref.watch(_commercantsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.commercantsLabel),
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
              onChanged: (value) => ref.read(_commercantSearchProvider.notifier).state = value,
            ),
          ),
          Expanded(
            child: commercantsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(l10n.commonError(error.toString()))),
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
                        title: Text(item.nom),
                        subtitle: Text(item.telephone),
                        trailing: item.suspended
                            ? TextButton(
                                onPressed: () => _act(
                                  context,
                                  ref,
                                  () => ref.read(adminApiProvider).reactivateCommercant(item.id),
                                ),
                                child: Text(l10n.reactivateLabel),
                              )
                            : TextButton(
                                onPressed: () => _confirmAndSuspend(context, ref, item.id),
                                child: Text(l10n.suspendLabel),
                              ),
                        leading: item.suspended
                            ? const Icon(Icons.block, color: Colors.red)
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
