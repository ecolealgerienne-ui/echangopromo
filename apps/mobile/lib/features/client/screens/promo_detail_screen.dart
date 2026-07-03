import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/commercant.dart';
import '../../../providers/core_providers.dart';
import '../providers/favorites_provider.dart';
import '../providers/promo_providers.dart';

/// Fiche promo (specs §3.1) : photo, produit, prix avant/après, nom et
/// adresse du commerçant, date de fin de validité, signalement.
class PromoDetailScreen extends ConsumerWidget {
  const PromoDetailScreen({super.key, required this.promoId});

  final String promoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promoAsync = ref.watch(promoDetailProvider(promoId));

    return Scaffold(
      appBar: AppBar(title: const Text('Détail de la promo')),
      body: promoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (promo) {
          final favorites = ref.watch(favoritesProvider);
          final isFavorite = favorites.contains(promo.commercantId);
          final currency = NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0);
          final dateFormat = DateFormat('dd/MM/yyyy');

          return ListView(
            children: [
              if (promo.photoUrl != null)
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: CachedNetworkImage(imageUrl: promo.photoUrl!, fit: BoxFit.cover),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(promo.produit, style: Theme.of(context).textTheme.headlineSmall),
                        ),
                        IconButton(
                          icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                          onPressed: () =>
                              ref.read(favoritesProvider.notifier).toggle(promo.commercantId),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          currency.format(promo.prixAvant),
                          style: const TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          currency.format(promo.prixApres),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Valable jusqu\'au ${dateFormat.format(promo.dateFin)}'),
                    const Divider(height: 32),
                    _CommercantInfo(commercantId: promo.commercantId),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Signaler (promo expirée ou incorrecte)'),
                      onPressed: () => _report(context, ref),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(reportApiProvider).create(promoId);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Signalement envoyé, merci.')));
      }
    } catch (error) {
      final message = extractApiErrorMessage(error, fallback: 'Signalement impossible.');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
}

final _commercantPublicProfileProvider =
    FutureProvider.autoDispose.family<Commercant, String>((ref, commercantId) {
  return ref.watch(commercantApiProvider).publicProfile(commercantId);
});

class _CommercantInfo extends ConsumerWidget {
  const _CommercantInfo({required this.commercantId});

  final String commercantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commercantAsync = ref.watch(_commercantPublicProfileProvider(commercantId));

    return commercantAsync.when(
      loading: () => const SizedBox(height: 40, child: Center(child: CircularProgressIndicator())),
      error: (error, _) => Text('Erreur : $error'),
      data: (commercant) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(commercant.nom, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 18, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(child: Text(commercant.adresse)),
            ],
          ),
        ],
      ),
    );
  }
}
