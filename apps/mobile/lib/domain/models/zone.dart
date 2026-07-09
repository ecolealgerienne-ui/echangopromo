/// Zone opérationnelle d'agent — distincte de `Commune` (référentiel
/// géographique), gérée exclusivement par l'admin (specs §3.4).
class Zone {
  const Zone({required this.id, required this.nom, this.description});

  factory Zone.fromJson(Map<String, dynamic> json) => Zone(
        id: json['id'] as String,
        nom: json['nom'] as String,
        description: json['description'] as String?,
      );

  final String id;
  final String nom;
  final String? description;
}
