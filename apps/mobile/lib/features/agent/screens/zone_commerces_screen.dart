import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';

final zoneCommercesProvider =
    FutureProvider.autoDispose((ref) => ref.watch(agentApiProvider).zoneCommerces());

/// Liste des commerces de la zone de l'agent avec statut de tournée
/// (specs §3.3) : jamais visité / à jour / à relancer.
class ZoneCommercesScreen extends ConsumerWidget {
  const ZoneCommercesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commercesAsync = ref.watch(zoneCommercesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ma zone'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Déconnexion',
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Nouveau commerçant'),
        onPressed: () async {
          final created = await context.push<bool>('/agent/commercant/new');
          if (created == true && context.mounted) {
            ref.invalidate(zoneCommercesProvider);
          }
        },
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(zoneCommercesProvider),
        child: commercesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Erreur : $error')),
          data: (commerces) {
            if (commerces.isEmpty) {
              return const Center(child: Text('Aucun commerce dans cette zone.'));
            }
            return ListView.builder(
              itemCount: commerces.length,
              itemBuilder: (context, index) {
                final entry = commerces[index];
                final commercant = entry.commercant;
                return ListTile(
                  title: Text(commercant.nom),
                  subtitle: Text('${commercant.adresse} · ${entry.visitStatusLabel}'),
                  trailing: commercant.accountState == 'cree_agent'
                      ? IconButton(
                          icon: const Icon(Icons.sms_outlined),
                          tooltip: 'Initier la revendication',
                          onPressed: () => _initiateClaim(context, ref, commercant.id),
                        )
                      : null,
                  onTap: () => context.push('/agent/promo/new/${commercant.id}'),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _initiateClaim(BuildContext context, WidgetRef ref, String commercantId) async {
    try {
      await ref.read(agentApiProvider).initiateClaim(commercantId);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('OTP envoyé au commerçant.')));
      }
    } catch (error) {
      final message = extractApiErrorMessage(error, fallback: 'Action impossible.');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
}
