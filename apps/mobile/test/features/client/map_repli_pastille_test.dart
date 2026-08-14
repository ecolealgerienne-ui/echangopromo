import 'package:echango_promo/features/client/screens/map_screen.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le bouton « Chercher autour de ce point » se replie en rond dès que le
/// client explore la carte. Toute la décision tient dans
/// `estExplorationCliente`, isolée du widget pour être éprouvable sans monter
/// une carte, des tuiles et un réseau.
///
/// ⚠️ Ce qui doit ÉCHOUER compte autant que ce qui doit passer (règle 28) : si
/// un recentrage automatique comptait pour une exploration, la pastille se
/// replierait avant même d'être affichée et son libellé ne serait jamais lu.
/// C'est le défaut que ces cas négatifs interdisent.
void main() {
  group('estExplorationCliente', () {
    const gestes = <MapEventSource>[
      MapEventSource.dragStart,
      MapEventSource.onDrag,
      MapEventSource.dragEnd,
      MapEventSource.multiFingerGestureStart,
      MapEventSource.onMultiFinger,
      MapEventSource.multiFingerEnd,
      MapEventSource.flingAnimationController,
      MapEventSource.doubleTap,
      MapEventSource.doubleTapHold,
      MapEventSource.doubleTapZoomAnimationController,
      MapEventSource.scrollWheel,
      MapEventSource.cursorKeyboardRotation,
    ];

    /// Les sources qui ne déplacent rien, ou que l'app se produit à elle-même.
    const nonGestes = <MapEventSource>[
      // `_recenterOn` au démarrage : GPS, point enregistré, point serveur.
      MapEventSource.mapController,
      MapEventSource.fitCamera,
      // Un clic ouvre ou referme une fiche sans bouger la caméra.
      MapEventSource.tap,
      MapEventSource.secondaryTap,
      MapEventSource.longPress,
      // Clavier qui s'ouvre, rotation de l'appareil, drapeaux d'interaction.
      MapEventSource.nonRotatedSizeChange,
      MapEventSource.interactiveFlagsChanged,
      MapEventSource.custom,
    ];

    for (final source in gestes) {
      test('${source.name} replie la pastille', () {
        expect(estExplorationCliente(source), isTrue);
      });
    }

    for (final source in nonGestes) {
      test('${source.name} laisse la pastille étendue', () {
        expect(estExplorationCliente(source), isFalse);
      });
    }

    test('toute source de flutter_map est classée explicitement', () {
      // ⚠️ Le contrôle qui a une vraie chance de lever un jour. Une montée de
      // version de `flutter_map` peut ajouter une source ; le `_ => false` du
      // code la traiterait alors comme « pas une exploration » — un repli qui
      // ne se produit jamais, muet et invisible à l'usage. Ce test force la
      // décision au lieu de la laisser au défaut.
      final classees = {...gestes, ...nonGestes};
      final oubliees =
          MapEventSource.values.where((s) => !classees.contains(s)).toList();
      expect(
        oubliees,
        isEmpty,
        reason:
            'sources non classées : ${oubliees.map((s) => s.name).join(", ")}'
            ' — décider pour chacune si elle vaut exploration, puis compléter '
            'estExplorationCliente ET ce test',
      );
    });
  });
}
