/// Bornes de durée d'une promo — **recopiées du serveur, et tenues par un
/// contrôle**.
///
/// Source unique : `PromoService.defaultDureeJours()` et `maxDureeJours()`
/// (`apps/backend/src/promo/promo.service.ts`), qui lisent
/// `PROMO_DEFAULT_DURATION_DAYS` et `PROMO_MAX_DURATION_DAYS` avec ces
/// valeurs par défaut.
///
/// ── Pourquoi ce fichier existe ────────────────────────────────────────────
///
/// Ces deux nombres vivaient en **trois exemplaires** côté app
/// (`promo_form_screen.dart`, `agent_promo_form_screen.dart`,
/// `promo_form_fields.dart`), sans que rien ne les tienne d'accord entre eux
/// ni avec le serveur. Un passage de 7 à 10 jours côté backend laissait les
/// trois écrans plafonner à 7 ; le passage inverse faisait refuser le serveur
/// avec `PROMO_DATE_FIN_EXCEEDS_MAX`, dont le message interpole une valeur et
/// n'est donc **pas traduit** (revue 2026-08-05, règle #32).
///
/// `tool/check_server_rules.dart` compare désormais ces deux constantes aux
/// valeurs par défaut lues dans `promo.service.ts` : la copie reste une copie,
/// mais elle ne peut plus diverger en silence.
///
/// ⚠️ **Ces bornes ne servent plus qu'à l'interface.** L'app envoie désormais
/// `dureeJours` et non une `dateFin` absolue (`PromoApi._buildPayload`) : le
/// calcul se fait sur l'horloge du serveur, la seule qui valide. Elles ne
/// décident donc plus de rien côté réseau — elles remplissent le sélecteur de
/// durée, et c'est `resolveDateFin` qui refuse au-delà du plafond.
library;

import 'enums/promo_lifecycle_status.dart';

/// Durée proposée par défaut à la création d'une promo.
const promoDefaultDureeJours = 5;

/// Durée maximale acceptée par le serveur.
const promoMaxDureeJours = 7;

/// Fenêtre « expire bientôt » — celle qui allume le badge côté app **et**
/// celle qui déclenche la notification côté serveur
/// (`EXPIRING_SOON_WINDOW_HOURS`, `promo.service.ts`). Les deux doivent bouger
/// ensemble : un badge sans notification, ou l'inverse, est un produit qui se
/// contredit lui-même.
const promoExpiringSoonHours = 24;

/// **Une promo est-elle expirée ?** — l'unique définition côté app.
///
/// Le statut ne suffit pas : le cron d'expiration ne passe qu'à 1h, donc une
/// promo peut rester `publiee` jusqu'à 24 h après sa `dateFin`. `Promo`
/// l'appliquait déjà ; `ModerationItem` passait `isExpired: false` **en dur**
/// et ne désérialisait même pas `dateFin`, pourtant servi par
/// `toAdminPromoJson` — l'écran de détail admin affichait donc « publiée » sur
/// une promo terminée (revue 2026-08-05, règles #30 et #31).
bool promoEstExpiree({
  required PromoLifecycleStatus lifecycleStatus,
  required DateTime? dateFin,
}) =>
    lifecycleStatus == PromoLifecycleStatus.expiree ||
    (dateFin != null && dateFin.isBefore(DateTime.now()));
