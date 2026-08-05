import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/selected_commune_store.dart';
import '../../../domain/models/commune.dart';
import '../../../providers/core_providers.dart';

final communeListProvider = FutureProvider<List<Commune>>((ref) {
  return ref.watch(communeApiProvider).list();
});

/// Décision produit 2026-07-12 : jusqu'à 4 communes sélectionnables côté
/// client (grandes villes où les communes sont accolées), plafond répété
/// côté backend (`ListPromoQueryDto.communeIds`, `@ArrayMaxSize(4)`).
const kMaxSelectedCommunes = 4;

/// Sélection enregistrée, **réduite à ce que le référentiel connaît**.
///
/// `SelectedCommuneStore` garde des UUID bruts dans les préférences, et rien
/// ne les confrontait jamais à la liste des communes. Une base réamorcée
/// (`seed:communes`, les bancs) leur en donne de nouveaux : l'app conservait
/// les anciens indéfiniment, sans que rien ne le signale — un identifiant
/// périmé est indiscernable d'un identifiant valide.
///
/// L'effet visible était un écran de sélection **inutilisable** : quatre
/// identifiants fantômes suffisaient à atteindre `kMaxSelectedCommunes`, ce
/// qui désactivait *toutes* les cases, dont aucune n'apparaissait cochée
/// puisqu'ils ne désignaient plus rien (constaté le 2026-08-05).
///
/// ⚠️ **Un référentiel vide ne réduit rien.** Il veut dire « je ne sais pas »
/// — requête en cours, en échec, ou seed non passé — et non « aucune des
/// tiennes n'existe ». Élaguer sur ce silence effacerait une sélection
/// parfaitement valide (règle #29 : l'absence d'information n'est pas une
/// information).
Set<String> selectionEffective(
  Set<String> enregistrees,
  List<Commune> referentiel,
) {
  if (referentiel.isEmpty) return enregistrees;
  return enregistrees.intersection(referentiel.map((c) => c.id).toSet());
}

class SelectedCommunesController extends StateNotifier<List<String>> {
  SelectedCommunesController(this._store) : super(_store.get());

  final SelectedCommuneStore _store;

  Future<void> select(List<String> communeIds) async {
    final capped = communeIds.take(kMaxSelectedCommunes).toList();
    await _store.set(capped);
    state = capped;
  }
}

final selectedCommunesProvider =
    StateNotifierProvider<SelectedCommunesController, List<String>>(
  (ref) => SelectedCommunesController(ref.watch(selectedCommuneStoreProvider)),
);

/// Libellé des communes sélectionnées, affiché en tête de l'accueil. Au-delà
/// d'une commune on n'aligne pas les noms (la barre déborderait) : la
/// première suivie du nombre de communes restantes. `null` tant que la liste
/// des communes n'est pas chargée — l'appelant affiche alors un libellé
/// générique plutôt qu'une chaîne vide.
final selectedCommuneLabelProvider = Provider.autoDispose<String?>((ref) {
  final ids = ref.watch(selectedCommunesProvider);
  final communes = ref.watch(communeListProvider).valueOrNull;
  if (ids.isEmpty || communes == null) return null;
  final names = communes
      .where((commune) => ids.contains(commune.id))
      .map((c) => c.nom)
      .toList();
  if (names.isEmpty) return null;
  return names.length == 1
      ? names.first
      : '${names.first} +${names.length - 1}';
});
