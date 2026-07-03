import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Upload d'une photo vers S3 OVH via URL pré-signée. Compression
/// obligatoire côté app avant upload — max ~1200px de large, JPEG qualité
/// ~80 (specs §5.8) — pour limiter le coût de stockage et la bande passante
/// vu la couverture réseau variable à Djelfa.
class StorageApi {
  StorageApi(this._authenticatedDio) : _rawDio = Dio();

  /// Dio authentifié (JWT + device-id) pour demander l'URL pré-signée.
  final Dio _authenticatedDio;

  /// Dio "nu" pour le PUT final vers S3 — une Authorization ou un
  /// X-Device-Id supplémentaire casserait la signature pré-signée.
  final Dio _rawDio;

  Future<String> uploadPhoto(File original) async {
    final compressed = await _compress(original);
    final presigned = await _requestPresignedUrl();

    await _rawDio.put<void>(
      presigned.uploadUrl,
      data: await compressed.readAsBytes(),
      options: Options(headers: {'Content-Type': 'image/jpeg'}),
    );

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

  Future<_PresignedUpload> _requestPresignedUrl() async {
    final response = await _authenticatedDio.post<Map<String, dynamic>>(
      '/storage/presigned-upload',
      data: {'contentType': 'image/jpeg'},
    );
    return _PresignedUpload(
      uploadUrl: response.data!['uploadUrl'] as String,
      key: response.data!['key'] as String,
    );
  }
}

class _PresignedUpload {
  _PresignedUpload({required this.uploadUrl, required this.key});

  final String uploadUrl;
  final String key;
}
