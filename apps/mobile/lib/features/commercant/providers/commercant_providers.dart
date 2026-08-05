import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/enums/registre_status.dart';
import '../../../domain/models/commercant.dart';
import '../../../domain/models/promo.dart';
import '../../../providers/core_providers.dart';

/// Occupation du plafond de promos actives — **mesurée par le serveur**
/// (`GET /promo/me/slots`), plafond compris.
///
/// Remplace `kMaxPromosActives = 5` et `countActivePromos(promos)`, qui
/// recopiaient la règle et la calculaient sur une page de 100 promos tous
/// statuts confondus : au-delà, le tableau de bord annonçait des emplacements
/// libres pendant que le serveur refusait en `PROMO_ACTIVE_CAP_REACHED`. Et il
/// comptait une promo expirée non encore basculée par le cron, qui n'occupe
/// plus rien (revue 2026-08-05, règles #29 et #32).
final promoSlotsProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(promoApiProvider).fetchSlots());

/// Fiche du commerçant connecté. Partagée entre le tableau de bord et tout
/// écran ayant besoin de son nom, de son statut de registre ou de sa photo.
final commercantMeProvider =
    FutureProvider.autoDispose((ref) => ref.watch(commercantApiProvider).me());

/// Nombre de visites de la fiche commerçant (specs §3.2).
final commercantProfileViewsProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(commercantApiProvider).dashboardProfileViewCount(),
);

/// Promos du commerçant connecté, tous statuts confondus. Déplacé ici depuis
/// `my_promos_screen.dart` : le tableau de bord en a besoin aussi, et deux
/// écrans partageant un provider ne doivent pas dépendre du fichier d'un
/// écran (règle d'audit #21).
final myPromosProvider =
    FutureProvider.autoDispose((ref) => ref.watch(promoApiProvider).listMine());

/// Somme des vues de toutes les promos. `viewCount` n'est renseigné que par
/// `GET /promo/me/all` (propriétaire authentifié) — d'où le repli à zéro.
int totalPromoViews(List<Promo> promos) =>
    promos.fold(0, (sum, promo) => sum + (promo.viewCount ?? 0));

/// Vrai quand le registre de commerce a été validé par un admin. Sert au
/// badge « Vérifié » du tableau de bord.
bool isRegistreVerified(Commercant commercant) =>
    commercant.registreStatus == RegistreStatus.valide;
