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
    final content = _isPrivacy ? l10n.legalPrivacyContent : l10n.legalCguContent;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(content),
      ),
    );
  }
}
