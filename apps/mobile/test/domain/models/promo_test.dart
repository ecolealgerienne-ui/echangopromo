import 'package:flutter_test/flutter_test.dart';
import 'package:echango_promo/domain/enums/categorie.dart';
import 'package:echango_promo/domain/models/promo.dart';

/// ⚠️ **`createdAt` est obligatoire côté modèle** (`Promo.fromJson` le caste
/// sans repli). Son absence ici a cassé les cinq tests de ce fichier pendant
/// trois semaines, depuis le commit `publishedAt` du 2026-07-14 — sans que
/// personne le voie, le SDK Flutter n'étant pas installable dans
/// l'environnement de l'époque. Trouvé le 2026-08-04, au premier
/// `flutter test` réel.
Promo _promo({
  required String lifecycleStatus,
  DateTime? dateFin,
  Map<String, dynamic> extra = const {},
}) =>
    Promo.fromJson({
      'id': 'p1',
      'commercantId': 'c1',
      'description': 'Test',
      'prixAvant': 100,
      'prixApres': 80,
      'categorie': 'autre',
      'dateFin': dateFin?.toIso8601String(),
      'lifecycleStatus': lifecycleStatus,
      'moderationStatus': 'normale',
      'photoUrl': null,
      'createdAt': DateTime(2026, 7, 1).toIso8601String(),
      ...extra,
    });

void main() {
  // Les libellés localisés (`lifecycleLabel` déplacé vers
  // `promoLifecycleLabel` dans features/shared/l10n/enum_labels.dart, qui
  // a besoin d'un `BuildContext`) sont couverts par
  // test/features/shared/l10n/enum_labels_test.dart — ce fichier ne teste
  // que la logique pure du modèle.
  test('brouillon : ni publiée ni expirée', () {
    final promo = _promo(lifecycleStatus: 'brouillon');
    expect(promo.isDraft, isTrue);
    expect(promo.isPublished, isFalse);
    expect(promo.isExpired, isFalse);
  });

  test('publiée avec dateFin future : publiée, pas expirée', () {
    final promo = _promo(
      lifecycleStatus: 'publiee',
      dateFin: DateTime.now().add(const Duration(days: 1)),
    );
    expect(promo.isPublished, isTrue);
    expect(promo.isExpired, isFalse);
  });

  // Cas non trivial : le backend peut ne pas avoir encore tourné le cron
  // d'expiration (`expireOutdatedPromos`) alors que `dateFin` est déjà
  // dépassée — le mobile doit s'en apercevoir sans attendre ce cron.
  test('publiée avec dateFin dépassée : considérée expirée côté mobile', () {
    final promo = _promo(
      lifecycleStatus: 'publiee',
      dateFin: DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(promo.isExpired, isTrue);
  });

  test('arretee : isStopped', () {
    final promo = _promo(lifecycleStatus: 'arretee');
    expect(promo.isStopped, isTrue);
  });

  test('categorie inconnue retombe sur autre', () {
    final promo = _promo(lifecycleStatus: 'brouillon');
    expect(promo.categorie, Categorie.autre);
  });

  // ── Position du commerce : la chaîne que la liste emprunte ────────────────
  //
  // ⚠️ **Ces deux champs étaient servis par le serveur et jetés ici.**
  // `GET /promo` les envoie depuis le 2026-08-12, avec un commentaire disant
  // explicitement « pour que l'app puisse afficher la distance dans la
  // liste » — et `Promo.fromJson` ne les lisait pas. Résultat : `PromoCard`
  // n'avait rien à afficher, et `formatDistance` n'était appelé que par la
  // fiche et la carte. Une capacité écrite des deux côtés, sans appelant au
  // milieu (règle 31) : aucune erreur, juste une fonctionnalité absente que
  // personne ne cherche puisque le code existe.
  group('position du commerce', () {
    test('décode une position servie par le serveur', () {
      final promo = _promo(lifecycleStatus: 'publiee', extra: {
        'commercantLatitude': 34.6714,
        'commercantLongitude': 3.2630,
      });
      expect(promo.commercantLatitude, 34.6714);
      expect(promo.commercantLongitude, 3.2630);
    });

    // ⚠️ **Le piège du JSON : un entier n'est pas un `double`.** Postgres rend
    // `3` et non `3.0` pour une longitude entière, `jsonDecode` en fait un
    // `int`, et un `as double?` lève `type 'int' is not a subtype of type
    // 'double?'`. Le décodage passe donc par `num?` — même précaution que les
    // prix, qui traversent `double.parse(...toString())`.
    //
    // Le méridien de Greenwich (longitude 0) est le cas réel : `0` est un
    // entier JSON parfaitement légitime, et c'est celui qui planterait.
    test('accepte un entier là où un double est attendu', () {
      final promo = _promo(lifecycleStatus: 'publiee', extra: {
        'commercantLatitude': 34,
        'commercantLongitude': 0,
      });
      expect(promo.commercantLatitude, 34.0);
      expect(promo.commercantLongitude, 0.0);
    });

    // ⚠️ Un commerce sans position existe : la position n'est obligatoire que
    // pour PUBLIER, et une fiche créée avant le 2026-08-12 peut ne pas en
    // avoir. `null` doit rester `null` — un repli à `0` placerait le commerce
    // au large du golfe de Guinée et afficherait une distance absurde plutôt
    // que rien (règle 29).
    test('sans position : null, jamais zéro', () {
      final promo = _promo(lifecycleStatus: 'publiee');
      expect(promo.commercantLatitude, isNull);
      expect(promo.commercantLongitude, isNull);
    });
  });
}
