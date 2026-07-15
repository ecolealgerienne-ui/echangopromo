import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../app/theme.dart';
import '../../../domain/enums/audit_actor_type.dart';
import '../../../domain/enums/categorie.dart';
import '../../../domain/enums/commercant_origin_verification.dart';
import '../../../domain/enums/promo_lifecycle_status.dart';
import '../../../domain/enums/promo_moderation_status.dart';
import '../../../domain/enums/registre_status.dart';
import '../../../domain/enums/report_reason.dart';
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
    case PromoLifecycleStatus.supprimee:
      return l10n.lifecycleDeleted;
  }
}

/// Couleur du badge de statut affiché dans "Mes promos" — dérivée du thème
/// (`AppSemanticColors`/`colorScheme`) pour rester calibrée en mode sombre,
/// plutôt que des `Colors.*` fixes (audit design 2026-07-11).
Color promoLifecycleColor(BuildContext context, PromoLifecycleStatus status, {required bool isExpired}) {
  final colorScheme = Theme.of(context).colorScheme;
  if (isExpired) return colorScheme.onSurfaceVariant;
  final semanticColors = Theme.of(context).extension<AppSemanticColors>()!;
  switch (status) {
    case PromoLifecycleStatus.brouillon:
      return colorScheme.onSurfaceVariant;
    case PromoLifecycleStatus.publiee:
      return semanticColors.success;
    case PromoLifecycleStatus.arretee:
      return semanticColors.warning;
    case PromoLifecycleStatus.expiree:
      return colorScheme.onSurfaceVariant;
    case PromoLifecycleStatus.supprimee:
      return colorScheme.error;
  }
}

String moderationStatusLabel(BuildContext context, PromoModerationStatus status) {
  final l10n = AppLocalizations.of(context)!;
  switch (status) {
    case PromoModerationStatus.normale:
      return l10n.moderationNormale;
    case PromoModerationStatus.signalee:
      return l10n.moderationSignalee;
    case PromoModerationStatus.masquee:
      return l10n.moderationMasquee;
    case PromoModerationStatus.verifieeOk:
      return l10n.moderationVerifieeOk;
  }
}

/// Couleur du badge de statut de modération — même logique dérivée du
/// thème que `promoLifecycleColor`.
Color moderationStatusColor(BuildContext context, PromoModerationStatus status) {
  final colorScheme = Theme.of(context).colorScheme;
  final semanticColors = Theme.of(context).extension<AppSemanticColors>()!;
  switch (status) {
    case PromoModerationStatus.normale:
      return semanticColors.success;
    case PromoModerationStatus.signalee:
      return semanticColors.warning;
    case PromoModerationStatus.masquee:
      return colorScheme.error;
    case PromoModerationStatus.verifieeOk:
      return colorScheme.onSurfaceVariant;
  }
}

String commercantOriginVerificationLabel(
  BuildContext context,
  CommercantOriginVerification origin,
) {
  final l10n = AppLocalizations.of(context)!;
  switch (origin) {
    case CommercantOriginVerification.autoInscrit:
      return l10n.originAutoInscrit;
    case CommercantOriginVerification.confirmeAgent:
      return l10n.originConfirmeAgent;
  }
}

String registreStatusLabel(BuildContext context, RegistreStatus status) {
  final l10n = AppLocalizations.of(context)!;
  switch (status) {
    case RegistreStatus.enAttente:
      return l10n.registreStatusEnAttente;
    case RegistreStatus.valide:
      return l10n.registreStatusValide;
    case RegistreStatus.rejete:
      return l10n.registreStatusRejete;
  }
}

Color registreStatusColor(BuildContext context, RegistreStatus status) {
  final semanticColors = Theme.of(context).extension<AppSemanticColors>()!;
  switch (status) {
    case RegistreStatus.enAttente:
      return semanticColors.warning;
    case RegistreStatus.valide:
      return semanticColors.success;
    case RegistreStatus.rejete:
      return Theme.of(context).colorScheme.error;
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

String auditActorTypeLabel(BuildContext context, AuditActorType actorType) {
  final l10n = AppLocalizations.of(context)!;
  switch (actorType) {
    case AuditActorType.admin:
      return l10n.auditActorAdmin;
    case AuditActorType.agent:
      return l10n.auditActorAgent;
  }
}

String reportReasonLabel(BuildContext context, ReportReason reason) {
  final l10n = AppLocalizations.of(context)!;
  switch (reason) {
    case ReportReason.perime:
      return l10n.reportReasonPerime;
    case ReportReason.arnaque:
      return l10n.reportReasonArnaque;
    case ReportReason.photoTrompeuse:
      return l10n.reportReasonPhotoTrompeuse;
    case ReportReason.autre:
      return l10n.reportReasonAutre;
  }
}
