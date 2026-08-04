# Visuels de catégorie

Images affichées dans les ronds de catégorie de l'accueil client
(`promo_list_screen.dart`). **Facultatives** : tant qu'un fichier est absent,
l'app retombe automatiquement sur l'icône Material correspondante, sans
erreur ni trou dans l'interface.

## Noms de fichiers attendus

Le nom doit correspondre exactement à la valeur de l'enum `Categorie`
(`lib/domain/enums/categorie.dart`, miroir de `categorie.enum.ts` côté
backend) — c'est ce qui permet d'ajouter une catégorie sans toucher au code
d'affichage :

| Fichier | Catégorie |
|---|---|
| `alimentation.jpg` | Alimentation |
| `restauration.jpg` | Restauration |
| `vetements_textile.jpg` | Vêtements / Textile |
| `electromenager.jpg` | Électroménager |
| `beaute_hygiene.jpg` | Beauté / Hygiène |
| `maison_ameublement.jpg` | Maison / Ameublement |
| `autre.jpg` | Autre |

## Contraintes

- **Format** : `.jpg` (l'extension est en dur dans `categorieAssetPath()`).
- **Cadrage carré**, l'image est rognée en cercle et centrée
  (`BoxFit.cover`) : ce qui compte doit être au milieu, pas sur les bords.
- **Taille** : viser 240 × 240 px. Les ronds font 56 dp au maximum, donc
  ~168 px sur un écran à 3× — au-delà c'est du poids d'app pour rien.
- Prévoir des visuels lisibles **en petit** : une photo détaillée devient
  illisible à 42 dp (taille des ronds en mode filtré). Un objet unique,
  cadré serré, fond uni fonctionne mieux qu'une scène.

Après avoir déposé les fichiers, relancer `flutter pub get` (ou un
redémarrage complet de l'app — un hot reload ne recharge pas le manifeste
d'assets).
