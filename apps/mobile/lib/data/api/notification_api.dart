import 'package:dio/dio.dart';
import '../../domain/models/notification.dart';

class PaginatedNotifications {
  final List<Notification> items;
  final int total;
  final int page;
  final int limit;

  PaginatedNotifications({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory PaginatedNotifications.fromJson(Map<String, dynamic> json) {
    return PaginatedNotifications(
      items: (json['items'] as List)
          .map((e) => Notification.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      limit: json['limit'] as int,
    );
  }
}

class NotificationApi {
  NotificationApi(this._dio);

  final Dio _dio;

  /// Récupère les notifications non lues de l'utilisateur
  Future<PaginatedNotifications> listUnread({int page = 1, int limit = 20}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/notifications/unread',
      queryParameters: {'page': page, 'limit': limit},
    );
    return PaginatedNotifications.fromJson(response.data!);
  }

  /// Historique complet (lues + non lues)
  Future<PaginatedNotifications> listAll({int page = 1, int limit = 20}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/notifications',
      queryParameters: {'page': page, 'limit': limit},
    );
    return PaginatedNotifications.fromJson(response.data!);
  }

  /// Compte les notifications non lues (pour un badge)
  Future<int> countUnread() async {
    final response = await _dio.get<Map<String, dynamic>>('/notifications/unread/count');
    return response.data!['count'] as int;
  }

  /// Marque une notification comme lue
  Future<void> markAsRead(String notificationId) async {
    await _dio.post<void>('/notifications/$notificationId/read');
  }

  /// Marque toutes les notifications comme lues
  Future<void> markAllAsRead() async {
    await _dio.post<void>('/notifications/read-all');
  }
}
