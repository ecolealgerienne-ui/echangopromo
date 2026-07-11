import 'package:url_launcher/url_launcher.dart';

/// Ouvre l'itinéraire vers un point GPS dans l'app Google Maps du
/// téléphone — dupliqué à l'identique entre la fiche promo client et la
/// fiche commerçant admin (CLAUDE.md règle #21).
Future<void> openMapsAt(double latitude, double longitude) async {
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$latitude,$longitude');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
