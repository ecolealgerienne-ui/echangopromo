import 'commune.dart';

class Agent {
  const Agent({
    required this.id,
    required this.nom,
    required this.email,
    this.communes = const [],
  });

  factory Agent.fromJson(Map<String, dynamic> json) => Agent(
        id: json['id'] as String,
        nom: json['nom'] as String,
        email: json['email'] as String,
        communes: (json['communes'] as List<dynamic>? ?? [])
            .map((e) => Commune.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String nom;
  final String email;
  final List<Commune> communes;
}
