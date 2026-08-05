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
/// L'écran maison est affiché **avant** cette demande, jamais l'inverse : un
/// refus sur notre écran ne consomme pas la permission système et laisse la
/// porte ouverte à l'écran de seconde chance, alors qu'un refus sur la boîte
/// native est définitif (`deniedForever` — plus aucun moyen de la
/// redemander, seulement d'ouvrir les réglages). C'est aussi pour ça qu'on
/// ne repropose jamais l'écran de seconde chance après un refus système :
/// le bouton « Activer » n'aurait alors plus aucun effet.
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

/// Termine l'onboarding sans demander la localisation.
Future<void> skipLocationAndFinish(BuildContext context, WidgetRef ref) async {
  final store = ref.read(onboardingStoreProvider);
  await store.markCompleted();
  if (!context.mounted) return;
  context.go(kDestinationWithoutLocation);
}
