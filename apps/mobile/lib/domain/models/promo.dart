import '../enums/categorie.dart';

class Promo {
  const Promo({
    required this.id,
    required this.commercantId,
    required this.produit,
    required this.prixAvant,
    required this.prixApres,
    required this.categorie,
    required this.dateFin,
    required this.status,
    required this.photoUrl,
    this.viewCount,
  });

  factory Promo.fromJson(Map<String, dynamic> json) => Promo(
        id: json['id'] as String,
        commercantId: json['commercantId'] as String,
        produit: json['produit'] as String,
        prixAvant: double.parse(json['prixAvant'].toString()),
        prixApres: double.parse(json['prixApres'].toString()),
        categorie: Categorie.fromValue(json['categorie'] as String),
        dateFin: DateTime.parse(json['dateFin'] as String),
        status: json['status'] as String,
        photoUrl: json['photoUrl'] as String?,
        viewCount: json['viewCount'] as int?,
      );

  final String id;
  final String commercantId;
  final String produit;
  final double prixAvant;
  final double prixApres;
  final Categorie categorie;
  final DateTime dateFin;
  final String status;
  final String? photoUrl;
  final int? viewCount;

  bool get isExpired => dateFin.isBefore(DateTime.now());
}
