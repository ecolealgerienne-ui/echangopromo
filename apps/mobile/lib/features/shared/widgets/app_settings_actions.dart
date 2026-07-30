import 'package:flutter/material.dart';
import 'language_switcher_button.dart';
import 'theme_mode_button.dart';

/// Réglages d'affichage à placer dans les `actions` d'une `AppBar` : bascule
/// clair/sombre puis choix de la langue.
///
/// Regroupés dans un seul widget parce que les deux boutons doivent
/// apparaître ensemble sur les 22 écrans qui portent une `AppBar` : les
/// ajouter séparément garantissait d'en oublier un, et c'est précisément ce
/// qui s'est produit quand la bascule de thème n'a été posée que sur
/// l'accueil client. Le prochain réglage d'affichage s'ajoute ici, une fois.
class AppSettingsActions extends StatelessWidget {
  const AppSettingsActions({super.key});

  @override
  Widget build(BuildContext context) {
    // `mainAxisSize.min` : dans une liste `actions`, un Row non borné
    // occuperait toute la largeur restante et pousserait le titre.
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [ThemeModeButton(), LanguageSwitcherButton()],
    );
  }
}
