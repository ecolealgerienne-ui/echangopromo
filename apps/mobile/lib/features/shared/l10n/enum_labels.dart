import 'package:flutter/widgets.dart';
import '../../../domain/enums/categorie.dart';
import '../../../domain/enums/promo_lifecycle_status.dart';
import '../../../l10n/app_localizations.dart';

/// Traduit les enums miroirs du backend (CLAUDE.md règle #19) en texte
/// localisé — les modèles/enums eux-mêmes n'ont pas accès à un
/// `BuildContext`, ce mapping vit donc côté UI plutôt que sur `Categorie`/
/// `PromoLifecycleStatus` (voir aussi `Promo.isExpired` pour le cas
/// publiée-mais-expirée).
String categorieLabel(BuildContext context, Categorie categorie) {
  final l10n = AppLocalizations.of(context)!;
  switch (categorie) {
    case Categorie.alimentation:
      return l10n.categorieAlimentation;
    case Categorie.vetementsTextile:
      return l10n.categorieVetementsTextile;
    case Categorie.electromenager:
      return l10n.categorieElectromenager;
    case Categorie.beauteHygiene:
      return l10n.categorieBeauteHygiene;
    case Categorie.maisonAmeublement:
      return l10n.categorieMaisonAmeublement;
    case Categorie.autre:
      return l10n.categorieAutre;
  }
}

String promoLifecycleLabel(BuildContext context, PromoLifecycleStatus status, {required bool isExpired}) {
  final l10n = AppLocalizations.of(context)!;
  switch (status) {
    case PromoLifecycleStatus.brouillon:
      return l10n.lifecycleDraft;
    case PromoLifecycleStatus.publiee:
      return isExpired ? l10n.lifecycleExpired : l10n.lifecyclePublished;
    case PromoLifecycleStatus.arretee:
      return l10n.lifecycleStopped;
    case PromoLifecycleStatus.expiree:
      return l10n.lifecycleExpired;
  }
}

String visitStatusLabel(BuildContext context, String visitStatus) {
  final l10n = AppLocalizations.of(context)!;
  switch (visitStatus) {
    case 'jamais_visite':
      return l10n.visitStatusNeverVisited;
    case 'a_jour':
      return l10n.visitStatusUpToDate;
    case 'a_relancer':
      return l10n.visitStatusToFollowUp;
    default:
      return visitStatus;
  }
}
