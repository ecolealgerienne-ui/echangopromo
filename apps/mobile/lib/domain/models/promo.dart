class Promo {
  const Promo({
    required this.id,
    required this.commercantId,
    required this.produit,
    required this.prixAvant,
    required this.prixApres,
    required this.categorie,
    required this.dateFin,
    required this.photoUrl,
  });

  factory Promo.fromJson(Map<String, dynamic> json) => Promo(
        id: json['id'] as String,
        commercantId: json['commercantId'] as String,
        produit: json['produit'] as String,
        prixAvant: (json['prixAvant'] as num).toDouble(),
        prixApres: (json['prixApres'] as num).toDouble(),
        categorie: json['categorie'] as String,
        dateFin: DateTime.parse(json['dateFin'] as String),
        photoUrl: json['photoUrl'] as String,
      );

  final String id;
  final String commercantId;
  final String produit;
  final double prixAvant;
  final double prixApres;
  final String categorie;
  final DateTime dateFin;
  final String photoUrl;
}
