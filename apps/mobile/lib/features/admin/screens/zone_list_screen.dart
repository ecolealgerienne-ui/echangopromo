import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/language_switcher_button.dart';

final _zoneListProvider = FutureProvider.autoDispose((ref) => ref.watch(adminApiProvider).listZones());

/// Gestion des zones opérationnelles (specs §3.4) — création et
/// consultation ; l'assignation à un agent se fait depuis l'écran Agents.
class ZoneListScreen extends ConsumerWidget {
  const ZoneListScreen({super.key});

  Future<void> _createZone(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final nomController = TextEditingController();
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.newZoneLabel),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nomController,
                decoration: InputDecoration(labelText: l10n.nomLabel),
                validator: (v) => (v == null || v.isEmpty) ? l10n.nomRequired : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: descriptionController,
                decoration: InputDecoration(labelText: l10n.zoneDescriptionLabel),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.of(context).pop(true);
            },
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(adminApiProvider).createZone(
            nom: nomController.text.trim(),
            description: descriptionController.text.trim(),
          );
      ref.invalidate(_zoneListProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(extractApiErrorMessage(
              error,
              fallback: l10n.operationFailed,
              locale: Localizations.localeOf(context),
            )),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final zonesAsync = ref.watch(_zoneListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.zonesLabel),
        actions: const [LanguageSwitcherButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l10n.newZoneLabel),
        onPressed: () => _createZone(context, ref),
      ),
      body: zonesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.commonError(error.toString()))),
        data: (zones) {
          if (zones.isEmpty) {
            return Center(child: Text(l10n.noZonesYet));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_zoneListProvider),
            child: ListView.builder(
              itemCount: zones.length,
              itemBuilder: (context, index) {
                final zone = zones[index];
                return ListTile(
                  title: Text(zone.nom),
                  subtitle: zone.description != null ? Text(zone.description!) : null,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
