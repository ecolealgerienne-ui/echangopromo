import 'api_enum.dart';

/// Miroir de `ReportReason` (backend) — motif du signalement client
/// (CLAUDE.md règle #19), plan de correction Phase 5.
enum ReportReason {
  perime('perime'),
  arnaque('arnaque'),
  photoTrompeuse('photo_trompeuse'),
  autre('autre');

  const ReportReason(this.value);

  final String value;

  /// Repli : la liste est fermée et les motifs partent **de** l'app — un
  /// inconnu ne peut venir que d'un désaccord de version.
  static ReportReason fromValue(String value) => fromApiValue(
        valeurs: ReportReason.values,
        valeurDe: (v) => v.value,
        recu: value,
        repli: ReportReason.autre,
        enumeration: 'ReportReason',
      );
}
