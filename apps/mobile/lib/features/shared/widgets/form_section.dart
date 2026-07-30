import 'package:flutter/material.dart';
import '../../../app/theme.dart';

/// Groupe de champs sous un titre, encadré. Sert à découper les formulaires
/// longs (profil commerçant, formulaire de promo) en étapes lisibles : un
/// écran de dix champs à la suite ne dit pas où l'on en est ni ce qui reste.
///
/// Extrait dès la deuxième utilisation (règle d'audit #21).
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
    this.tone,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// Couleur du titre et du cadre. `null` = neutre. Sert à distinguer une
  /// section destructrice (suppression de compte) du reste du formulaire.
  final Color? tone;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = tone ?? colorScheme.onSurface;
    final border = tone?.withValues(alpha: 0.4) ?? colorScheme.outlineVariant;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: border, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: tone ?? colorScheme.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(color: accent),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
