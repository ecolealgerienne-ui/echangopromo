import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/models/commune.dart';
import '../../../providers/core_providers.dart';

/// Référentiel des communes.
///
/// ⚠️ **Il ne sert plus au client**, qui cherche désormais autour d'un point
/// (bascule 2026-08-12) : il ne reste que pour la cascade wilaya → commune de
/// l'inscription commerçant et les filtres admin/agent, où la commune demeure
/// la frontière d'autorisation de l'agent (`assertCommuneMatches`).
///
/// ⚠️ Chargé **en entier**, exception nommée à la règle #15 — l'app boucle
/// jusqu'à `total` dans `CommuneApi.list`. Ce qui a disparu avec la sélection
/// client, c'est le plafond de 4 communes et le rapprochement des identifiants
/// enregistrés avec le référentiel : sans sélection locale à réconcilier, le
/// défaut qu'ils réparaient n'existe plus.
final communeListProvider = FutureProvider<List<Commune>>((ref) {
  return ref.watch(communeApiProvider).list();
});
