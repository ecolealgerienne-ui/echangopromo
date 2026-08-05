import 'package:integration_test/integration_test_driver.dart';

/// Lanceur des parcours joués sur l'appareil.
///
/// ⚠️ Il ne contient aucune logique et n'en contiendra jamais : il tourne sur
/// la machine de développement, pas sur l'appareil. Les deux moitiés ne
/// partagent pas de mémoire — y écrire une assertion la rendrait aveugle à ce
/// qui se passe à l'écran.
Future<void> main() => integrationDriver();
