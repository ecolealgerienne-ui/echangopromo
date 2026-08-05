import 'package:echango_promo/domain/models/commune.dart';
import 'package:echango_promo/features/client/providers/commune_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Ce que ce banc prouve : qu'une commune enregistrée mais inconnue du
/// référentiel est bien écartée — et qu'un référentiel muet n'écarte rien.**
///
/// Le défaut d'origine (2026-08-05) : les identifiants gardés en préférences
/// n'étaient jamais confrontés à la liste des communes. Une base réamorcée
/// leur donnant de nouveaux UUID, quatre identifiants fantômes suffisaient à
/// atteindre le plafond de sélection — toutes les cases se désactivaient, et
/// aucune n'apparaissait cochée. L'écran devenait impossible à utiliser, sans
/// message ni erreur.
///
/// Le second cas est celui qui pouvait faire pire que le mal : élaguer sur un
/// référentiel vide (requête en cours, en échec, seed non passé) aurait effacé
/// une sélection parfaitement valide.
void main() {
  Commune c(String id) => Commune(id: id, nom: 'C-$id', wilaya: 'Djelfa');

  const djelfa = 'a1';
  const ainOussara = 'a2';
  const fantome = 'z9';

  group('selectionEffective', () {
    // ── Doivent CONSERVER ──────────────────────────────────────────────────

    test('garde une sélection entièrement connue', () {
      expect(
        selectionEffective({djelfa, ainOussara}, [c(djelfa), c(ainOussara)]),
        {djelfa, ainOussara},
      );
    });

    test(
        'garde tout si le référentiel est vide — « je ne sais pas » n’est '
        'pas « aucune n’existe »', () {
      expect(selectionEffective({djelfa, fantome}, const []), {
        djelfa,
        fantome,
      });
    });

    test('une sélection vide le reste', () {
      expect(selectionEffective(const {}, [c(djelfa)]), isEmpty);
    });

    // ── Doivent ÉCARTER ────────────────────────────────────────────────────

    test('écarte un identifiant que le référentiel ne connaît plus', () {
      expect(selectionEffective({djelfa, fantome}, [c(djelfa)]), {djelfa});
    });

    test(
        'écarte TOUT quand plus aucun identifiant ne survit — le cas réel '
        'après un réamorçage de base', () {
      expect(
        selectionEffective({
          'vieux1',
          'vieux2',
          'vieux3',
          'vieux4'
        }, [
          c(djelfa),
          c(ainOussara),
        ]),
        isEmpty,
      );
    });

    test('n’invente jamais une commune absente de la sélection', () {
      expect(
          selectionEffective({djelfa}, [c(djelfa), c(ainOussara)]), {djelfa});
    });
  });
}
