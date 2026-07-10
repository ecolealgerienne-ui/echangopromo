import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Upload proxifié par notre backend (pas de POST policy S3 pré-signée) :
/// OVH (le S3 utilisé en prod) ne supporte pas l'API S3 "POST Object"
/// (`501 Not Implemented`, découvert au premier test réel post-
/// déploiement) — le fichier transite donc par notre API, qui valide
/// taille et format avant de l'envoyer elle-même à S3.
/// Compression obligatoire côté app avant upload — max ~1200px de large,
/// JPEG qualité ~80 (specs §5.8) — pour limiter le coût de stockage et la
/// bande passante vu la couverture réseau variable à Djelfa.
class StorageApi {
  StorageApi(this._dio);

  /// Dio authentifié (JWT + device-id) — l'upload passe maintenant par
  /// notre backend, plus par un POST direct vers S3, donc plus besoin
  /// d'un Dio "nu" séparé.
  final Dio _dio;

  /// `purpose` détermine le préfixe de la clé S3 côté backend — 'promo'
  /// (défaut) ou 'commercant' pour la photo du commerce.
  Future<String> uploadPhoto(File original, {String purpose = 'promo'}) async {
    final compressed = await _compress(original);

    final formData = FormData.fromMap({
      'purpose': purpose,
      'file': await MultipartFile.fromFile(compressed.path),
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/storage/upload',
      data: formData,
    );
    return response.data!['key'] as String;
  }

  Future<File> _compress(File original) async {
    final targetPath = p.join(
      (await getTemporaryDirectory()).path,
      '${DateTime.now().millisecondsSinceEpoch}.jpg',
    );

    final result = await FlutterImageCompress.compressAndGetFile(
      original.absolute.path,
      targetPath,
      minWidth: 1200,
      quality: 80,
      format: CompressFormat.jpeg,
    );

    return result != null ? File(result.path) : original;
  }
}
