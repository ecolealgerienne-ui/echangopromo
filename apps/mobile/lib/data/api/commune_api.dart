import 'package:dio/dio.dart';
import '../../domain/models/commune.dart';

/// Taille de page côté requête — la plus grande autorisée par le backend
/// (`MAX_PAGE_SIZE`). Le référentiel commune est une liste de référence
/// bornée (~1500 communes au maximum en Algérie), jamais un flux paginé à
/// l'écran : `list()` boucle en interne jusqu'à tout récupérer, le
/// sélecteur wilaya → commune a besoin de la liste complète
/// (CommuneCascadeField).
const _pageSize = 100;

class CommuneApi {
  CommuneApi(this._dio);

  final Dio _dio;

  Future<List<Commune>> list({String? wilaya}) async {
    final all = <Commune>[];
    var page = 1;
    while (true) {
      final response = await _dio.get<Map<String, dynamic>>(
        '/commune',
        queryParameters: {
          if (wilaya != null) 'wilaya': wilaya,
          'page': page,
          'limit': _pageSize,
        },
      );
      final data = response.data!;
      final items = (data['items'] as List<dynamic>)
          .map((e) => Commune.fromJson(e as Map<String, dynamic>))
          .toList();
      all.addAll(items);
      final total = data['total'] as int;
      if (items.isEmpty || all.length >= total) break;
      page++;
    }
    return all;
  }
}
