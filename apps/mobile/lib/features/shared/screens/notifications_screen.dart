import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/notification_provider.dart';
import '../widgets/notifications_panel.dart';

/// Écran de notifications commun aux rôles commerçant/agent/admin — le rôle
/// du JWT détermine côté backend quel destinataire est interrogé
/// (voir NotificationController.roleToRecipientType).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.watch(notificationControllerProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.notificationsTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: l10n.markAllReadLabel,
              onPressed: () async {
                await controller.markAllAsRead();
                ref.invalidate(notificationsProvider);
                ref.invalidate(notificationHistoryProvider);
                ref.invalidate(unreadNotificationCountProvider);
              },
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.unreadNotificationsTab),
              Tab(text: l10n.historyNotificationsTab),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(notificationsProvider);
                ref.invalidate(unreadNotificationCountProvider);
              },
              child: const NotificationsPanel(),
            ),
            RefreshIndicator(
              onRefresh: () async => ref.invalidate(notificationHistoryProvider),
              child: const NotificationsPanel(history: true),
            ),
          ],
        ),
      ),
    );
  }
}
