import 'package:dio/dio.dart';
import 'package:echango_promo/data/api/etag_cache_interceptor.dart';
import 'package:echango_promo/data/local/etag_cache_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adaptateur qui rend ce qu'on lui dit, et **retient ce qu'on lui a demandé**.
///
/// ⚠️ Retenir la requête est le cœur de ces tests : la moitié des affirmations
/// portent sur un en-tête ENVOYÉ (`If-None-Match`), pas sur une réponse reçue.
/// Un adaptateur qui ne garderait que la réponse ne pourrait rien prouver de ce
/// que l'app émet.
class _AdaptateurFactice implements HttpClientAdapter {
  _AdaptateurFactice(this.reponses);

  final List<ResponseBody> reponses;
  final List<RequestOptions> recues = [];
  int _appel = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8ListLike>? _,
      Future<void>? __) async {
    recues.add(options);
    return reponses[_appel++];
  }

  @override
  void close({bool force = false}) {}
}

typedef Uint8ListLike = List<int>;

ResponseBody _json(String corps, {int statut = 200, String? etag}) =>
    ResponseBody.fromString(
      corps,
      statut,
      headers: {
        'content-type': ['application/json'],
        if (etag != null) 'etag': [etag],
      },
    );

void main() {
  late EtagCacheStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = EtagCacheStore(await SharedPreferences.getInstance());
  });

  Dio dioAvec(_AdaptateurFactice adaptateur) {
    final dio = Dio(BaseOptions(baseUrl: 'https://exemple.test'))
      ..httpClientAdapter = adaptateur;
    dio.interceptors.add(EtagCacheInterceptor(store));
    return dio;
  }

  /// ── Le chemin nominal, et il porte tout ────────────────────────────────
  ///
  /// Premier appel : rien en cache, aucun `If-None-Match`, la réponse est
  /// conservée. Second appel : l'en-tête part, le serveur rend `304` **sans
  /// corps**, et l'app doit tout de même recevoir les données.
  test('le second appel envoie If-None-Match et exploite le 304', () async {
    final adaptateur = _AdaptateurFactice([
      _json('{"total":2}', etag: 'W/"abc"'),
      _json('', statut: 304),
    ]);
    final dio = dioAvec(adaptateur);

    final premier = await dio.get<dynamic>('/promo');
    expect(premier.data, {'total': 2});
    expect(
      adaptateur.recues.first.headers.containsKey('If-None-Match'),
      isFalse,
      reason: 'le premier appel ne peut rien revalider : il n’a rien en cache',
    );

    // ⚠️ L'écriture du cache n'est pas attendue par l'intercepteur (elle ne
    // doit pas retarder l'affichage) : on laisse la boucle d'événements la
    // terminer avant de mesurer, sinon on mesurerait une course, pas un cache.
    await Future<void>.delayed(Duration.zero);

    final second = await dio.get<dynamic>('/promo');
    expect(
      adaptateur.recues[1].headers['If-None-Match'],
      'W/"abc"',
      reason: 'sans cet en-tête, le serveur ne peut pas répondre 304 et le '
          'corps repart en entier — l’ETag ne sert alors à rien',
    );
    expect(
      second.data,
      {'total': 2},
      reason: 'le 304 ne porte AUCUN corps : si l’app n’en sert pas un depuis '
          'son cache, l’écran est vide alors que rien n’a changé',
    );
    expect(second.statusCode, 200);
  });

  /// ── ⚠️ Le contrôle qui rend ce cache sûr ───────────────────────────────
  ///
  /// L'app est multi-rôles sur un seul appareil. Mettre en cache une réponse
  /// authentifiée sous une clé d'URL ferait servir les données d'un compte à
  /// celui qui ouvre l'app ensuite — la clé ne porte pas l'identité.
  test('une réponse authentifiée n’est jamais mise en cache', () async {
    final adaptateur = _AdaptateurFactice([
      _json('{"secret":1}', etag: 'W/"prive"'),
      _json('{"secret":2}', etag: 'W/"prive2"'),
    ]);
    final dio = dioAvec(adaptateur);

    await dio.get<dynamic>('/promo/me/all',
        options: Options(headers: {'Authorization': 'Bearer x'}));
    await Future<void>.delayed(Duration.zero);

    final second = await dio.get<dynamic>('/promo/me/all',
        options: Options(headers: {'Authorization': 'Bearer x'}));
    expect(
      adaptateur.recues[1].headers.containsKey('If-None-Match'),
      isFalse,
      reason: 'une réponse authentifiée a été conservée : sur un appareil où '
          'le rôle change, elle serait servie au compte suivant',
    );
    expect(second.data, {'secret': 2});
  });

  /// ── ⚠️ Deux cadrages de carte sont deux réponses ───────────────────────
  test('la clé de cache distingue les paramètres de requête', () async {
    final adaptateur = _AdaptateurFactice([
      _json('{"ville":"djelfa"}', etag: 'W/"d"'),
      _json('{"ville":"alger"}', etag: 'W/"a"'),
    ]);
    final dio = dioAvec(adaptateur);

    await dio.get<dynamic>('/promo/map', queryParameters: {'north': 34.7});
    await Future<void>.delayed(Duration.zero);
    final autre =
        await dio.get<dynamic>('/promo/map', queryParameters: {'north': 36.8});

    expect(
      adaptateur.recues[1].headers.containsKey('If-None-Match'),
      isFalse,
      reason: 'un autre cadrage a revalidé contre l’ETag du premier : le '
          'serveur pourrait rendre 304 et l’app afficherait la mauvaise ville',
    );
    expect(autre.data, {'ville': 'alger'});
  });

  /// ── ⚠️ Un ETag sans corps est un piège, et le store l'interdit ─────────
  test('un ETag conservé sans son corps n’est jamais rendu', () async {
    await store.enregistrer('https://exemple.test/promo', 'W/"x"', {'a': 1});
    expect(store.lire('https://exemple.test/promo'), isNotNull);

    await store.vider();
    expect(
      store.lire('https://exemple.test/promo'),
      isNull,
      reason: 'le vidage doit emporter l’ETag ET le corps : garder l’un sans '
          'l’autre ferait envoyer If-None-Match sans rien à servir en retour',
    );
  });

  /// ── La borne de taille, sans laquelle le démarrage ralentirait ─────────
  test('une réponse trop volumineuse n’est pas conservée', () async {
    final gros = {'x': 'a' * (EtagCacheStore.maxOctetsParEntree + 10)};
    await store.enregistrer('cle-grosse', 'W/"g"', gros);
    expect(
      store.lire('cle-grosse'),
      isNull,
      reason: 'SharedPreferences est lu EN ENTIER au démarrage : y laisser '
          'grossir des corps ralentirait le lancement, soit exactement ce '
          'qu’on cherche à améliorer',
    );
  });

  /// ── L'éviction, pour que le cache reste borné dans le temps ────────────
  test('au-delà du plafond, la plus ancienne entrée part', () async {
    for (var i = 0; i <= EtagCacheStore.maxEntrees; i++) {
      await store.enregistrer('cle-$i', 'W/"$i"', {'n': i});
    }
    expect(store.lire('cle-0'), isNull, reason: 'la plus ancienne doit partir');
    expect(store.lire('cle-${EtagCacheStore.maxEntrees}'), isNotNull);
  });
}
