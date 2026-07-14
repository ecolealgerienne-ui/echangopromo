import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/commune_multi_select_field.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../providers/commune_providers.dart';

/// Demandée au premier lancement, modifiable à tout moment (specs §3.1).
/// Sélection multi-communes (décision produit 2026-07-12, jusqu'à
/// [kMaxSelectedCommunes]) : dans les grandes villes les communes sont
/// accolées, une promo dans l'une intéresse un client dans la voisine. Écran
/// dédié + bouton de confirmation explicite (pas d'application en direct à
/// chaque coche) : ce filtre part en requête serveur, contrairement au
/// filtre favoris/tri qui reste local.
class CommuneSelectionScreen extends ConsumerStatefulWidget {
  const CommuneSelectionScreen({super.key});

  @override
  ConsumerState<CommuneSelectionScreen> createState() => _CommuneSelectionScreenState();
}

class _CommuneSelectionScreenState extends ConsumerState<CommuneSelectionScreen> {
  late Set<String> _selectedCommuneIds;

  @override
  void initState() {
    super.initState();
    // Pré-remplit avec le choix déjà enregistré en local, s'il existe.
    _selectedCommuneIds = ref.read(selectedCommunesProvider).toSet();
  }

  Future<void> _confirm() async {
    if (_selectedCommuneIds.isEmpty) return;
    await ref.read(selectedCommunesProvider.notifier).select(_selectedCommuneIds.toList());
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
          error: (error, _) => Center(child: ApiErrorText(error)),
          data: (communes) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.maxCommunesHint(kMaxSelectedCommunes),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: CommuneMultiSelectField(
                    communes: communes,
                    selectedCommuneIds: _selectedCommuneIds,
                    maxSelection: kMaxSelectedCommunes,
                    constrainListHeight: false,
                    onChanged: (ids) => setState(() => _selectedCommuneIds = ids),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _selectedCommuneIds.isEmpty ? null : _confirm,
                child: Text(l10n.commonConfirm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
