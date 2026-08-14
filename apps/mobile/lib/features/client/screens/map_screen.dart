import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../app/theme.dart';
import '../../../data/api/api_exception.dart';
import '../../../data/local/point_proposal_store.dart';
import '../../../domain/enums/categorie.dart';
import '../../../domain/models/map_shop.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/l10n/enum_labels.dart';
import '../providers/location_providers.dart';
import '../providers/position_providers.dart';
import '../providers/map_providers.dart';
import '../providers/promo_providers.dart';
import '../utils/marker_cluster.dart';
import '../widgets/map_shop_sheet.dart';

/// ⚠️ **Le centre de repli n'est plus déclaré ici.** Cet écran en portait un
/// (Djelfa, en dur) pendant que la configuration serveur en annonçait un autre :
/// un client sans point enregistré aurait vu une liste autour de l'un et une
/// carte autour de l'autre. Il n'en existe plus qu'un seul dans tout le dépôt,
/// `kPointDeRepliHorsLigne`, au bout de `centreParDefautProvider` (A4).
const _initialZoom = 13.0;

/// Au-delà de ce zoom, deux commerces distincts ne se chevauchent plus :
/// inutile de continuer à les regrouper.
const _maxClusterZoom = 17.0;

/// Immobilité requise avant de réagir à un déplacement de carte. Assez court
/// pour rester imperceptible à la main, assez long pour qu'un pincement
/// complet ne compte que pour un seul traitement.
const _settleDelay = Duration(milliseconds: 300);

/// Temps laissé au client pour LIRE le libellé du bouton flottant avant qu'il
/// ne se replie en rond. Sans ce délai, un client qui ne touche pas la carte
/// garderait sous les yeux une pastille occupant 60 % de la largeur ; avec un
/// délai trop court, il ne saurait jamais ce que fait ce rond.
const _repliLibelleDelay = Duration(seconds: 5);

/// En deçà, le cadrage ne veut plus rien dire : le point du client n'est pas
/// mesuré au mètre, et le cercle circonscrit à la vue est déjà une
/// approximation. Un rayon de 200 m donnerait une liste d'une rue avec une
/// précision qu'aucune des deux données n'a.
const _rayonPlancherKm = 1.0;

/// Au-delà de ce rapport, la vue ne correspond plus au cadre enregistré : on a
/// zoomé ou dézoomé assez pour que la liste parle d'autre chose que l'écran.
const _cadrePerimeFacteur = 1.5;

/// Le rayon qu'il faut pour couvrir ce que la carte montre.
///
/// ⚠️ **C'est le zoom qui parle ici, pas une constante.** Le geste « Chercher
/// autour de ce point » prenait le centre de la carte et lui collait le rayon
/// par défaut du serveur : cadrer une rue ou une wilaya donnait la même liste.
/// Remarqué depuis Alger le 2026-08-14 — zoomer sur un quartier puis revenir à
/// la liste montrait tout Alger.
///
/// Demi-diagonale : c'est le cercle **circonscrit** au rectangle visible, donc
/// il couvre tout l'écran et un peu au-delà. Le cercle inscrit, lui, laisserait
/// les coins de la carte hors de la liste — on verrait des commerces qu'on ne
/// retrouverait pas.
///
/// ⚠️ Rend `null` si le plafond serveur n'est pas connu : sans lui on ne peut
/// pas borner, et transmettre un rayon non borné vaut moins que ne rien
/// transmettre — le serveur applique alors le sien (règle 29).
double? rayonDepuisLaVue(LatLng nordOuest, LatLng sudEst,
    {required double? plafondKm}) {
  if (plafondKm == null) return null;
  final diagonaleM = distanceTo(nordOuest, sudEst.latitude, sudEst.longitude);
  if (diagonaleM == null) return null;
  final demiDiagonaleKm = diagonaleM / 2000;
  if (demiDiagonaleKm < _rayonPlancherKm) return _rayonPlancherKm;
  return demiDiagonaleKm > plafondKm ? plafondKm : demiDiagonaleKm;
}

/// Le rectangle que décrit un rayon — l'inverse de [rayonDepuisLaVue].
///
/// ⚠️ **Le zoom n'est pas stocké, et c'est délibéré.** Il serait une seconde
/// valeur disant la même chose que le rayon, et deux valeurs qui doivent
/// s'accorder finissent par diverger : la liste cadrerait 2 km pendant que la
/// carte en montrerait 8, sans que rien ne le signale (règle 30). Le zoom est le
/// **rendu** du rayon, pas un fait indépendant — et il dépend en plus de la
/// taille de l'écran, donc le stocker rendrait le cadrage faux sur un autre
/// appareil.
///
/// Le rayon étant la demi-diagonale de la vue, le demi-côté du carré équivalent
/// vaut `r / √2`. `fitCamera` en déduit le zoom exact pour l'écran courant.
///
/// ⚠️ Rend `null` sans rayon : un client d'avant cette version n'a rien cadré,
/// et inventer un rectangle lui imposerait un zoom qu'il n'a pas choisi.
LatLngBounds? cadreDepuisLeRayon(LatLng centre, double? rayonKm) {
  if (rayonKm == null || rayonKm <= 0) return null;
  final demiCoteKm = rayonKm / math.sqrt2;
  final dLat = demiCoteKm / 111.32;
  // Un degré de longitude rétrécit avec la latitude. Le cosinus est borné :
  // près des pôles il tend vers zéro et l'écart partirait à l'infini — hors
  // sujet en Algérie, mais un `NaN` dans un cadrage fige la carte sans erreur.
  final cos = math.cos(centre.latitude * math.pi / 180);
  final dLng = demiCoteKm / (111.32 * (cos.abs() < 0.01 ? 0.01 : cos));
  // ⚠️ Bornage indispensable, et trouvé par le test : près du pôle,
  // `latitude + dLat` dépasse 90 et `LatLng` lève une assertion — la carte se
  // fige sans message. Même précaution que `_onMapEvent` prend déjà sur la zone
  // visible, pour la même raison.
  return LatLngBounds(
    LatLng((centre.latitude - dLat).clamp(-90.0, 90.0),
        (centre.longitude - dLng).clamp(-180.0, 180.0)),
    LatLng((centre.latitude + dLat).clamp(-90.0, 90.0),
        (centre.longitude + dLng).clamp(-180.0, 180.0)),
  );
}

/// La vue montre-t-elle autre chose que ce que le cadre enregistré couvre ?
///
/// ⚠️ **Ce n'est pas la même question que la proposition d'exploration**, qui
/// regarde si le CENTRE s'est éloigné. Ici on regarde la LARGEUR : depuis Alger,
/// zoomer sur un quartier ne déplace pas le centre — la proposition ne dit rien
/// — et pourtant la liste continue de montrer toute la ville. C'est ce cas-là,
/// et lui seul, qui doit redéployer la pastille.
bool cadreEstPerime(double? rayonDeLaVue, double? rayonEnregistre) {
  if (rayonDeLaVue == null) return false;
  // Aucun cadre posé : la pastille a quelque chose à proposer, toujours.
  if (rayonEnregistre == null) return true;
  final rapport = rayonDeLaVue / rayonEnregistre;
  return rapport > _cadrePerimeFacteur || rapport < 1 / _cadrePerimeFacteur;
}

/// Le geste vient-il du client, ou l'app s'est-elle recentrée toute seule ?
///
/// ⚠️ La distinction est le cœur du repli : `_recenterOn` déplace la caméra au
/// démarrage (GPS, point enregistré, point serveur). Compter ces déplacements
/// comme une exploration replierait le bouton **avant même que la carte soit
/// affichée** — le libellé ne serait alors jamais lu par personne.
///
/// ⚠️ Liste **positive**, et c'est délibéré (règle 29) : une source inconnue —
/// une version future de `flutter_map` en ajoutera — laisse la pastille
/// DÉPLIÉE. Des deux échecs possibles, un bouton trop visible se remarque et se
/// corrige ; un bouton replié trop tôt disparaît en silence.
bool estExplorationCliente(MapEventSource source) => switch (source) {
      MapEventSource.dragStart ||
      MapEventSource.onDrag ||
      MapEventSource.dragEnd ||
      MapEventSource.multiFingerGestureStart ||
      MapEventSource.onMultiFinger ||
      MapEventSource.multiFingerEnd ||
      MapEventSource.flingAnimationController ||
      MapEventSource.doubleTap ||
      MapEventSource.doubleTapHold ||
      MapEventSource.doubleTapZoomAnimationController ||
      MapEventSource.scrollWheel ||
      MapEventSource.cursorKeyboardRotation =>
        true,
      // `tap` et `longPress` ouvrent ou referment une fiche sans rien déplacer ;
      // `mapController`, `fitCamera` et `nonRotatedSizeChange` sont l'app
      // elle-même. Aucun n'est une exploration.
      _ => false,
    };

/// Carte "autour de moi" : les commerces trop proches à l'écran sont
/// regroupés en ronds qui se scindent au zoom, jusqu'aux points exacts.
/// Un clic sur un rond zoome dessus ; un clic sur un point ouvre la fiche
/// du commerçant.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  /// L'invitation à activer la localisation a-t-elle été écartée ?
  ///
  /// ⚠️ **Plus aucune persistance depuis le 2026-08-14.** Ce drapeau était
  /// initialisé depuis `LocationInviteStore`, que `main` a supprimé dans le
  /// commit même qui corrige le second refus Apple 5.1.1(iv) — parce que le
  /// mécanisme d'écart ÉTAIT le problème : il permettait de fermer
  /// l'explication sans que la demande système ait lieu.
  ///
  /// Il ne sert donc plus qu'à masquer le bandeau immédiatement après un
  /// accord, sans attendre le rafraîchissement du provider de permission. Il
  /// n'y a plus rien à retenir d'une session à l'autre : le bandeau ne
  /// s'affiche que tant que la permission est demandable, et un seul geste
  /// suffit à sortir de cet état, quelle que soit la réponse.
  bool _invitationEcartee = false;

  final MapController _map = MapController();

  /// Zone **chargée**, volontairement plus large que l'écran — pas la zone
  /// visible. Sert de clé au provider : tant que ce qu'on regarde tient
  /// dedans, aucune requête n'est relancée.
  MapBounds? _bounds;
  double _zoom = _initialZoom;
  MapShop? _selected;

  /// Centre de la carte **une fois stabilisée**, pas à chaque image. C'est lui
  /// que la proposition d'enregistrement offre, et c'est lui qu'on compare à la
  /// ville déjà enregistrée. Lu depuis `_map.camera` uniquement à ce
  /// moment-là : le lire pendant un vol proposerait une ville qu'on traverse.
  LatLng? _centreStabilise;

  late bool _premierPointEcarte =
      ref.read(pointProposalStoreProvider).premierPointEcarte();

  /// Ville explorée que le client vient d'écarter, à la maille du centième de
  /// degré. `null` = aucune. Relue au démarrage pour survivre à un retour sur
  /// l'écran.
  late String? _villeEcartee =
      ref.read(pointProposalStoreProvider).villeEcartee();

  /// Derniers commerces reçus, conservés pendant qu'une nouvelle zone se
  /// charge. Sans ça, changer de zone vide `valueOrNull` et fait disparaître
  /// tous les points le temps de la requête — la carte se « rechargeait »
  /// visiblement à chaque geste.
  List<MapShop> _lastShops = const [];

  /// Attente que la carte se stabilise avant de réagir. Pendant un pincement
  /// ou un vol, `flutter_map` émet un événement **par frame** : traiter
  /// chacun d'eux, c'était des dizaines de requêtes par geste — de quoi
  /// épuiser la limite de débit du serveur en quelques secondes et vider la
  /// batterie en recalculant le regroupement à chaque image.
  Timer? _settle;

  /// Repli du bouton flottant : étendu à l'arrivée, rond ensuite.
  ///
  /// Deux déclencheurs, un seul état — le premier des deux qui survient gagne :
  /// le client déplace la carte (il n'a plus besoin du libellé, il explore), ou
  /// `_repliLibelleDelay` s'écoule (il a eu le temps de lire).
  Timer? _repli;
  bool _pastilleRepliee = false;

  /// La position arrive de façon asynchrone, après le premier rendu :
  /// `initialCenter` est déjà consommé à ce moment-là, il faut donc déplacer
  /// la caméra une fois. Ce drapeau évite de la ramener sur l'utilisateur à
  /// chaque reconstruction, ce qui empêcherait toute exploration manuelle.
  bool _centeredOnUser = false;

  /// Drapeau **distinct** de `_centeredOnUser`, et c'est délibéré : un GPS qui
  /// arrive après le centrage sur le point par défaut doit reprendre la main.
  /// Un seul drapeau partagé aurait figé la carte sur ce centre approximatif
  /// alors que la position exacte était devenue disponible.
  ///
  /// ⚠️ Il s'appelait `_centeredOnCommune` jusqu'au 2026-08-13 — un nom qui
  /// mentait depuis la bascule géographique : il n'a jamais porté de commune,
  /// et rien ne le signalait. Un booléen mal nommé se lit comme une intention.
  bool _centeredOnDefaultPoint = false;

  @override
  void initState() {
    super.initState();
    _repli = Timer(_repliLibelleDelay, _replierPastille);
  }

  @override
  void dispose() {
    _settle?.cancel();
    _repli?.cancel();
    _map.dispose();
    super.dispose();
  }

  /// Idempotent : les deux déclencheurs peuvent se présenter, le second ne doit
  /// pas reconstruire l'écran pour rien.
  void _replierPastille() {
    if (_pastilleRepliee || !mounted) return;
    _repli?.cancel();
    setState(() => _pastilleRepliee = true);
  }

  /// Redéploie la pastille et relance son minuteur.
  ///
  /// ⚠️ **C'est l'inverse exact du repli, et c'est voulu.** Le repli libère la
  /// carte pendant qu'on explore ; le redéploiement la rend quand l'exploration
  /// a rendu le cadre faux. La pastille n'est pas un encombrement à cacher :
  /// c'est le porteur du cadre de recherche, et il doit se montrer au moment où
  /// le cadre ne correspond plus à l'écran.
  void _deplierPastille() {
    if (!mounted) return;
    _repli?.cancel();
    _repli = Timer(_repliLibelleDelay, _replierPastille);
    if (_pastilleRepliee) setState(() => _pastilleRepliee = false);
  }

  /// Le rayon que couvre la carte telle qu'elle est cadrée, ou `null`.
  ///
  /// ⚠️ **Plafonné au rayon PAR DÉFAUT du serveur, pas à son maximum.** Le
  /// maximum (50 km) borne ce que l'API accepte ; la borne produit est plus
  /// serrée : echango Promo sert des promos de proximité, pas des annonces
  /// nationales. Dézoomer sur toute la wilaya n'élargit donc pas la recherche
  /// au-delà du voisinage — la carte montre plus, la liste reste locale.
  ///
  /// ⚠️ Ce plafond est **aussi** appliqué à l'émission (`rayonBorne`, côté
  /// providers). Le poser ici seulement laisserait passer un rayon plus large
  /// déjà stocké par une version antérieure.
  double? _rayonDeLaVue() {
    final vue = _map.camera.visibleBounds;
    return rayonDepuisLaVue(
      vue.northWest,
      vue.southEast,
      plafondKm: ref.read(clientGeoConfigProvider).valueOrNull?.defaultRadiusKm,
    );
  }

  /// Appelé à la fin de chaque déplacement/zoom : `MapCamera` n'est pas
  /// disponible avant le premier rendu, d'où la mise à jour ici plutôt qu'en
  /// `initState`.
  void _onMapEvent(MapEvent event) {
    // Dès le premier geste : le client explore, le libellé a fait son travail.
    // Appelé hors du minuteur de stabilisation, à dessein — attendre 300 ms de
    // plus ferait traîner la pastille pendant tout le déplacement, c'est-à-dire
    // exactement au moment où elle gêne. Aucune source de geste n'est émise
    // pendant la phase de layout, donc ce `setState` n'y tombe pas.
    if (estExplorationCliente(event.source)) _replierPastille();

    final camera = event.camera;
    final visible = camera.visibleBounds;
    // Bornage indispensable : dézoomé, ou pendant la toute première passe de
    // layout où la taille de la carte n'est pas encore établie, la zone
    // visible peut déborder du monde réel (longitude au-delà de ±180,
    // latitude au-delà de ±90). Le backend valide ces quatre champs avec
    // `@IsLatitude`/`@IsLongitude` et rejette la requête en 400 — la carte
    // affichait alors « impossible de charger les promos de cette zone »
    // pour une raison qui n'avait rien à voir avec les promos.
    // `.clamp()` est déclaré sur `num` et renvoie `num`, d'où `.toDouble()`.
    final next = MapBounds(
      north: visible.north.clamp(-90.0, 90.0).toDouble(),
      south: visible.south.clamp(-90.0, 90.0).toDouble(),
      east: visible.east.clamp(-180.0, 180.0).toDouble(),
      west: visible.west.clamp(-180.0, 180.0).toDouble(),
    );
    // Un seul traitement par geste, une fois la carte immobile. Ce délai
    // règle aussi le "setState() called during build" : les événements émis
    // pendant la phase de layout sont absorbés par le minuteur, qui se
    // déclenche forcément hors construction.
    _settle?.cancel();
    _settle = Timer(_settleDelay, () {
      if (!mounted) return;
      // Ne recharger que si la zone regardée sort de ce qui est déjà chargé.
      // Zoomer, ou se déplacer dans la marge, n'appelle donc pas le serveur :
      // les commerces sont déjà là, seul le regroupement change. Dézoomer
      // découvre en revanche du terrain neuf et reste une vraie requête.
      final loaded = _bounds;
      final needsFetch = loaded == null || !loaded.contains(next);
      // ⚠️ Le centre se met à jour à CHAQUE stabilisation, avant la sortie
      // anticipée : se déplacer dans la marge déjà chargée ne demande rien au
      // serveur, mais change bel et bien la ville qu'on regarde. Le capturer
      // seulement quand une requête part ferait proposer une ville quittée.
      final centreChange = _centreStabilise != camera.center;
      if (!needsFetch && camera.zoom == _zoom && !centreChange) return;
      setState(() {
        if (needsFetch) _bounds = next.padded();
        _zoom = camera.zoom;
        _centreStabilise = camera.center;
      });
      // La carte s'est posée : le cadre qu'elle montre correspond-il encore à
      // celui de la liste ? Si non, la pastille redevient une proposition.
      if (cadreEstPerime(
          _rayonDeLaVue(), ref.read(clientPositionProvider)?.rayonKm)) {
        _deplierPastille();
      }
    });
  }

  /// Enregistre un point après consentement — **le même chemin** que le bouton
  /// flottant, appelé aussi par la proposition.
  ///
  /// ⚠️ Deux copies de ce geste divergeraient : le dialogue de consentement,
  /// l'invalidation des providers et la confirmation forment un tout, et c'est
  /// l'invalidation qu'on oublie (règle 30 et règle 37). Une seule
  /// implémentation, deux appelants.
  Future<void> _enregistrerPoint(LatLng centre,
      {bool viaProposition = false}) async {
    final l10n = AppLocalizations.of(context)!;
    final accepte = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext)!.savePointAction),
        content: Text(AppLocalizations.of(dialogContext)!.savePointNotice),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(dialogContext)!.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(dialogContext)!.savePointAction),
          ),
        ],
      ),
    );
    if (accepte != true) return;
    await ref.read(clientPositionProvider.notifier).enregistrer(
          centre.latitude,
          centre.longitude,
          rayonKm: _rayonDeLaVue(),
        );
    if (!mounted) return;
    // ⚠️ Sans cette invalidation, la vitrine et la carte garderaient leur
    // cadrage d'avant : elles ne sont pas reconstruites de zéro au retour d'une
    // boîte de dialogue (règle 37).
    invalidateAfterPositionChange(ref);
    // Une ville enregistrée depuis la proposition d'exploration efface la
    // « ville écartée » : elle vient d'être acceptée, la mémoriser comme
    // refusée n'aurait aucun sens.
    if (viaProposition) setState(() => _villeEcartee = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.savePointDone)),
    );
  }

  void _recenterOn(LatLng position, {double? zoom}) {
    _map.move(position, zoom ?? (_zoom < 14 ? 15.0 : _zoom));
  }

  /// Rouvre la carte sur le cadre que le client a enregistré.
  ///
  /// Sans rayon — client d'avant cette version — on retombe sur le zoom
  /// d'ouverture : c'est une absence de cadrage, pas un cadrage large.
  void _cadrerSurLePoint(LatLng centre, double? rayonKm) {
    final cadre = cadreDepuisLeRayon(centre, rayonKm);
    if (cadre == null) {
      _recenterOn(centre, zoom: _initialZoom);
      return;
    }
    _map.fitCamera(CameraFit.bounds(bounds: cadre));
  }

  Future<void> _openCluster(ShopCluster cluster) async {
    if (cluster.isSingle) {
      setState(() => _selected = cluster.single);
      return;
    }
    // Zoomer n'a de sens que si le groupe finit par se scinder. Deux
    // commerces à la même adresse — galerie marchande, même immeuble, ou
    // simplement deux fiches saisies au même point — occupent le même pixel
    // quel que soit le zoom : le rond zoomait alors indéfiniment dans le
    // vide en affichant toujours « 2 » (retour terrain 2026-07-30).
    //
    // Le test est exact et non approximatif : on rejoue le regroupement au
    // zoom maximal, celui où les cellules sont les plus fines. S'il ne
    // produit toujours qu'un groupe, aucun zoom ne les séparera jamais.
    final splitsEventually =
        clusterShops(cluster.shops, zoom: _maxClusterZoom).length > 1;
    if (!splitsEventually || _zoom >= _maxClusterZoom) {
      await _showClusterPicker(cluster);
      return;
    }
    setState(() => _selected = null);
    // `.clamp()` est déclaré sur `num` et renvoie `num` : sans `toDouble()`,
    // le type ne passe pas sur `MapController.move(LatLng, double)`.
    _map.move(cluster.center, (_zoom + 2).clamp(1.0, 18.0).toDouble());
  }

  /// Dernier recours quand le zoom ne peut plus départager : on liste les
  /// commerces du groupe et l'utilisateur choisit. Une carte doit toujours
  /// mener quelque part.
  ///
  /// ── ⚠️ Cette feuille liste des COMMERCES, pas des promos — décision du
  /// 2026-08-13, prise en connaissance de cause ─────────────────────────────
  ///
  /// L'objection est légitime et a été posée : l'app sert à chercher des
  /// **promos**, et c'est la seule surface où le commerçant est l'unité. Le fil
  /// client, la vitrine et l'écran de détail sont tous promo-centrés. Le
  /// marqueur lui-même parle en promos — il affiche « −XX % », la meilleure
  /// remise du point — et cette feuille répond par des noms de commerces : la
  /// question et la réponse ne sont pas dans la même monnaie.
  ///
  /// **Le changement ne coûterait rien au serveur** : `GET /promo/map` sert
  /// déjà les promos complètes sous chaque commerce (`toClientJson`), photos
  /// comprises, et `MapShopSheet` les affiche déjà une fois le commerce choisi.
  /// Seule cette étape intermédiaire est marchande.
  ///
  /// **Gardé tel quel malgré tout.** La réserve qui pèse : dix commerces à cinq
  /// promos font cinquante cartes dans une feuille, et trancher entre « tout
  /// lister » et « la meilleure par commerce » est un arbitrage d'écran qui
  /// n'était pas le sujet du jour. C'est écrit ici plutôt que laissé à
  /// deviner — sans ça, le prochain à ouvrir ce fichier reposera la même
  /// question et la croira neuve.
  Future<void> _showClusterPicker(ShopCluster cluster) async {
    setState(() => _selected = null);
    final chosen = await showModalBottomSheet<MapShop>(
      context: context,
      builder: (context) => _ClusterPicker(shops: cluster.shops),
    );
    if (chosen != null && mounted) setState(() => _selected = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final bounds = _bounds;
    final shopsAsync =
        bounds == null ? null : ref.watch(mapShopsProvider(bounds));
    final userPosition = ref.watch(userPositionProvider).valueOrNull;
    // Cascade unique : point enregistré → défaut serveur → repli hors ligne.
    // Elle est lue au même endroit par la liste et par la carte, sans quoi un
    // client sans point verrait l'une autour d'un lieu et l'autre autour d'un
    // autre (A4 du plan de bascule).
    final centreParDefaut = ref.watch(centreParDefautProvider);
    // `?? false` : tant qu'on ne sait pas, on ne propose rien — une invitation
    // affichée puis retirée est plus déroutante qu'une invitation tardive.
    final peutDemander =
        ref.watch(peutDemanderLocalisationProvider).valueOrNull ?? false;

    // ── ⚠️ Précédence : un point ENREGISTRÉ gagne sur le GPS ────────────────
    //
    // Un point enregistré est un **choix** ; le GPS est une **mesure**. Tant
    // que le client n'a rien enregistré, les deux sont à égalité — le défaut
    // servi par le serveur et la position du téléphone sont deux cadrages
    // également provisoires, et le premier disponible fait l'affaire. Dès
    // qu'un point est enregistré, il l'emporte : c'est ce que le client a
    // demandé, et une mesure n'a pas à défaire une décision.
    //
    // ⚠️ **C'était l'inverse jusqu'au 2026-08-13**, et le défaut se voyait mal
    // parce qu'il fallait être loin de sa ville pour le constater. Un client
    // qui avait enregistré Djelfa puis rouvrait l'app en voyage était emmené
    // là où était son téléphone, sans rien pour revenir sinon refaire le
    // geste. Mesuré au banc, sonde dans cet écran : `defaut = Djelfa`,
    // `gps = 37.42/-122.08` (position par défaut de l'émulateur), carte
    // cadrée sur la Californie et **zéro commerce** — le parcours carte
    // accusait la carte depuis.
    //
    // Le bouton « me localiser » reste là pour y aller **à la demande** : on
    // ne retire pas l'accès au GPS, on retire son autorité.
    final pointEnregistre = ref.watch(clientPositionProvider);
    if (pointEnregistre != null && !_centeredOnDefaultPoint) {
      _centeredOnDefaultPoint = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // ⚠️ **Le zoom du client, pas une constante.** Jusqu'au 2026-08-14 ce
          // centrage forçait `_initialZoom` : cadrer un quartier, enregistrer,
          // revenir sur la carte — et elle rouvrait en vue large. Le cadre
          // était bien enregistré (la liste, elle, le respectait), mais la
          // carte le jetait à chaque retour, ce qui donnait à croire que
          // l'enregistrement n'avait rien retenu.
          _cadrerSurLePoint(
            LatLng(pointEnregistre.latitude, pointEnregistre.longitude),
            pointEnregistre.rayonKm,
          );
        }
      });
    } else if (pointEnregistre == null &&
        userPosition != null &&
        !_centeredOnUser) {
      // Premier centrage sur l'utilisateur dès que sa position est connue —
      // après le premier rendu, sinon `MapController` n'est pas encore relié
      // à la carte.
      _centeredOnUser = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _recenterOn(userPosition, zoom: 15);
      });
    } else if (pointEnregistre == null &&
        userPosition == null &&
        !_centeredOnDefaultPoint) {
      // Pas de GPS : on ouvre sur le point du client s'il en a enregistré un,
      // sinon sur celui que sert le serveur.
      //
      // Zoom volontairement plus large que pour le GPS : ce centre est un
      // repère, pas une position mesurée. L'afficher au même zoom lui donnerait
      // une précision qu'il n'a pas.
      _centeredOnDefaultPoint = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _recenterOn(centreParDefaut, zoom: _initialZoom);
      });
    }

    // ── La proposition d'enregistrer une ville par défaut ────────────────
    //
    // Deux moments, un seul geste. Le mécanisme d'enregistrement existait
    // déjà — bouton flottant + consentement — mais **rien ne le proposait** :
    // il fallait remarquer un bouton libellé « Chercher autour de ce point »
    // pour comprendre qu'on pouvait fixer sa ville. Les deux scénarios client
    // du 2026-08-13 le demandent explicitement.
    //
    // ⚠️ **Le seuil vient du SERVEUR**, jamais d'une constante écrite ici : au
    // delà du rayon de recherche, le client regarde des promos qui
    // n'apparaîtront pas dans sa liste — c'est exactement le moment où la
    // proposition a du sens, et le jour où le rayon change elle suit
    // (règle 32).
    final rayonKm =
        ref.watch(clientGeoConfigProvider).valueOrNull?.defaultRadiusKm;
    final centre = _centreStabilise;
    _Proposition? proposition;
    if (centre != null && rayonKm != null) {
      if (pointEnregistre == null) {
        // Scénario 1 — aucune ville enregistrée. On propose dès que la carte
        // s'est posée quelque part, que ce soit sur le GPS ou sur le défaut
        // serveur : à ce stade les deux sont à égalité, et c'est justement au
        // client de trancher.
        if (!_premierPointEcarte) {
          proposition = _Proposition(
            message: l10n.savePointProposeFirst,
            centre: centre,
            onEcarter: () async {
              await ref.read(pointProposalStoreProvider).ecarterPremierPoint();
              if (mounted) setState(() => _premierPointEcarte = true);
            },
          );
        }
      } else {
        // Scénario 2 — une ville est enregistrée et le client en explore une
        // autre. `distanceTo` rend des mètres.
        final ecart = distanceTo(
            centre, pointEnregistre.latitude, pointEnregistre.longitude);
        final cle =
            PointProposalStore.cleDeVille(centre.latitude, centre.longitude);
        if (ecart != null && ecart > rayonKm * 1000 && cle != _villeEcartee) {
          proposition = _Proposition(
            message: l10n.savePointProposeArea,
            centre: centre,
            onEcarter: () async {
              await ref
                  .read(pointProposalStoreProvider)
                  .ecarterVille(centre.latitude, centre.longitude);
              if (mounted) setState(() => _villeEcartee = cle);
            },
          );
        }
      }
    }

    // Les points restent affichés pendant qu'une nouvelle zone se charge, et
    // même si elle échoue : une carte qui se vide à chaque geste donne
    // l'impression de tout recharger en permanence.
    final fresh = shopsAsync?.valueOrNull?.items;
    if (fresh != null && !identical(fresh, _lastShops)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _lastShops = fresh);
      });
    }
    final shops = fresh ?? _lastShops;
    final clusters = clusterShops(
      shops,
      zoom: _zoom >= _maxClusterZoom ? _maxClusterZoom : _zoom,
    );

    return Scaffold(
      // ⚠️ **C'est ici, et nulle part ailleurs, que naît le point du client.**
      //
      // Le geste est explicite et il porte sa notice : c'est lui qui vaut
      // consentement (A2.2 du plan). Il n'existe aucun chemin où accorder la
      // permission de localisation suffirait à enregistrer un point — se
      // centrer sur soi ne fait que **cadrer**, il faut encore valider. Cette
      // frontière est ce qui permet d'affirmer aux deux stores qu'il n'y a ni
      // suivi ni lecture en arrière-plan.
      floatingActionButton: _BoutonEnregistrerPoint(
        // ⚠️ Le bouton ne refait plus le geste, il l'appelle. Il portait sa
        // propre copie de la notice, du dialogue et de l'enregistrement — deux
        // chemins pour un seul consentement, et c'est celui qu'on oublie qui
        // aurait perdu le rayon (règle 30).
        onEnregistrer: () => _enregistrerPoint(_map.camera.center),
        repliee: _pastilleRepliee,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: centreParDefaut,
              initialZoom: _initialZoom,
              maxZoom: 18,
              minZoom: 5,
              onMapEvent: _onMapEvent,
              // Un clic hors marqueur referme la fiche, comme un retour.
              onTap: (_, __) => setState(() => _selected = null),
            ),
            children: [
              // Fond de carte volontairement minimal (CARTO Positron) plutôt
              // que le rendu OpenStreetMap standard : celui-ci est très
              // coloré et dense en détails (commerces, POI, routes
              // hiérarchisées), au point que les pastilles de réduction s'y
              // perdent. Un fond gris clair quasi blanc laisse le terracotta
              // des marqueurs être la seule couleur forte de l'écran.
              //
              // Toujours sans clé API ni facturation, mais attribution
              // obligatoire (CARTO + OpenStreetMap, ci-dessous).
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.echango.echango_promo',
                maxNativeZoom: 20,
              ),
              if (userPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: userPosition,
                      width: 22,
                      height: 22,
                      child: const _UserDot(),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final cluster in clusters)
                    Marker(
                      point: cluster.center,
                      width: cluster.isSingle ? 86 : 64,
                      height: cluster.isSingle ? 40 : 64,
                      child: _ClusterMarker(
                        cluster: cluster,
                        isSelected: cluster.isSingle &&
                            cluster.single.id == _selected?.id,
                        onTap: () => _openCluster(cluster),
                      ),
                    ),
                ],
              ),
              // Attribution obligatoire, pas décorative : OpenStreetMap est
              // sous ODbL (le crédit fait partie de la licence) et les fonds
              // CARTO gratuits l'imposent dans leurs conditions. La retirer
              // nous mettrait en infraction, et c'est le genre de point que
              // les magasins d'applications vérifient.
              //
              // Ce qu'on peut faire, et qu'on fait : la réduire au minimum.
              // `showFlutterMapAttribution: false` retire « made with
              // flutter_map », qui n'est qu'une politesse du paquet (option
              // prévue pour ça) et non une contrainte de licence. Et on la
              // pose à gauche : par défaut elle occupe le coin bas-droit,
              // exactement là où se trouve le bouton « me recentrer ».
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                showFlutterMapAttribution: false,
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                  TextSourceAttribution('CARTO'),
                ],
              ),
            ],
          ),

          // Barre du haut : retour à la liste, puis filtre par catégorie.
          SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _RoundButton(
                        icon: Icons.arrow_back,
                        tooltip: l10n.mapBackToList,
                        onTap: () => context.go('/'),
                      ),
                      const Spacer(),
                      if (shopsAsync?.isLoading ?? false)
                        const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                    ],
                  ),
                ),
                const _CategoryFilterBar(),
              ],
            ),
          ),

          if (shopsAsync?.hasError ?? false)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: _Banner(
                // Le message du backend quand il y en a un (code d'erreur
                // localisé), le texte générique sinon (panne réseau, DNS,
                // timeout). Afficher `mapLoadError` dans tous les cas rendait
                // indistinguables une zone rejetée par l'API et une absence
                // de réseau — donc impossible à diagnostiquer sur le terrain.
                message: extractApiErrorMessage(
                  shopsAsync!.error!,
                  fallback: l10n.mapLoadError,
                  locale: Localizations.localeOf(context),
                ),
                color: colorScheme.errorContainer,
                onColor: colorScheme.onErrorContainer,
              ),
            )
          else if ((shopsAsync?.valueOrNull?.truncated ?? false) &&
              _selected == null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: _Banner(
                message: l10n.mapTooManyShops,
                color: colorScheme.secondaryContainer,
                onColor: colorScheme.onSecondaryContainer,
              ),
            ),

          // ── L'invitation à activer la localisation ────────────────────
          //
          // ⚠️ **Ici, et nulle part avant.** Cette proposition vivait dans
          // l'onboarding, juste après un premier refus : Apple l'a refusée le
          // 2026-08-05 (5.1.1(iv), « encourages users to allow »). Elle est
          // désormais faite là où la fonction ne marche pas sans position —
          // ce qu'Apple suggère explicitement dans sa réponse.
          //
          // Trois conditions, et chacune compte : la permission doit être
          // encore DEMANDABLE (voir `peutDemanderLocalisationProvider` — un
          // `deniedForever` rendrait le bouton inerte), aucune fiche ne doit
          // être ouverte, et l'utilisateur ne doit pas l'avoir déjà écartée.
          // Sans cette dernière, l'invitation reviendrait à chaque ouverture
          // de la carte : la même proposition répétée n'est plus une
          // proposition.
          // ⚠️ **Un seul bandeau à la fois, et l'invitation passe devant.**
          // Activer la localisation est le préalable du scénario 1 : les
          // empiler proposerait au client de fixer une ville avant même de
          // savoir où il est, et deux sollicitations superposées se lisent
          // comme du harcèlement — c'est ce qu'Apple a refusé le 2026-08-05.
          if (proposition != null &&
              _selected == null &&
              !(peutDemander && !_invitationEcartee))
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: _PropositionPoint(
                message: proposition.message,
                onEnregistrer: () => _enregistrerPoint(proposition!.centre,
                    viaProposition: true),
                onEcarter: proposition.onEcarter,
              ),
            ),

          if (peutDemander && _selected == null && !_invitationEcartee)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: _InvitationLocalisation(
                onActiver: () async {
                  final accorde = await demanderPermissionLocalisation();
                  if (!context.mounted) return;
                  ref.invalidate(userPositionProvider);
                  ref.invalidate(peutDemanderLocalisationProvider);
                  if (accorde) setState(() => _invitationEcartee = true);
                },
              ),
            ),

          // Masqué plutôt que désactivé quand la position est inconnue : un
          // bouton "me localiser" présent mais inerte laisse croire à une
          // panne, alors que la localisation a simplement été refusée.
          if (userPosition != null && _selected == null)
            PositionedDirectional(
              end: 16,
              bottom: 24,
              child: _RoundButton(
                icon: Icons.my_location,
                tooltip: l10n.mapRecenter,
                onTap: () => _recenterOn(userPosition, zoom: 15),
              ),
            ),

          if (_selected != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: MapShopSheet(
                shop: _selected!,
                distanceMeters: distanceTo(
                  userPosition,
                  _selected!.latitude,
                  _selected!.longitude,
                ),
                onPromoTap: (promo) => context.push('/promo/${promo.id}'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClusterMarker extends StatelessWidget {
  const _ClusterMarker({
    required this.cluster,
    required this.isSelected,
    required this.onTap,
  });

  final ShopCluster cluster;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (cluster.isSingle) {
      final discount = cluster.single.bestDiscountPercent;
      return GestureDetector(
        onTap: onTap,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected ? colorScheme.onSurface : colorScheme.primary,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              border: Border.all(color: colorScheme.onPrimary, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              discount != null ? '−$discount%' : cluster.single.nom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    // Le rond grossit avec le nombre de commerces qu'il regroupe — le halo
    // reprend le code visuel universel du clustering cartographique.
    final size =
        cluster.count >= 20 ? 60.0 : (cluster.count >= 8 ? 52.0 : 44.0);
    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.28),
                blurRadius: 0,
                spreadRadius: 6,
              ),
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.28),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            '${cluster.promoCount}',
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Filtre par catégorie, en pastilles flottantes au-dessus de la carte.
///
/// Pilote le **même** `categoryFilterProvider` que les ronds de l'accueil :
/// un filtre choisi ici reste actif en revenant à la liste, et
/// inversement. Deux filtres indépendants pour la même notion se
/// contrediraient à l'écran sans que le client comprenne pourquoi.
///
/// Aucune requête supplémentaire : `mapShopsProvider` observe déjà ce
/// provider, et le filtrage se fait côté serveur (`GET /promo/map`) plutôt
/// que sur les commerces déjà chargés — sinon les commerces d'une autre
/// catégorie occuperaient le plafond de `MAX_MAP_COMMERCANTS` pour rien.
///
/// Pastilles et non ronds illustrés comme sur l'accueil : au-dessus d'un
/// fond cartographique, un libellé lisible prime sur l'image, et la barre
/// doit manger le moins de carte possible.
/// Liste des commerces d'un groupe que le zoom ne peut pas départager.
///
/// Sans ça, deux fiches saisies au même point restaient inatteignables :
/// le rond affichait « 2 » et zoomer n'y changeait rien.
class _ClusterPicker extends StatelessWidget {
  const _ClusterPicker({required this.shops});

  final List<MapShop> shops;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            // ── ⚠️ Le titre compte des PROMOS, le sous-titre des commerces ──
            //
            // Il n'annonçait que des commerces, et ça a fait buter trois fois
            // le même jour : « 15 promos dans la liste, 3 sur la carte », puis
            // « Autre 4 + Alimentation 22 = 26, mais Toutes 24 ». Les deux
            // fois, le produit avait raison — un ensemble de LIEUX ne
            // s'additionne pas comme un ensemble de promos, parce qu'un
            // commerce dont les promos sont dans deux catégories est compté
            // dans les deux filtres et une seule fois dans « Toutes ».
            //
            // Le chiffre restait donc juste et **illisible** : il répondait en
            // boutiques à un filtre qui parle en catégories de promos, sur une
            // app dont l'objet est de chercher des promos.
            //
            // ⚠️ Les deux nombres sont montrés, pas l'un à la place de l'autre :
            // la liste dessous énumère des commerces, et n'afficher qu'un
            // total de promos rendrait ce qu'on lit incompréhensible à son
            // tour. Chaque nombre dit ce qu'il compte.
            //
            // Composé à partir des deux clés existantes plutôt qu'une
            // troisième : une clé de plus, c'est trois fichiers `.arb` à tenir
            // en phase pour une phrase que ceux-ci disent déjà (règle 27).
            child: Text(
              '${l10n.promoCount(shops.fold<int>(0, (n, s) => n + s.promos.length))}'
              ' · ${l10n.mapShopsHere(shops.length)}',
              style: textTheme.titleMedium,
            ),
          ),
          // `Flexible` + `shrinkWrap` : la feuille s'ajuste à deux commerces
          // comme à dix, sans occuper l'écran entier pour rien.
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: shops.length,
              itemBuilder: (context, index) {
                final shop = shops[index];
                final discount = shop.bestDiscountPercent;
                return ListTile(
                  leading: ClipOval(
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: shop.photoUrl == null
                          ? Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.storefront_outlined,
                                color: colorScheme.outline,
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: shop.photoUrl!,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                  color: colorScheme.surfaceContainerHighest),
                              errorWidget: (context, url, error) => Container(
                                  color: colorScheme.surfaceContainerHighest),
                            ),
                    ),
                  ),
                  title: Text(shop.nom,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${categorieLabel(context, shop.categorie)} · '
                    '${l10n.promoCount(shop.promos.length)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: discount == null
                      ? null
                      : Text(
                          '−$discount%',
                          style: textTheme.labelLarge?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                  onTap: () => Navigator.pop(context, shop),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _CategoryFilterBar extends ConsumerWidget {
  const _CategoryFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final selected = ref.watch(categoryFilterProvider);

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _CategoryChip(
            label: l10n.allCategoriesChip,
            selected: selected == null,
            onTap: () => ref.read(categoryFilterProvider.notifier).state = null,
          ),
          for (final categorie in Categorie.values) ...[
            const SizedBox(width: 8),
            _CategoryChip(
              label: categorieLabel(context, categorie),
              selected: selected == categorie,
              // Retaper la catégorie active la retire : sans ça, revenir à
              // "toutes" obligerait à viser la première pastille, souvent
              // hors écran après avoir fait défiler la barre.
              onTap: () => ref.read(categoryFilterProvider.notifier).state =
                  selected == categorie ? null : categorie,
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: selected ? colorScheme.primary : colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      // Ombre portée : au-dessus d'une carte, une pastille sans relief se
      // confond avec le fond dès qu'elle passe sur une zone claire.
      elevation: 2,
      shadowColor: colorScheme.shadow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Center(
            child: Text(
              label,
              style: textTheme.labelLarge?.copyWith(
                color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton(
      {required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon),
        tooltip: tooltip,
        color: colorScheme.onSurface,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(
      {required this.message, required this.color, required this.onColor});

  final String message;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(AppRadii.md),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style:
              Theme.of(context).textTheme.bodyMedium?.copyWith(color: onColor),
        ),
      ),
    );
  }
}

/// Position de l'utilisateur. Bleu volontairement hors palette de l'app :
/// c'est la convention cartographique universelle, la reconnaître prime sur
/// la cohérence chromatique.
class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1F6FEB);
    return Container(
      decoration: BoxDecoration(
        color: blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
              color: blue.withValues(alpha: 0.3),
              blurRadius: 0,
              spreadRadius: 5),
        ],
      ),
    );
  }
}

/// Invitation discrète à activer la localisation, posée sur la carte.
///
/// Un bandeau, pas un écran : la carte est déjà là, et la couvrir d'une
/// proposition plein écran reviendrait à redemander avant de laisser voir —
/// exactement ce qui a été refusé.
/// Ce qu'il y a à proposer, et où. `null` quand il n'y a rien à proposer —
/// jamais un objet « vide » qu'il faudrait interroger pour le savoir.
class _Proposition {
  const _Proposition({
    required this.message,
    required this.centre,
    required this.onEcarter,
  });

  final String message;
  final LatLng centre;
  final Future<void> Function() onEcarter;
}

/// Bandeau proposant de fixer la ville par défaut.
///
/// Même forme que `_InvitationLocalisation` volontairement : ce sont deux
/// propositions du même écran, et leur donner deux apparences ferait croire à
/// deux natures.
class _PropositionPoint extends StatelessWidget {
  const _PropositionPoint({
    required this.message,
    required this.onEnregistrer,
    required this.onEcarter,
  });

  final String message;
  final Future<void> Function() onEnregistrer;
  final Future<void> Function() onEcarter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(AppRadii.md),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: colorScheme.onSecondaryContainer,
                  tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                  onPressed: onEcarter,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onEcarter,
                  child: Text(l10n.savePointProposeLater),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onEnregistrer,
                  child: Text(l10n.savePointProposeAccept),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// L'explication affichée AVANT la boîte de dialogue système.
///
/// ⚠️ **Un seul bouton, et il mène TOUJOURS à la demande système.** C'est la
/// condition posée par Apple le 2026-08-08 (deuxième refus 5.1.1(iv)) : un
/// message maison a le droit d'expliquer *pourquoi*, il n'a pas le droit de
/// devenir une décision.
///
/// Ce bandeau portait exactement les deux motifs nommés dans ce refus, et ils
/// ont été retirés à la fusion du 2026-08-14 :
///   · une **croix** qui fermait le message sans que la demande système ait
///     lieu — c'est le « second bouton » qu'Apple refuse, sous forme d'icône ;
///   · un libellé qui **encourage** (« Activer la localisation ») là où Apple
///     demande « Continuer » ou « Suivant ».
///
/// Un texte à l'impératif (« Activez la localisation pour… ») est interdit pour
/// la même raison : il encourage autant qu'un bouton. `mapLocationInvite` décrit
/// une conséquence, il ne demande rien.
///
/// ⚠️ **Et il ne harcèle pas pour autant** — ce qui était la raison d'être de la
/// croix. Le bandeau n'est affiché que tant que la permission est encore
/// DEMANDABLE (`peutDemanderLocalisationProvider`) : un seul geste suffit à le
/// faire disparaître, quelle que soit la réponse donnée à la boîte système.
class _InvitationLocalisation extends StatelessWidget {
  const _InvitationLocalisation({required this.onActiver});

  final Future<void> Function() onActiver;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(AppRadii.md),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.mapLocationInvite,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                  ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: onActiver,
                child: Text(l10n.onboardingLocationContinue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Enregistre le centre courant de la carte comme point de recherche du client.
///
/// ⚠️ **La notice est affichée AVANT l'enregistrement, pas après.** Un
/// consentement qui arrive une fois la donnée posée n'en est pas un — et c'est
/// cette boîte de dialogue, avec sa phrase, qui rend vraie l'affirmation faite
/// aux stores : le client sait ce qu'il envoie, pourquoi, et qu'il peut le
/// reprendre.
///
/// ⚠️ Le bouton bascule en « oublier mon point » quand il y en a un : le
/// retrait doit être aussi accessible que l'octroi, sinon le consentement n'est
/// pas reprenable.
/// ⚠️ Replié, ce bouton n'est plus qu'un rond : le libellé disparaît de
/// l'écran, donc il doit rester atteignable autrement. `tooltip` le porte — il
/// s'affiche en bulle sur appui long **et** il est ce que lisent les lecteurs
/// d'écran, pour qui la pastille étendue et le rond doivent dire la même chose.
///
/// ⚠️ **Ce bouton ne porte plus le geste, il l'appelle.** Il en avait sa propre
/// copie — même dialogue, même notice, même appel — à côté de celle de
/// `_enregistrerPoint`, utilisée par la proposition d'exploration. Deux chemins
/// pour un seul consentement : le 2026-08-14, en faisant porter le zoom au
/// rayon, c'est exactement le genre d'endroit où l'un des deux serait resté en
/// arrière sans que rien ne le signale (règle 30).
class _BoutonEnregistrerPoint extends ConsumerWidget {
  const _BoutonEnregistrerPoint({
    required this.onEnregistrer,
    this.repliee = false,
  });

  /// Le geste complet — notice, consentement, enregistrement, invalidation —
  /// tenu par l'écran, pas ici.
  final Future<void> Function() onEnregistrer;

  /// Rond (icône seule) plutôt que pastille étendue. `isExtended` anime la
  /// transition tout seul : pas de widget supplémentaire, pas d'animation à
  /// écrire.
  final bool repliee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final dejaPose = ref.watch(clientPositionProvider) != null;
    final libelle = dejaPose ? l10n.forgetPointAction : l10n.savePointAction;

    return FloatingActionButton.extended(
      isExtended: !repliee,
      tooltip: libelle,
      icon: Icon(dejaPose ? Icons.wrong_location_outlined : Icons.my_location),
      label: Text(libelle),
      onPressed: () async {
        if (dejaPose) {
          // Le retrait reste ici : il n'a ni notice ni cadrage à porter, et
          // l'extraire créerait un aller-retour pour un `clear()`.
          await ref.read(clientPositionProvider.notifier).retirer();
          if (context.mounted) invalidateAfterPositionChange(ref);
          return;
        }
        await onEnregistrer();
      },
    );
  }
}
