import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../l10n/app_localizations.dart';

/// Capture optionnelle de la position GPS du commerce — gratuit, aucune clé
/// API Google Maps nécessaire (juste la localisation native de l'appareil).
class LocationCaptureField extends StatefulWidget {
  const LocationCaptureField({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.onChanged,
  });

  final double? latitude;
  final double? longitude;
  final void Function(double latitude, double longitude) onChanged;

  @override
  State<LocationCaptureField> createState() => _LocationCaptureFieldState();
}

class _LocationCaptureFieldState extends State<LocationCaptureField> {
  bool _locating = false;
  String? _error;

  Future<void> _locate() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _locating = true;
      _error = null;
    });

    // Message localisé posé directement, jamais `'$error'` : une exception
    // brute s'affichait telle quelle au commerçant — préfixe « Exception: »
    // pour nos propres messages, et texte anglais du framework pour les
    // autres (`TimeoutException after 0:00:12...`).
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _fail(l10n.locationEnableService);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _fail(l10n.locationPermissionDenied);
        return;
      }

      // `medium` (~100-500 m) et une limite explicite : `high` force un
      // verrou GPS satellite qui peut dépasser 30 s en intérieur — or un
      // commerce se trouve précisément à l'intérieur. Retour terrain
      // 2026-07-30 : le bouton restait bloqué, le commerçant enregistrait
      // avant que la position n'arrive, et la fiche partait sans
      // coordonnées (donc absente de la carte, sans le moindre message).
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } on Exception {
        // Repli sur la dernière position connue de l'appareil : à l'échelle
        // d'un commerce de quartier elle reste exploitable, et vaut
        // infiniment mieux qu'une fiche sans position.
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) {
        _fail(l10n.locationUnavailable);
        return;
      }
      widget.onChanged(position.latitude, position.longitude);
    } catch (_) {
      _fail(l10n.locationUnavailable);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final located = widget.latitude != null && widget.longitude != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          icon: Icon(located ? Icons.check_circle_outline : Icons.my_location_outlined),
          label: Text(located ? l10n.locationSaved : l10n.locationCapture),
          onPressed: _locating ? null : _locate,
        ),
        if (_locating)
          const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        // Coordonnées affichées en clair : le commerçant voit que quelque
        // chose a réellement été capté, plutôt qu'un libellé de bouton qui
        // change. Sert aussi au support — une position aberrante se repère
        // à l'œil.
        if (located && !_locating)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${widget.latitude!.toStringAsFixed(5)}, ${widget.longitude!.toStringAsFixed(5)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }
}
