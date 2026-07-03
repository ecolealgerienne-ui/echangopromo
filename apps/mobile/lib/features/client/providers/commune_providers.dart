import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/selected_commune_store.dart';
import '../../../domain/models/commune.dart';
import '../../../providers/core_providers.dart';

final communeListProvider = FutureProvider<List<Commune>>((ref) {
  return ref.watch(communeApiProvider).list();
});

class SelectedCommuneController extends StateNotifier<String?> {
  SelectedCommuneController(this._store) : super(_store.get());

  final SelectedCommuneStore _store;

  Future<void> select(String communeId) async {
    await _store.set(communeId);
    state = communeId;
  }
}

final selectedCommuneProvider = StateNotifierProvider<SelectedCommuneController, String?>(
  (ref) => SelectedCommuneController(ref.watch(selectedCommuneStoreProvider)),
);
