import 'package:url_launcher/url_launcher.dart';

/// Ouvre l'app téléphone du système sur le numéro donné (tap-pour-appeler).
Future<void> callPhone(String telephone) async {
  final uri = Uri(scheme: 'tel', path: telephone);
  await launchUrl(uri);
}
