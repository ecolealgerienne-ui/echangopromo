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
  test('brouillon : ni publiée ni expirée', () {
    final promo = _promo(lifecycleStatus: 'brouillon');
    expect(promo.isDraft, isTrue);
    expect(promo.isPublished, isFalse);
    expect(promo.isExpired, isFalse);
    expect(promo.lifecycleLabel, 'Brouillon');
  });

  test('publiée avec dateFin future : publiée, pas expirée', () {
    final promo = _promo(
      lifecycleStatus: 'publiee',
      dateFin: DateTime.now().add(const Duration(days: 1)),
    );
    expect(promo.isPublished, isTrue);
    expect(promo.isExpired, isFalse);
    expect(promo.lifecycleLabel, 'Publiée');
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
    expect(promo.lifecycleLabel, 'Expirée');
  });

  test('arretee : label Arrêtée', () {
    final promo = _promo(lifecycleStatus: 'arretee');
    expect(promo.isStopped, isTrue);
    expect(promo.lifecycleLabel, 'Arrêtée');
  });

  test('categorie inconnue retombe sur autre', () {
    final promo = _promo(lifecycleStatus: 'brouillon');
    expect(promo.categorie, Categorie.autre);
  });
}
