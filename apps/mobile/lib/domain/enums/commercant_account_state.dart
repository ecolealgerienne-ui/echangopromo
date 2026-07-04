/// Miroir de `CommercantAccountState` (backend).
enum CommercantAccountState {
  creeAgent('cree_agent'),
  autonome('autonome');

  const CommercantAccountState(this.value);

  final String value;

  static CommercantAccountState fromValue(String value) => CommercantAccountState.values
      .firstWhere((s) => s.value == value, orElse: () => CommercantAccountState.autonome);
}
