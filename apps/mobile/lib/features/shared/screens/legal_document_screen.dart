import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

/// Écran statique CGU/politique de confidentialité (plan de correction,
/// Phase 4) — texte à valider/compléter par un juriste avant ouverture
/// publique (spec §7.4), affiché ici tel quel en attendant.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen.cgu({super.key}) : _isPrivacy = false;
  const LegalDocumentScreen.privacy({super.key}) : _isPrivacy = true;

  final bool _isPrivacy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = _isPrivacy ? l10n.legalPrivacyTitle : l10n.legalCguTitle;
    final content =
        _isPrivacy ? l10n.legalPrivacyContent : l10n.legalCguContent;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          for (final paragraph in content.split('\n\n'))
            _LegalParagraph(text: paragraph.trim()),
        ],
      ),
    );
  }
}

/// Un paragraphe du texte légal. Les intertitres numérotés (« 1. Objet »)
/// sont détectés et mis en valeur : le contenu arrive en une seule chaîne
/// depuis les fichiers `.arb`, sans balisage, et s'affichait jusqu'ici en un
/// bloc uniforme illisible sur un écran de téléphone.
class _LegalParagraph extends StatelessWidget {
  const _LegalParagraph({required this.text});

  final String text;

  /// Un intertitre est une ligne courte commençant par « N. ».
  static final _headingPattern = RegExp(r'^\d+\.\s');

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final lines = text.split('\n');
    final firstLine = lines.first;
    final isSection = _headingPattern.hasMatch(firstLine);

    if (!isSection) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          text,
          style: textTheme.bodyMedium?.copyWith(
            height: 1.6,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final body = lines.skip(1).join('\n').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(firstLine,
              style:
                  textTheme.titleSmall?.copyWith(color: colorScheme.primary)),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              body,
              style: textTheme.bodyMedium?.copyWith(
                height: 1.6,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
