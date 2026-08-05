import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../data/api/notification_api.dart';
import '../../../providers/core_providers.dart';

/// Liste des notifications non lues (paginées)
final notificationsProvider = FutureProvider.autoDispose(
  (ref) async {
    final api = ref.watch(notificationApiProvider);
    return api.listUnread(page: 1, limit: 50);
  },
);

/// Historique complet (lues + non lues)
final notificationHistoryProvider = FutureProvider.autoDispose(
  (ref) async {
    final api = ref.watch(notificationApiProvider);
    return api.listAll(page: 1, limit: 50);
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

  /// ⚠️ **`NOTIFICATION_NOT_FOUND` n'est pas une erreur pour l'appelant.**
  ///
  /// Depuis le 2026-08-05 le serveur refuse un marquage qui ne modifie aucune
  /// ligne — notification appartenant à quelqu'un d'autre, ou effacée par la
  /// purge de rétention (il rendait auparavant `201` sur un geste sans effet).
  /// Côté écran, l'état visé est atteint dans les deux cas : elle n'est plus
  /// là. Laisser remonter ce refus afficherait une erreur pour un tap qui a
  /// abouti du point de vue de l'utilisateur.
  ///
  /// Tout autre refus remonte : lui, l'appelant doit le voir.
  Future<void> markAsRead(String notificationId) async {
    try {
      await _notificationApi.markAsRead(notificationId);
    } on ApiException catch (e) {
      if (e.code != 'NOTIFICATION_NOT_FOUND') rethrow;
    }
  }

  Future<void> markAllAsRead() async {
    await _notificationApi.markAllAsRead();
  }
}

final notificationControllerProvider = Provider(
  (ref) => NotificationController(ref.watch(notificationApiProvider)),
);
