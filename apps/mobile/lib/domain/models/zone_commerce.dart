import 'commercant.dart';

/// Commerce de la zone d'un agent avec son statut de tournée (specs §3.3).
class ZoneCommerce {
  const ZoneCommerce({required this.commercant, required this.visitStatus});

  factory ZoneCommerce.fromJson(Map<String, dynamic> json) => ZoneCommerce(
        commercant: Commercant.fromJson(json),
        visitStatus: json['visitStatus'] as String,
      );

  final Commercant commercant;
  final String visitStatus;
}
