import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../providers/core_providers.dart';

final myPromosProvider = FutureProvider.autoDispose((ref) => ref.watch(promoApiProvider).listMine());

/// Jusqu'à 5 promos actives simultanément (specs §3.2/§5.3).
class MyPromosScreen extends ConsumerWidget {
  const MyPromosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promosAsync = ref.watch(myPromosProvider);
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Mes promos')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle promo'),
        onPressed: () async {
          final created = await context.push<bool>('/commercant/promos/new');
          if (created == true) ref.invalidate(myPromosProvider);
        },
      ),
      body: promosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (promos) {
          if (promos.isEmpty) {
            return const Center(child: Text('Aucune promo pour le moment.'));
          }
          final activeCount = promos.where((p) => p.status == 'active').length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('$activeCount / 5 promos actives'),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: promos.length,
                  itemBuilder: (context, index) {
                    final promo = promos[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            promo.photoUrl != null ? CachedNetworkImageProvider(promo.photoUrl!) : null,
                      ),
                      title: Text(promo.produit),
                      subtitle: Text(
                        '${promo.status} · jusqu\'au ${dateFormat.format(promo.dateFin)} · ${promo.viewCount ?? 0} vues',
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
