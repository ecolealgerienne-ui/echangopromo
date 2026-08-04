import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/models/highlight.dart';
import '../../../providers/core_providers.dart';

/// Liste admin du bandeau d'accueil, inactives comprises. Déclarée hors des
/// écrans (contrairement aux providers privés des autres écrans admin) parce
/// qu'elle est partagée par la liste et le formulaire : ce dernier doit
/// pouvoir l'invalider après enregistrement sans importer l'écran liste.
final adminHighlightsProvider = FutureProvider.autoDispose<List<Highlight>>(
  (ref) => ref.watch(highlightApiProvider).listForAdmin(),
);
