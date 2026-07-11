/// Miroir de `ReportReason` (backend) — motif du signalement client
/// (CLAUDE.md règle #19), plan de correction Phase 5.
enum ReportReason {
  perime('perime'),
  arnaque('arnaque'),
  photoTrompeuse('photo_trompeuse'),
  autre('autre');

  const ReportReason(this.value);

  final String value;

  static ReportReason fromValue(String value) =>
      ReportReason.values.firstWhere((r) => r.value == value, orElse: () => ReportReason.autre);
}
