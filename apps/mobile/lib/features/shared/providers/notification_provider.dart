import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/notification_api.dart';
import '../../../domain/models/notification.dart';
import '../../../providers/core_providers.dart';

/// Liste des notifications non lues (paginées)
final notificationsProvider = FutureProvider.autoDispose(
  (ref) async {
    final api = ref.watch(notificationApiProvider);
    return api.listUnread(page: 1, limit: 50);
  },
);

/// Compteur des notifications non lues (pour un badge)
final unreadNotificationCountProvider = FutureProvider.autoDispose(
  (ref) async {
    final api = ref.watch(notificationApiProvider);
    return api.countUnread();
  },
);

/// Contrôleur pour les actions sur les notifications
class NotificationController {
  NotificationController(this._notificationApi);

  final NotificationApi _notificationApi;

  Future<void> markAsRead(String notificationId) async {
    await _notificationApi.markAsRead(notificationId);
  }

  Future<void> markAllAsRead() async {
    await _notificationApi.markAllAsRead();
  }
}

final notificationControllerProvider = Provider(
  (ref) => NotificationController(ref.watch(notificationApiProvider)),
);
