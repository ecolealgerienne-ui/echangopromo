import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../app/theme.dart';
import '../../../data/api/api_exception.dart';
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
  /// Lue une fois au démarrage de l'écran : le magasin est synchrone, mais on
  /// veut aussi pouvoir la masquer immédiatement après un geste, sans relire.
  late bool _invitationEcartee =
      ref.read(locationInviteStoreProvider).isDismissed();

  final MapController _map = MapController();

  /// Zone **chargée**, volontairement plus large que l'écran — pas la zone
  /// visible. Sert de clé au provider : tant que ce qu'on regarde tient
  /// dedans, aucune requête n'est relancée.
  MapBounds? _bounds;
  double _zoom = _initialZoom;
  MapShop? _selected;

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
  void dispose() {
    _settle?.cancel();
    _map.dispose();
    super.dispose();
  }

  /// Appelé à la fin de chaque déplacement/zoom : `MapCamera` n'est pas
  /// disponible avant le premier rendu, d'où la mise à jour ici plutôt qu'en
  /// `initState`.
  void _onMapEvent(MapEvent event) {
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
      if (!needsFetch && camera.zoom == _zoom) return;
      setState(() {
        if (needsFetch) _bounds = next.padded();
        _zoom = camera.zoom;
      });
    });
  }

  void _recenterOn(LatLng position, {double? zoom}) {
    _map.move(position, zoom ?? (_zoom < 14 ? 15.0 : _zoom));
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
          _recenterOn(
            LatLng(pointEnregistre.$1, pointEnregistre.$2),
            zoom: _initialZoom,
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
        centreCourant: () => _map.camera.center,
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
                onEcarter: () async {
                  await ref.read(locationInviteStoreProvider).markDismissed();
                  if (!context.mounted) return;
                  setState(() => _invitationEcartee = true);
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
            '${cluster.count}',
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
            child: Text(l10n.mapShopsHere(shops.length),
                style: textTheme.titleMedium),
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
class _InvitationLocalisation extends StatelessWidget {
  const _InvitationLocalisation({
    required this.onActiver,
    required this.onEcarter,
  });

  final Future<void> Function() onActiver;
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
                    l10n.mapLocationInvite,
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
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: onActiver,
                child: Text(l10n.onboardingLocationEnable),
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
class _BoutonEnregistrerPoint extends ConsumerWidget {
  const _BoutonEnregistrerPoint({required this.centreCourant});

  final LatLng Function() centreCourant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final dejaPose = ref.watch(clientPositionProvider) != null;

    return FloatingActionButton.extended(
      icon: Icon(dejaPose ? Icons.wrong_location_outlined : Icons.my_location),
      label: Text(dejaPose ? l10n.forgetPointAction : l10n.savePointAction),
      onPressed: () async {
        final controleur = ref.read(clientPositionProvider.notifier);
        if (dejaPose) {
          await controleur.retirer();
          if (context.mounted) invalidateAfterPositionChange(ref);
          return;
        }

        final centre = centreCourant();
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
                child:
                    Text(AppLocalizations.of(dialogContext)!.savePointAction),
              ),
            ],
          ),
        );
        if (accepte != true) return;

        await controleur.enregistrer(centre.latitude, centre.longitude);
        if (!context.mounted) return;
        // ⚠️ Sans cette invalidation, la vitrine et la carte garderaient leur
        // cadrage d'avant : elles ne sont pas reconstruites de zéro au retour
        // d'une boîte de dialogue (règle #37).
        invalidateAfterPositionChange(ref);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.savePointDone)),
        );
      },
    );
  }
}
