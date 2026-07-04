import 'package:flutter/material.dart';

/// Message d'erreur de formulaire — même bloc `if (_error != null) ...`
/// répété dans la quasi-totalité des écrans (audit qualité de code).
/// Occupe un espace nul (`SizedBox.shrink`) quand `message` est null, donc
/// utilisable inconditionnellement dans une liste de widgets.
class ErrorText extends StatelessWidget {
  const ErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(message!, style: const TextStyle(color: Colors.red)),
    );
  }
}
