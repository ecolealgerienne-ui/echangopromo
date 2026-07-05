import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/widgets/commune_cascade_field.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../providers/commune_providers.dart';

/// Demandée au premier lancement, modifiable à tout moment (specs §3.1).
/// Sélection guidée wilaya → commune (comme côté commerçant/agent) plutôt
/// qu'une liste plate — ne change rien au pilote Djelfa (une seule wilaya)
/// mais prépare l'extension multi-wilaya sans reprendre l'écran. Le choix
/// reste stocké en local (`SelectedCommuneStore`) et donc réutilisé aux
/// prochains lancements, comme avant.
class CommuneSelectionScreen extends ConsumerStatefulWidget {
  const CommuneSelectionScreen({super.key});

  @override
  ConsumerState<CommuneSelectionScreen> createState() => _CommuneSelectionScreenState();
}

class _CommuneSelectionScreenState extends ConsumerState<CommuneSelectionScreen> {
  String? _selectedCommuneId;

  @override
  void initState() {
    super.initState();
    // Pré-remplit avec le choix déjà enregistré en local, s'il existe.
    _selectedCommuneId = ref.read(selectedCommuneProvider);
  }

  Future<void> _confirm() async {
    if (_selectedCommuneId == null) return;
    await ref.read(selectedCommuneProvider.notifier).select(_selectedCommuneId!);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final communesAsync = ref.watch(communeListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.chooseCommuneTitle),
        actions: const [LanguageSwitcherButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: communesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(l10n.commonError(error.toString()))),
          data: (communes) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CommuneCascadeField(
                communes: communes,
                selectedCommuneId: _selectedCommuneId,
                onChanged: (id) => setState(() => _selectedCommuneId = id),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _selectedCommuneId == null ? null : _confirm,
                child: Text(l10n.commonConfirm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
