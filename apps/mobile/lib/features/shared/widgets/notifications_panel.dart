import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/models/notification.dart' as domain;
import '../../../l10n/app_localizations.dart';
import '../l10n/enum_labels.dart';
import '../providers/notification_provider.dart';

class NotificationsPanel extends ConsumerWidget {
  const NotificationsPanel({super.key, this.history = false});

  /// `false` = seulement les non lues (comportement historique). `true` =
  /// historique complet (lues + non lues), voir `notificationHistoryProvider`.
  final bool history;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final notificationsAsync =
        ref.watch(history ? notificationHistoryProvider : notificationsProvider);
    final controller = ref.watch(notificationControllerProvider);

    return notificationsAsync.when(
      data: (paginatedNotifications) {
        final notifications = paginatedNotifications.items;

        if (notifications.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.noNotifications,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: notifications.length,
          itemBuilder: (context, index) {
            final notification = notifications[index];
            return _NotificationTile(
              notification: notification,
              onMarkAsRead: () async {
                await controller.markAsRead(notification.id);
                ref.invalidate(notificationsProvider);
                ref.invalidate(notificationHistoryProvider);
                ref.invalidate(unreadNotificationCountProvider);
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, st) => Center(
        child: Text(l10n.commonError(error.toString())),
      ),
    );
  }
}

/// Couleur/icône par type — partagées entre le panneau plein écran et le
/// bandeau du dashboard (CLAUDE.md #21 : extraire dès la 2e duplication).
Color notificationIconColor(domain.NotificationType type) {
  switch (type) {
    case domain.NotificationType.promoWarned:
      return Colors.orange;
    case domain.NotificationType.promoHidden:
      return Colors.red;
    case domain.NotificationType.promoVerified:
      return Colors.green;
    case domain.NotificationType.promoExpiringSoon:
      return Colors.blue;
  }
}

IconData notificationIcon(domain.NotificationType type) {
  switch (type) {
    case domain.NotificationType.promoWarned:
      return Icons.warning_rounded;
    case domain.NotificationType.promoHidden:
      return Icons.visibility_off_rounded;
    case domain.NotificationType.promoVerified:
      return Icons.check_circle_rounded;
    case domain.NotificationType.promoExpiringSoon:
      return Icons.schedule_rounded;
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({
    required this.notification,
    required this.onMarkAsRead,
  });

  final domain.Notification notification;
  final VoidCallback onMarkAsRead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Icon(
          notificationIcon(notification.type),
          color: notificationIconColor(notification.type),
        ),
        title: Text(notification.message),
        subtitle: Text(notificationRelativeDate(context, notification.createdAt)),
        trailing: !notification.isRead
            ? IconButton(
                icon: const Icon(Icons.check),
                tooltip: l10n.markAsReadTooltip,
                onPressed: onMarkAsRead,
              )
            : null,
        tileColor: notification.isRead ? null : Colors.grey.shade100,
      ),
    );
  }
}

/// Badge affichant le nombre de notifications non lues
class NotificationBadge extends ConsumerWidget {
  const NotificationBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(unreadNotificationCountProvider);

    return countAsync.when(
      data: (count) => count > 0
          ? Badge(
              label: Text('$count'),
              child: const Icon(Icons.notifications),
            )
          : const Icon(Icons.notifications),
      loading: () => const Icon(Icons.notifications),
      error: (_, __) => const Icon(Icons.notifications),
    );
  }
}
