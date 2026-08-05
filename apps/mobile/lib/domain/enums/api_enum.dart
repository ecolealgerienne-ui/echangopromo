import 'package:flutter/foundation.dart';

/// Résout une **valeur réseau** vers un membre d'enum miroir, avec un repli
/// qui **se signale** au lieu de se taire.
///
/// ── Pourquoi ce helper existe ────────────────────────────────────────────
///
/// Cinq miroirs portaient le même `firstWhere(..., orElse: …)`. Une valeur
/// ajoutée côté backend y devenait silencieusement autre chose : aucune
/// erreur, aucun journal, et pour `PromoLifecycleStatus` un repli sur
/// `expiree` — donc des promos qui **disparaissent** de l'affichage client,
/// avec un diagnostic qui partirait chercher une panne de données.
///
/// ⚠️ **Le repli n'est pas supprimé, et c'est délibéré.** Lever sur une valeur
/// inconnue ferait planter une liste entière à cause d'une seule ligne, chez
/// l'utilisateur, au pire moment. Et pour au moins deux de ces enums le repli
/// est un **choix produit** : une catégorie inconnue affichée comme « autre »
/// est le comportement voulu, et un test le documente depuis le 2026-07-05.
///
/// Ce qui change, c'est que le repli **dit quelque chose** — le critère de la
/// règle 29 : *si cette valeur est fausse, est-ce que quelque chose le dira ?*
/// Ici oui, en développement et pendant les tests, au moment où quelqu'un peut
/// encore agir. En production il reste muet, parce qu'un utilisateur n'a rien
/// à faire de ce message.
///
/// ⚠️ **Ce helper ne remplace pas `tool/check_enums.dart`.** Lui compare les
/// deux listes *avant* l'exécution et refuse un miroir en retard ; celui-ci ne
/// parle que si une valeur inconnue arrive vraiment. Le premier prévient, le
/// second constate.
T fromApiValue<T>({
  required List<T> valeurs,
  required String Function(T) valeurDe,
  required String recu,
  required T repli,
  required String enumeration,
}) {
  for (final valeur in valeurs) {
    if (valeurDe(valeur) == recu) return valeur;
  }
  if (kDebugMode) {
    debugPrint(
      '⚠️  $enumeration : valeur « $recu » inconnue du miroir Dart — repli sur '
      '« $repli ». Le backend a-t-il ajouté une valeur ? '
      'Vérifier avec : dart run tool/check_enums.dart',
    );
  }
  return repli;
}
