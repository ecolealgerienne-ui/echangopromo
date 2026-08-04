import '../../../domain/enums/categorie.dart';

/// Chemin du visuel d'une catégorie. Le nom de fichier suit la valeur de
/// l'enum (`alimentation.jpg`, `vetements_textile.jpg`...) : ajouter une
/// catégorie côté backend ne demande alors que de déposer un fichier, sans
/// toucher au code d'affichage.
///
/// Le fichier peut ne pas exister — c'est le cas par défaut. L'appelant doit
/// prévoir un repli (`Image.asset(..., errorBuilder:)` retombe sur l'icône
/// Material) : l'app doit rester utilisable avant que les visuels ne soient
/// fournis. Voir `assets/images/categories/README.md`.
String categorieAssetPath(Categorie categorie) =>
    'assets/images/categories/${categorie.value}.jpg';
