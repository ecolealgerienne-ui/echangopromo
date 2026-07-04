import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

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
    setState(() {
      _locating = true;
      _error = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Active la localisation sur ton téléphone.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permission de localisation refusée.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      widget.onChanged(position.latitude, position.longitude);
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final located = widget.latitude != null && widget.longitude != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          icon: Icon(located ? Icons.check_circle_outline : Icons.my_location_outlined),
          label: Text(located ? 'Position enregistrée — relocaliser' : 'Localiser mon commerce (optionnel)'),
          onPressed: _locating ? null : _locate,
        ),
        if (_locating)
          const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
      ],
    );
  }
}
