import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Cible réelle après compression (specs §5.8, décision 2026-07-12) — le
/// plafond serveur de 500 Ko (`MAX_UPLOAD_BYTES`) n'est qu'une sécurité, pas
/// l'objectif : 5 Mo était beaucoup trop généreux pour le marché algérien
/// (coût data, couverture réseau variable à Djelfa). S'applique aussi bien
/// aux photos promo/commerce qu'au document de registre de commerce — une
/// seule règle de compression, plutôt qu'un cas particulier par `purpose`.
const _targetBytes = 250 * 1024;

/// Paliers largeur/qualité essayés dans l'ordre jusqu'à passer sous
/// `_targetBytes` — repartir à chaque palier de l'original (jamais d'un
/// résultat déjà compressé) pour ne pas cumuler les artefacts de
/// recompression JPEG. Le dernier palier (le plus agressif) sert de filet :
/// si même lui dépasse la cible, on l'envoie quand même plutôt que
/// d'échouer l'upload ou de dégrader encore plus l'image.
const _compressionSteps = [
  (width: 1200, quality: 80),
  (width: 1200, quality: 60),
  (width: 900, quality: 60),
  (width: 900, quality: 45),
  (width: 700, quality: 45),
  (width: 700, quality: 35),
];

/// Upload proxifié par notre backend (pas de POST policy S3 pré-signée) :
/// OVH (le S3 utilisé en prod) ne supporte pas l'API S3 "POST Object"
/// (`501 Not Implemented`, découvert au premier test réel post-
/// déploiement) — le fichier transite donc par notre API, qui valide
/// taille et format avant de l'envoyer elle-même à S3.
class StorageApi {
  StorageApi(this._dio);

  /// Dio authentifié (JWT + device-id) — l'upload passe maintenant par
  /// notre backend, plus par un POST direct vers S3, donc plus besoin
  /// d'un Dio "nu" séparé.
  final Dio _dio;

  /// `purpose` détermine le préfixe de la clé S3 côté backend — 'promo'
  /// (défaut), 'commercant' pour la photo du commerce, ou 'registre'.
  Future<String> uploadPhoto(File original, {String purpose = 'promo'}) async {
    final compressed = await _compress(original);

    final formData = FormData.fromMap({
      'purpose': purpose,
      'file': await MultipartFile.fromFile(compressed.path),
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/storage/upload',
      data: formData,
      // Le défaut de `ApiClient` (20s) est calibré pour du JSON, trop court
      // pour l'upload d'une image (jusqu'à ~500 Ko) sur un réseau lent.
      options: Options(sendTimeout: const Duration(seconds: 60), receiveTimeout: const Duration(seconds: 60)),
    );
    return response.data!['key'] as String;
  }

  /// Compresse par paliers décroissants jusqu'à passer sous `_targetBytes`
  /// — `flutter_image_compress` n'a pas de mode "viser X Ko" natif, un seul
  /// palier fixe (l'ancien `minWidth: 1200, quality: 80`) ne garantissait
  /// rien de précis sur la taille réelle produite.
  Future<File> _compress(File original) async {
    File? lastAttempt;

    for (final step in _compressionSteps) {
      final targetPath = p.join(
        (await getTemporaryDirectory()).path,
        '${DateTime.now().microsecondsSinceEpoch}.jpg',
      );

      final result = await FlutterImageCompress.compressAndGetFile(
        original.absolute.path,
        targetPath,
        minWidth: step.width,
        minHeight: step.width,
        quality: step.quality,
        format: CompressFormat.jpeg,
      );
      if (result == null) continue;

      final file = File(result.path);
      lastAttempt = file;
      if (await file.length() <= _targetBytes) return file;
    }

    return lastAttempt ?? original;
  }
}
