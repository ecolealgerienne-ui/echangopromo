import 'commercant.dart';

/// Commerce d'une des communes couvertes par un agent, avec son statut de
/// tournée (specs §3.3).
class CommuneCommerce {
  const CommuneCommerce({required this.commercant, required this.visitStatus});

  factory CommuneCommerce.fromJson(Map<String, dynamic> json) => CommuneCommerce(
        commercant: Commercant.fromJson(json),
        visitStatus: json['visitStatus'] as String,
      );

  final Commercant commercant;
  final String visitStatus;
}
