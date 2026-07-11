import 'package:flutter/material.dart';
import '../../../app/theme.dart';

/// Badge de statut coloré (fond teinté + bordure + texte de la même
/// couleur, lisible quel que soit le thème clair/sombre) — dupliqué entre
/// la fiche promo et la fiche commerçant admin (CLAUDE.md règle #21).
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
