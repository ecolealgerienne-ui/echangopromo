/// Entrée de la file de vérification registre admin — `GET
/// /admin/commercant/registre/queue`.
class RegistreItem {
  const RegistreItem({
    required this.id,
    required this.nom,
    required this.telephone,
    required this.registreUrl,
    required this.createdAt,
  });

  factory RegistreItem.fromJson(Map<String, dynamic> json) => RegistreItem(
        id: json['id'] as String,
        nom: json['nom'] as String,
        telephone: json['telephone'] as String,
        registreUrl: json['registreUrl'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final String id;
  final String nom;
  final String telephone;
  final String? registreUrl;
  final DateTime createdAt;
}
