import '../enums/api_enum.dart';

/// Miroir de `NotificationType` (`apps/backend/src/notification/entities/
/// notification.entity.ts`). Tenu par `tool/check_enums.dart`.
enum NotificationType {
  promoWarned('promo_warned'),
  promoHidden('promo_hidden'),
  promoVerified('promo_verified'),
  promoExpiringSoon('promo_expiring_soon'),
  registreValidated('registre_validated'),
  registreRejected('registre_rejected'),
  profileValidated('profile_validated'),

  /// Repli explicite pour une valeur ajoutée côté backend et pas encore
  /// miroitée ici. **Ne correspond à aucune valeur serveur** — d'où la
  /// chaîne sentinelle, qu'aucun `type` réel ne peut porter, et l'exclusion
  /// déclarée dans `tool/check_enums.dart`.
  ///
  /// Avant, `fromValue` était un `firstWhere` **sans `orElse`** : il levait.
  /// Une seule notification d'un type inconnu faisait donc basculer en erreur
  /// `notificationsProvider`, `notificationHistoryProvider` et le tableau de
  /// bord commerçant — **toutes** les notifications perdues à cause d'une
  /// ligne, alors que le backend a déjà ajouté quatre valeurs à cet enum en
  /// trois migrations (revue 2026-08-05, règle #19). Le `message` serveur
  /// reste affiché : une notification inconnue s'affiche, avec une icône
  /// neutre, au lieu de faire disparaître les autres.
  unknown('__unknown__');

  const NotificationType(this.value);
  final String value;

  static NotificationType fromValue(String value) => fromApiValue(
        valeurs: NotificationType.values,
        valeurDe: (e) => e.value,
        recu: value,
        repli: NotificationType.unknown,
        enumeration: 'NotificationType',
      );
}

class Notification {
  final String id;
  final NotificationType type;

  /// Phrase composée par le serveur, **toujours en français** — n'est plus
  /// affichée que si le type est inconnu du miroir (voir [NotificationType]).
  /// Le rendu normal passe par `notificationLabel`, à partir de [type] et
  /// [promoDescription].
  final String message;
  final String? promoId;
  final String? promoDescription;
  final DateTime createdAt;
  final DateTime? readAt;

  Notification({
    required this.id,
    required this.type,
    required this.message,
    this.promoId,
    this.promoDescription,
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
      promoDescription: json['promoDescription'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      readAt: json['readAt'] != null
          ? DateTime.parse(json['readAt'] as String)
          : null,
    );
  }
}
