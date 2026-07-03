class Commercant {
  const Commercant({
    required this.id,
    required this.nom,
    required this.adresse,
    required this.categorie,
    required this.communeId,
  });

  factory Commercant.fromJson(Map<String, dynamic> json) => Commercant(
        id: json['id'] as String,
        nom: json['nom'] as String,
        adresse: json['adresse'] as String,
        categorie: json['categorie'] as String,
        communeId: json['communeId'] as String,
      );

  final String id;
  final String nom;
  final String adresse;
  final String categorie;
  final String communeId;
}
