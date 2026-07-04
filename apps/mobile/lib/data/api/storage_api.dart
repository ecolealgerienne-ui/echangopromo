import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Upload d'une photo vers S3 OVH via une POST policy pré-signée (pas un
/// simple PUT : `content-length-range` est une contrainte appliquée par S3
/// lui-même, ce qu'un PUT pré-signé ne permet pas — audit sécurité).
/// Compression obligatoire côté app avant upload — max ~1200px de large,
/// JPEG qualité ~80 (specs §5.8) — pour limiter le coût de stockage et la
/// bande passante vu la couverture réseau variable à Djelfa.
class StorageApi {
  StorageApi(this._authenticatedDio) : _rawDio = Dio();

  /// Dio authentifié (JWT + device-id) pour demander la POST policy.
  final Dio _authenticatedDio;

  /// Dio "nu" pour l'upload final vers S3 — une Authorization ou un
  /// X-Device-Id supplémentaire n'a rien à faire dans cette requête.
  final Dio _rawDio;

  Future<String> uploadPhoto(File original) async {
    final compressed = await _compress(original);
    final presigned = await _requestPresignedUpload();

    final formData = FormData();
    presigned.fields.forEach((key, value) {
      formData.fields.add(MapEntry(key, value));
    });
    // Le champ "file" doit être ajouté en dernier : S3 ignore tout champ
    // de la policy qui arriverait après lui dans le formulaire multipart.
    formData.files.add(
      MapEntry('file', await MultipartFile.fromFile(compressed.path)),
    );

    await _rawDio.post<void>(presigned.url, data: formData);

    return presigned.key;
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

  Future<_PresignedUpload> _requestPresignedUpload() async {
    final response = await _authenticatedDio.post<Map<String, dynamic>>(
      '/storage/presigned-upload',
      data: {'contentType': 'image/jpeg'},
    );
    final fields = (response.data!['fields'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as String),
    );
    return _PresignedUpload(
      url: response.data!['url'] as String,
      fields: fields,
      key: response.data!['key'] as String,
    );
  }
}

class _PresignedUpload {
  _PresignedUpload({required this.url, required this.fields, required this.key});

  final String url;
  final Map<String, String> fields;
  final String key;
}
