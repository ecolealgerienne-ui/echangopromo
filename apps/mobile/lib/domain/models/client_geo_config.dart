/// Repères géographiques servis par `GET /promo/config`.
///
/// ⚠️ **Aucune de ces valeurs n'a de jumelle compilée dans l'app.** Le mobile
/// n'a pas de `.env` : un `--dart-define` serait figé au build, et `CLAUDE.md`
/// documente qu'il se perd silencieusement selon la façon dont `flutter` est
/// lancé. Le seul repli local est le point de premier lancement hors ligne
/// (`kPointDeRepliHorsLigne`), volontairement unique dans tout le dépôt.
///
/// ⚠️ Et aucune de ces valeurs ne doit être réécrite dans une chaîne traduite :
/// « dans un rayon de 5 km » figé dans les `.arb` reproduirait le défaut
/// « Plafond de 5 promos atteint », qui annonçait 5 à une app qui en autorisait
/// déjà 8 (règle #32). Les libellés prennent un placeholder.
class ClientGeoConfig {
  const ClientGeoConfig({
    required this.defaultLatitude,
    required this.defaultLongitude,
    required this.defaultRadiusKm,
    required this.maxRadiusKm,
  });

  factory ClientGeoConfig.fromJson(Map<String, dynamic> json) =>
      ClientGeoConfig(
        // `as num` puis `.toDouble()` : le serveur passe par `configNumber`,
        // donc ce sont bien des nombres — mais une valeur entière arrive en
        // `int` en JSON, et `as double` planterait dessus.
        defaultLatitude: (json['defaultLatitude'] as num).toDouble(),
        defaultLongitude: (json['defaultLongitude'] as num).toDouble(),
        defaultRadiusKm: (json['defaultRadiusKm'] as num).toDouble(),
        maxRadiusKm: (json['maxRadiusKm'] as num).toDouble(),
      );

  final double defaultLatitude;
  final double defaultLongitude;
  final double defaultRadiusKm;
  final double maxRadiusKm;
}
