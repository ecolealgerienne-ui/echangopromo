import '../enums/categorie.dart';

class Commercant {
  const Commercant({
    required this.id,
    required this.nom,
    required this.adresse,
    required this.categorie,
    required this.communeId,
    this.accountState,
    this.telephone,
  });

  factory Commercant.fromJson(Map<String, dynamic> json) => Commercant(
        id: json['id'] as String,
        nom: json['nom'] as String,
        adresse: json['adresse'] as String,
        categorie: Categorie.fromValue(json['categorie'] as String),
        communeId: json['communeId'] as String,
        accountState: json['accountState'] as String?,
        telephone: json['telephone'] as String?,
      );

  final String id;
  final String nom;
  final String adresse;
  final Categorie categorie;
  final String communeId;
  final String? accountState;
  final String? telephone;
}
