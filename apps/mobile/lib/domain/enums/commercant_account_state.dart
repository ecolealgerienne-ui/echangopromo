import 'api_enum.dart';

/// Miroir de `CommercantAccountState` (backend).
enum CommercantAccountState {
  creeAgent('cree_agent'),
  autonome('autonome');

  const CommercantAccountState(this.value);

  final String value;

  /// Repli : un état de compte inconnu est traité comme autonome, l'état le
  /// moins restrictif — ne pas brider un commerçant sur une valeur mal comprise.
  static CommercantAccountState fromValue(String value) => fromApiValue(
        valeurs: CommercantAccountState.values,
        valeurDe: (v) => v.value,
        recu: value,
        repli: CommercantAccountState.autonome,
        enumeration: 'CommercantAccountState',
      );
}
