class Admin {
  const Admin({required this.id, required this.nom, required this.email});

  factory Admin.fromJson(Map<String, dynamic> json) => Admin(
        id: json['id'] as String,
        nom: json['nom'] as String,
        email: json['email'] as String,
      );

  final String id;
  final String nom;
  final String email;
}
