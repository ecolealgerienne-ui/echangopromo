import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

/// Couleur du badge de statut affiché dans "Mes promos" — indépendante de
/// la localisation du texte, juste un repère visuel rapide.
Color promoLifecycleColor(PromoLifecycleStatus status, {required bool isExpired}) {
  if (isExpired) return Colors.grey;
  switch (status) {
    case PromoLifecycleStatus.brouillon:
      return Colors.blueGrey;
    case PromoLifecycleStatus.publiee:
      return Colors.green;
    case PromoLifecycleStatus.arretee:
      return Colors.orange;
    case PromoLifecycleStatus.expiree:
      return Colors.grey;
  }
}

String notificationRelativeDate(BuildContext context, DateTime createdAt) {
  final l10n = AppLocalizations.of(context)!;
  final diff = DateTime.now().difference(createdAt);

  if (diff.inMinutes < 1) return l10n.notificationJustNow;
  if (diff.inHours < 1) return l10n.notificationMinutesAgo(diff.inMinutes);
  if (diff.inDays < 1) return l10n.notificationHoursAgo(diff.inHours);
  if (diff.inDays == 1) return l10n.notificationYesterday;

  return DateFormat('dd/MM/yyyy').format(createdAt);
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
