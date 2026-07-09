import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/language_switcher_button.dart';

final _registreQueueProvider =
    FutureProvider.autoDispose((ref) => ref.watch(adminApiProvider).registreQueue());

/// File des vérifications registre en attente (specs §3.4) : un commerçant
/// a soumis une preuve de registre du commerce, à valider ou rejeter.
class RegistreQueueScreen extends ConsumerWidget {
  const RegistreQueueScreen({super.key});

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await action();
      ref.invalidate(_registreQueueProvider);
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
    final queueAsync = ref.watch(_registreQueueProvider);
    final api = ref.read(adminApiProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.registreLabel),
        actions: const [LanguageSwitcherButton()],
      ),
      body: queueAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.commonError(error.toString()))),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(l10n.noRegistreItems));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_registreQueueProvider),
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(item.nom, style: Theme.of(context).textTheme.titleMedium),
                        Text(item.telephone),
                        if (item.registreUrl != null) ...[
                          const SizedBox(height: 8),
                          AspectRatio(
                            aspectRatio: 4 / 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(item.registreUrl!, fit: BoxFit.cover),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    _act(context, ref, () => api.rejeterRegistre(item.id)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(context).colorScheme.error,
                                ),
                                child: Text(l10n.rejeterLabel),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () =>
                                    _act(context, ref, () => api.validerRegistre(item.id)),
                                child: Text(l10n.validerLabel),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
