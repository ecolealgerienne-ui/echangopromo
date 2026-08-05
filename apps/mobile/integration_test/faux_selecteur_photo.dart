/// Double du sélecteur de photos **du système**, pour le parcours de création
/// de promo.
///
/// ── Ce qui est simulé, et ce qui ne l'est surtout pas ────────────────────
///
/// Ce qui est remplacé : la galerie Android, c'est-à-dire une application
/// tierce qui s'ouvre par-dessus la nôtre. `integration_test` pilote notre
/// arbre de widgets, pas celui du système : sans ce double, le parcours
/// s'arrête sur une fenêtre qu'il ne peut ni voir ni toucher.
///
/// Ce qui reste réel : **tout le reste**. Le tap sur l'emplacement photo, la
/// feuille « appareil / galerie », la compression, l'upload multipart vers
/// `POST /storage/upload`, l'écriture dans MinIO, la création de la promo, le
/// retour à l'écran précédent et le compteur qui s'incrémente. Le seul geste
/// escamoté est celui qu'aucun test ne peut faire.
///
/// ── Pourquoi l'icône de l'app comme photo ────────────────────────────────
///
/// `assets/images/brand/icon-master-terracotta-1024.png` est un vrai PNG de
/// 1024×1024, déjà déclaré dans `pubspec.yaml` pour l'app elle-même. Il
/// traverse donc la compression comme une vraie photo le ferait.
///
/// Fabriquer un JPEG minimal en base64 dans le test aurait été plus court et
/// bien pire : une image de 1×1 pixel ne fait rien travailler à la chaîne de
/// compression, et un blob recopié qui se révèle mal formé fait échouer le
/// parcours en accusant l'upload.
///
/// ── Ce que ce double REFUSE de faire ─────────────────────────────────────
///
/// Il n'invente rien. Il retient la source demandée (galerie ou appareil
/// photo) et le nombre d'appels, pour que le parcours puisse affirmer que le
/// chemin emprunté est bien celui qu'il croit avoir emprunté. Un double qui
/// rendrait la même photo quelle que soit la demande laisserait passer un tap
/// parti sur la mauvaise entrée de la feuille (règle #29 : pas de valeur de
/// repli qui détruit l'information).
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String cheminAssetPhoto =
    'assets/images/brand/icon-master-terracotta-1024.png';

class FauxSelecteurPhoto extends ImagePickerPlatform {
  FauxSelecteurPhoto(this._chemin);

  final String _chemin;

  /// Nombre de fois où l'app a réellement demandé une photo au système.
  int appels = 0;

  /// La dernière source demandée — `null` tant que rien n'a été demandé.
  ///
  /// ⚠️ Pas de valeur par défaut : « galerie » posé d'office rendrait
  /// indiscernable « l'app a demandé la galerie » de « l'app n'a rien
  /// demandé ».
  ImageSource? derniereSource;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    appels++;
    derniereSource = source;
    return XFile(_chemin);
  }
}

/// Installe le double et rend l'objet, pour que le parcours puisse
/// l'interroger.
///
/// L'image est copiée dans le dossier temporaire de l'appareil : le sélecteur
/// système rend un chemin de fichier, pas des octets, et c'est un `File` que
/// `MultiPhotoPickerField` construit ensuite.
Future<FauxSelecteurPhoto> installerFauxSelecteurPhoto() async {
  final donnees = await rootBundle.load(cheminAssetPhoto);
  final dossier = await getTemporaryDirectory();
  final fichier = File(p.join(dossier.path, 'photo-parcours.png'));
  await fichier.writeAsBytes(donnees.buffer.asUint8List(), flush: true);

  final faux = FauxSelecteurPhoto(fichier.path);
  ImagePickerPlatform.instance = faux;
  return faux;
}
