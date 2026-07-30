import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/enums/promo_lifecycle_status.dart';
import '../../../domain/enums/registre_status.dart';
import '../../../domain/models/commercant.dart';
import '../../../domain/models/promo.dart';
import '../../../providers/core_providers.dart';

/// Plafond de promos actives simultanées, imposé côté backend
/// (`MAX_PROMOS_ACTIVES`, `PromoService`) pour tout le monde — agent et admin
/// compris. Répété ici pour l'afficher au commerçant : il ne découvrait son
/// existence qu'en se faisant refuser une publication.
const kMaxPromosActives = 5;

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

/// Promos actuellement en ligne — la seule mesure qui compte face au plafond.
/// `PromoLifecycleStatus.publiee` uniquement : un brouillon ou une promo
/// arrêtée n'occupe pas d'emplacement, exactement comme côté backend.
int countActivePromos(List<Promo> promos) =>
    promos.where((promo) => promo.lifecycleStatus == PromoLifecycleStatus.publiee).length;

/// Somme des vues de toutes les promos. `viewCount` n'est renseigné que par
/// `GET /promo/me/all` (propriétaire authentifié) — d'où le repli à zéro.
int totalPromoViews(List<Promo> promos) =>
    promos.fold(0, (sum, promo) => sum + (promo.viewCount ?? 0));

/// Vrai quand le registre de commerce a été validé par un admin. Sert au
/// badge « Vérifié » du tableau de bord.
bool isRegistreVerified(Commercant commercant) =>
    commercant.registreStatus == RegistreStatus.valide;
