import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';

/// Dashboard commerçant (specs §3.2) : donne une raison concrète de revenir
/// régulièrement dans l'app, en plus de l'obligation de republication.
class CommercantDashboardScreen extends ConsumerWidget {
  const CommercantDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meAsync = ref.watch(_meProvider);
    final statsAsync = ref.watch(_statsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon espace commerçant'),
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
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_meProvider);
          ref.invalidate(_statsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            meAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('Erreur : $error'),
              data: (commercant) => Text(
                commercant.nom,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Vues de votre fiche (devices uniques)'),
                trailing: statsAsync.when(
                  loading: () => const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => const Text('-'),
                  data: (count) => Text('$count', style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.local_offer_outlined),
              label: const Text('Mes promos'),
              onPressed: () => context.push('/commercant/promos'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Modifier mon profil'),
              onPressed: () async {
                final updated = await context.push<bool>('/commercant/profile/edit');
                if (updated == true) {
                  ref.invalidate(_meProvider);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

final _meProvider = FutureProvider.autoDispose((ref) => ref.watch(commercantApiProvider).me());
final _statsProvider =
    FutureProvider.autoDispose((ref) => ref.watch(commercantApiProvider).dashboardProfileViewCount());
