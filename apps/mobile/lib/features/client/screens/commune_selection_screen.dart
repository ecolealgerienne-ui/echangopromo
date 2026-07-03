import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/commune_providers.dart';

/// Demandée au premier lancement, modifiable à tout moment (specs §3.1).
class CommuneSelectionScreen extends ConsumerWidget {
  const CommuneSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final communesAsync = ref.watch(communeListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Choisissez votre commune')),
      body: communesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (communes) => ListView.builder(
          itemCount: communes.length,
          itemBuilder: (context, index) {
            final commune = communes[index];
            return ListTile(
              title: Text(commune.nom),
              subtitle: Text(commune.wilaya),
              onTap: () async {
                await ref.read(selectedCommuneProvider.notifier).select(commune.id);
                if (context.mounted) context.go('/');
              },
            );
          },
        ),
      ),
    );
  }
}
