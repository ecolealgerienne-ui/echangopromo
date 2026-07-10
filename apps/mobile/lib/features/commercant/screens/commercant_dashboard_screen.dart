import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';
import '../../shared/providers/notification_provider.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/notifications_panel.dart';

/// Dashboard commerçant (specs §3.2) : donne une raison concrète de revenir
/// régulièrement dans l'app, en plus de l'obligation de republication.
class CommercantDashboardScreen extends ConsumerWidget {
  const CommercantDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final meAsync = ref.watch(_meProvider);
    final statsAsync = ref.watch(_statsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myCommercantSpaceTitle),
        actions: [
          const LanguageSwitcherButton(),
          IconButton(
            icon: const NotificationBadge(),
            tooltip: l10n.notificationsTooltip,
            onPressed: () => context.push('/commercant/notifications'),
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
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_meProvider);
          ref.invalidate(_statsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _UnreadNotificationsBanner(),
            meAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text(l10n.commonError(error.toString())),
              data: (commercant) => Text(
                commercant.nom,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text(l10n.profileViewsLabel),
                trailing: statsAsync.when(
                  loading: () => const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => const Text('-'),
                  data: (count) => Text('$count', style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.local_offer_outlined),
              label: Text(l10n.myPromosLabel),
              onPressed: () => context.push('/commercant/promos'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.storefront_outlined),
              label: Text(l10n.editProfileLabel),
              onPressed: () async {
                final updated = await context.push<bool>('/commercant/profile/edit');
                if (updated == true) {
                  ref.invalidate(_meProvider);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

final _meProvider = FutureProvider.autoDispose((ref) => ref.watch(commercantApiProvider).me());
final _statsProvider =
    FutureProvider.autoDispose((ref) => ref.watch(commercantApiProvider).dashboardProfileViewCount());

/// Alertes de modération affichées directement sur le dashboard — pas
/// seulement derrière l'icône cloche, pour que le commerçant ne les
/// découvre pas seulement s'il pense à cliquer dessus. Reste affichée tant
/// que le commerçant n'a pas marqué la notification comme lue (aucune
/// republication automatique de la promo).
class _UnreadNotificationsBanner extends ConsumerWidget {
  const _UnreadNotificationsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final notificationsAsync = ref.watch(notificationsProvider);

    return notificationsAsync.maybeWhen(
      data: (paginated) {
        final unread = paginated.items;
        if (unread.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final notification in unread)
              Card(
                color: notificationIconColor(notification.type).withValues(alpha: 0.1),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    notificationIcon(notification.type),
                    color: notificationIconColor(notification.type),
                  ),
                  title: Text(notification.message),
                  trailing: TextButton(
                    onPressed: () => context.push('/commercant/promos'),
                    child: Text(l10n.reviewPromoCta),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
