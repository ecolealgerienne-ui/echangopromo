import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/enums/commercant_account_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';

final communeCommercesProvider =
    FutureProvider.autoDispose((ref) => ref.watch(agentApiProvider).communesCommerces());

/// Liste des commerces des communes de l'agent avec statut de tournée
/// (specs §3.3) : jamais visité / à jour / à relancer.
class CommuneCommercesScreen extends ConsumerWidget {
  const CommuneCommercesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final commercesAsync = ref.watch(communeCommercesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l10n.backToHomeTooltip,
          onPressed: () => context.go('/'),
        ),
        title: Text(l10n.myCommunesTitle),
        actions: [
          const LanguageSwitcherButton(),
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: l10n.moderationLabel,
            onPressed: () => context.push('/agent/moderation'),
          ),
          IconButton(
            icon: const Icon(Icons.local_offer_outlined),
            tooltip: l10n.allPromosLabel,
            onPressed: () => context.push('/agent/promos'),
          ),
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
            ref.invalidate(communeCommercesProvider);
          }
        },
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(communeCommercesProvider),
        child: commercesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: ApiErrorText(error)),
          data: (commerces) {
            if (commerces.isEmpty) {
              return Center(child: Text(l10n.communesEmptyForAgent));
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
