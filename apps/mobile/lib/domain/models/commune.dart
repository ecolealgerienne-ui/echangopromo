class Commune {
  const Commune({required this.id, required this.nom, required this.wilaya});

  factory Commune.fromJson(Map<String, dynamic> json) => Commune(
        id: json['id'] as String,
        nom: json['nom'] as String,
        wilaya: json['wilaya'] as String,
      );

  final String id;
  final String nom;
  final String wilaya;
}
