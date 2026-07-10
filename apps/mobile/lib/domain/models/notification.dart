import 'package:flutter/material.dart' show Locale;
import 'package:intl/intl.dart';

enum NotificationType {
  promoWarned('promo_warned'),
  promoHidden('promo_hidden'),
  promoVerified('promo_verified');

  const NotificationType(this.value);
  final String value;

  static NotificationType fromValue(String value) =>
      NotificationType.values.firstWhere((e) => e.value == value);
}

class Notification {
  final String id;
  final NotificationType type;
  final String message;
  final String? promoId;
  final DateTime createdAt;
  final DateTime? readAt;

  Notification({
    required this.id,
    required this.type,
    required this.message,
    this.promoId,
    required this.createdAt,
    this.readAt,
  });

  bool get isRead => readAt != null;

  factory Notification.fromJson(Map<String, dynamic> json) {
    return Notification(
      id: json['id'] as String,
      type: NotificationType.fromValue(json['type'] as String),
      message: json['message'] as String,
      promoId: json['promoId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      readAt: json['readAt'] != null
          ? DateTime.parse(json['readAt'] as String)
          : null,
    );
  }

  String formatDate(Locale locale) {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inHours < 1) return 'Il y a ${diff.inMinutes}m';
    if (diff.inDays < 1) return 'Il y a ${diff.inHours}h';
    if (diff.inDays == 1) return 'Hier';

    return DateFormat('d MMM', 'fr_FR').format(createdAt);
  }
}
