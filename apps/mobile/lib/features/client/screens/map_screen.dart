import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../app/theme.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/map_shop.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/location_providers.dart';
import '../providers/map_providers.dart';
import '../utils/marker_cluster.dart';
import '../widgets/map_shop_sheet.dart';

/// Centre de repli : Djelfa, le quartier pilote. Utilisé tant que la
/// position de l'utilisateur n'est pas connue (localisation refusée, service
/// coupé, ou position pas encore remontée) — une carte centrée sur l'océan
/// serait inexploitable.
const _fallbackCenter = LatLng(34.6703, 3.2630);
const _initialZoom = 13.0;

/// Au-delà de ce zoom, deux commerces distincts ne se chevauchent plus :
/// inutile de continuer à les regrouper.
const _maxClusterZoom = 17.0;

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

  /// La position arrive de façon asynchrone, après le premier rendu :
  /// `initialCenter` est déjà consommé à ce moment-là, il faut donc déplacer
  /// la caméra une fois. Ce drapeau évite de la ramener sur l'utilisateur à
  /// chaque reconstruction, ce qui empêcherait toute exploration manuelle.
  bool _centeredOnUser = false;

  @override
  void dispose() {
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
    // Ne recharger que si la zone regardée sort de ce qui est déjà chargé.
    // Zoomer, ou se déplacer dans la marge, n'appelle donc plus le serveur :
    // les commerces sont déjà là, seul le regroupement change. Dézoomer
    // découvre en revanche du terrain neuf et reste une vraie requête.
    final loaded = _bounds;
    final needsFetch = loaded == null || !loaded.contains(next);
    final zoomChanged = camera.zoom != _zoom;
    if (!needsFetch && !zoomChanged) return;
    // Différé d'une frame : certains événements de la carte sont émis
    // pendant la phase de layout (redimensionnement initial), et un
    // `setState` synchrone y déclencherait "setState() called during build".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        if (needsFetch) _bounds = next.padded();
        _zoom = camera.zoom;
      });
    });
  }

  void _recenterOn(LatLng position, {double? zoom}) {
    _map.move(position, zoom ?? (_zoom < 14 ? 15.0 : _zoom));
  }

  void _openCluster(ShopCluster cluster) {
    if (cluster.isSingle) {
      setState(() => _selected = cluster.single);
      return;
    }
    // Un rond représente plusieurs commerces : il ne peut pas ouvrir une
    // fiche, il zoome pour se scinder.
    setState(() => _selected = null);
    // `.clamp()` est déclaré sur `num` et renvoie `num` : sans `toDouble()`,
    // le type ne passe pas sur `MapController.move(LatLng, double)`.
    _map.move(cluster.center, (_zoom + 2).clamp(1.0, 18.0).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final bounds = _bounds;
    final shopsAsync =
        bounds == null ? null : ref.watch(mapShopsProvider(bounds));
    final userPosition = ref.watch(userPositionProvider).valueOrNull;

    // Premier centrage sur l'utilisateur dès que sa position est connue —
    // après le premier rendu, sinon `MapController` n'est pas encore relié
    // à la carte.
    if (userPosition != null && !_centeredOnUser) {
      _centeredOnUser = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _recenterOn(userPosition, zoom: 15);
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
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _fallbackCenter,
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
                        isSelected: cluster.isSingle && cluster.single.id == _selected?.id,
                        onTap: () => _openCluster(cluster),
                      ),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                  TextSourceAttribution('CARTO'),
                ],
              ),
            ],
          ),

          // Barre du haut : retour à la liste.
          SafeArea(
            child: Padding(
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
          else if ((shopsAsync?.valueOrNull?.truncated ?? false) && _selected == null)
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
    final size = cluster.count >= 20 ? 60.0 : (cluster.count >= 8 ? 52.0 : 44.0);
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

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});

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
  const _Banner({required this.message, required this.color, required this.onColor});

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
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: onColor),
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
          BoxShadow(color: blue.withValues(alpha: 0.3), blurRadius: 0, spreadRadius: 5),
        ],
      ),
    );
  }
}
