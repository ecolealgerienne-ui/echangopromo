import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/models/notification.dart' as domain;
import '../providers/notification_provider.dart';

class NotificationsPanel extends ConsumerWidget {
  const NotificationsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final controller = ref.watch(notificationControllerProvider);

    return notificationsAsync.when(
      data: (paginatedNotifications) {
        final notifications = paginatedNotifications.items;

        if (notifications.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Aucune notification',
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
                ref.invalidate(unreadNotificationCountProvider);
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, st) => Center(
        child: Text('Erreur : $error'),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({
    required this.notification,
    required this.onMarkAsRead,
  });

  final domain.Notification notification;
  final VoidCallback onMarkAsRead;

  Color _getIconColor(domain.NotificationType type) {
    switch (type) {
      case domain.NotificationType.promoWarned:
        return Colors.orange;
      case domain.NotificationType.promoHidden:
        return Colors.red;
      case domain.NotificationType.promoVerified:
        return Colors.green;
    }
  }

  IconData _getIcon(domain.NotificationType type) {
    switch (type) {
      case domain.NotificationType.promoWarned:
        return Icons.warning_rounded;
      case domain.NotificationType.promoHidden:
        return Icons.visibility_off_rounded;
      case domain.NotificationType.promoVerified:
        return Icons.check_circle_rounded;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Icon(
          _getIcon(notification.type),
          color: _getIconColor(notification.type),
        ),
        title: Text(notification.message),
        subtitle: Text(notification.formatDate(locale)),
        trailing: !notification.isRead
            ? IconButton(
                icon: const Icon(Icons.check),
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
