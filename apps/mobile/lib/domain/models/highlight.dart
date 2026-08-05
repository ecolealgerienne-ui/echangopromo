/// Une diapositive du bandeau « Top promos » de l'accueil.
///
/// Deux endpoints alimentent ce même modèle :
/// - `GET /highlight` (public) — ce que voit le client. [curated] vaut
///   `false` quand le backend est retombé sur le classement calculé
///   (meilleures réductions), faute de mise en avant admin exploitable ;
///   [id] est alors préfixé `auto-` et ne désigne aucune ligne modifiable.
/// - `GET /admin/highlight` (admin) — renseigne en plus [position],
///   [active], [imageKey], [promoPhotoUrl] et [promoVisible], nuls partout
///   ailleurs (même principe que `Promo.photoKeys`, réservé au
///   propriétaire).
class Highlight {
  const Highlight({
    required this.id,
    required this.curated,
    this.titre,
    this.sousTitre,
    this.imageUrl,
    this.promoId,
    this.promoDescription,
    this.prixAvant,
    this.prixApres,
    this.commercantNom,
    this.position,
    this.active,
    this.imageKey,
    this.promoPhotoUrl,
    this.promoVisible,
  });

  factory Highlight.fromJson(Map<String, dynamic> json) => Highlight(
        id: json['id'] as String,
        // Absent de la réponse admin : une ligne en base est curée par
        // définition.
        curated: json['curated'] as bool? ?? true,
        titre: json['titre'] as String?,
        sousTitre: json['sousTitre'] as String?,
        imageUrl: json['imageUrl'] as String?,
        promoId: json['promoId'] as String?,
        promoDescription: json['promoDescription'] as String?,
        prixAvant: json['prixAvant'] != null
            ? double.parse(json['prixAvant'].toString())
            : null,
        prixApres: json['prixApres'] != null
            ? double.parse(json['prixApres'].toString())
            : null,
        commercantNom: json['commercantNom'] as String?,
        position: json['position'] as int?,
        active: json['active'] as bool?,
        imageKey: json['imageKey'] as String?,
        promoPhotoUrl: json['promoPhotoUrl'] as String?,
        promoVisible: json['promoVisible'] as bool?,
      );

  final String id;
  final bool curated;

  /// Remplace la description de la promo à l'affichage quand l'admin en a
  /// saisi un.
  final String? titre;
  final String? sousTitre;

  /// Visuel effectif côté client : l'image importée par l'admin si elle
  /// existe, sinon la photo de la promo ciblée — l'arbitrage est fait côté
  /// backend, l'app n'a qu'à afficher.
  final String? imageUrl;

  final String? promoId;
  final String? promoDescription;
  final double? prixAvant;
  final double? prixApres;

  /// Nom du commerce de la promo ciblée — sert de sous-titre par défaut.
  /// Null sur un bandeau sans cible (image seule).
  final String? commercantNom;

  // --- Réservé à la vue admin ---

  final int? position;
  final bool? active;

  /// Clé S3 brute de l'image importée — permet à l'écran d'édition de
  /// renvoyer l'image inchangée sans la réuploader.
  final String? imageKey;

  /// Photo de la promo ciblée, indépendamment de l'image importée : l'écran
  /// admin doit pouvoir montrer ce qui serait affiché *sans* image dédiée.
  final String? promoPhotoUrl;

  /// `false` quand la promo ciblée n'est plus visible côté client (expirée,
  /// masquée, commerce suspendu) — la diapositive existe toujours mais ne
  /// s'affiche nulle part.
  final bool? promoVisible;

  /// Texte principal de la vignette.
  String? get displayTitre => titre ?? promoDescription;

  /// Texte secondaire — le nom du commerce sert de repli, c'est lui qui
  /// donne le contexte quand l'admin n'a saisi qu'un titre.
  String? get displaySousTitre => sousTitre ?? commercantNom;

  /// Le badge de réduction n'a de sens que sur une diapositive qui cible
  /// une promo réelle avec deux prix.
  bool get hasDiscount =>
      prixAvant != null && prixApres != null && prixAvant! > prixApres!;
}
