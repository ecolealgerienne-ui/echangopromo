import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/enums/commercant_account_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/widgets/language_switcher_button.dart';

final zoneCommercesProvider =
    FutureProvider.autoDispose((ref) => ref.watch(agentApiProvider).zoneCommerces());

/// Liste des commerces de la zone de l'agent avec statut de tournée
/// (specs §3.3) : jamais visité / à jour / à relancer.
class ZoneCommercesScreen extends ConsumerWidget {
  const ZoneCommercesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final commercesAsync = ref.watch(zoneCommercesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.zoneTitle),
        actions: [
          const LanguageSwitcherButton(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (action) async {
              switch (action) {
                case 'logout':
                  await ref.read(authControllerProvider.notifier).logout();
                  if (context.mounted) context.go('/');
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'logout', child: Text(l10n.logoutTooltip)),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_business_outlined),
        label: Text(l10n.newCommercantLabel),
        onPressed: () async {
          final created = await context.push<bool>('/agent/commercant/new');
          if (created == true && context.mounted) {
            ref.invalidate(zoneCommercesProvider);
          }
        },
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(zoneCommercesProvider),
        child: commercesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(l10n.commonError(error.toString()))),
          data: (commerces) {
            if (commerces.isEmpty) {
              return Center(child: Text(l10n.zoneEmpty));
            }
            return ListView.builder(
              itemCount: commerces.length,
              itemBuilder: (context, index) {
                final entry = commerces[index];
                final commercant = entry.commercant;
                return ListTile(
                  title: Text(commercant.nom),
                  subtitle: Text(
                    [
                      if (commercant.adresse != null) commercant.adresse!,
                      visitStatusLabel(context, entry.visitStatus),
                    ].join(' · '),
                  ),
                  trailing: commercant.accountState == CommercantAccountState.creeAgent
                      ? Tooltip(
                          message: l10n.waitingActivationTooltip,
                          child: const Icon(Icons.hourglass_empty),
                        )
                      : null,
                  onTap: () => context.push(
                    '/agent/promo/new/${commercant.id}',
                    extra: commercant.categorie,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
