import 'package:flutter_test/flutter_test.dart';
import 'package:echango_promo/domain/enums/categorie.dart';
import 'package:echango_promo/domain/models/promo.dart';

Promo _promo({required String lifecycleStatus, DateTime? dateFin}) => Promo.fromJson({
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
}
