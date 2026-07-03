class Agent {
  const Agent({required this.id, required this.nom, required this.email, this.zoneId});

  factory Agent.fromJson(Map<String, dynamic> json) => Agent(
        id: json['id'] as String,
        nom: json['nom'] as String,
        email: json['email'] as String,
        zoneId: json['zoneId'] as String?,
      );

  final String id;
  final String nom;
  final String email;
  final String? zoneId;
}
