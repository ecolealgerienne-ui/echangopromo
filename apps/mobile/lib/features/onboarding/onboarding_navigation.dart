import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../providers/core_providers.dart';

/// Destination une fois la localisation accordée : la carte « autour de
/// moi », qui n'a d'intérêt qu'avec une position connue.
const kDestinationWithLocation = '/carte';

/// Destination quand la localisation est refusée ou reportée.
const kDestinationWithoutLocation = '/';

/// Demande la permission de localisation puis termine l'onboarding.
///
/// ⚠️ **C'est la SEULE sortie de `LocationPermissionScreen`.** Il a existé une
/// `skipLocationAndFinish`, qui terminait l'onboarding sans rien demander :
/// Apple l'a refusée le 2026-08-07 (5.1.1(iv), *« the user can close the
/// message and delay the permission request »*). Un message maison explique,
/// il ne décide pas — la seule décision est celle prise dans la boîte du
/// système. Ne pas la réintroduire.
///
/// L'écran d'explication est affiché **avant** cette demande, jamais l'inverse :
/// c'est ce qu'Apple autorise explicitement (*« provide more information about
/// why the app is requesting permission before the request appears »*), et un
/// refus sur la boîte native est définitif (`deniedForever` — plus aucun moyen
/// de la redemander, seulement d'ouvrir les réglages).
Future<void> requestLocationAndFinish(
    BuildContext context, WidgetRef ref) async {
  // Le store est résolu avant tout `await` : plus aucune lecture de `ref`
  // une fois le widget potentiellement démonté (audit règle #20).
  final store = ref.read(onboardingStoreProvider);

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  final granted = permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always;

  await store.markCompleted();

  if (!context.mounted) return;
  context.go(granted ? kDestinationWithLocation : kDestinationWithoutLocation);
}
