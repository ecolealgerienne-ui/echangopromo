import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/commune_multi_select_field.dart';
import '../../shared/widgets/app_settings_actions.dart';
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final communesAsync = ref.watch(communeListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.chooseCommuneTitle),
        actions: const [AppSettingsActions()],
      ),
      body: communesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: ApiErrorText(error)),
        data: (communes) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.maxCommunesHint(kMaxSelectedCommunes), style: textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  // Compteur vivant plutôt qu'une consigne figée : le client
                  // voit combien il lui reste de choix au lieu de découvrir
                  // le plafond en butant dessus.
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 15, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n.communesSelectedCount(_selectedCommuneIds.length),
                          style: textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CommuneMultiSelectField(
                  communes: communes,
                  selectedCommuneIds: _selectedCommuneIds,
                  maxSelection: kMaxSelectedCommunes,
                  constrainListHeight: false,
                  onChanged: (ids) => setState(() => _selectedCommuneIds = ids),
                ),
              ),
            ),
          ],
        ),
      ),
      // Confirmation fixée en bas : la liste des communes défile sur
      // plusieurs écrans, le bouton disparaissait dès qu'on cherchait.
      bottomNavigationBar: Material(
        color: colorScheme.surface,
        elevation: 3,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: FilledButton(
              onPressed: _selectedCommuneIds.isEmpty ? null : _confirm,
              child: Text(l10n.commonConfirm),
            ),
          ),
        ),
      ),
    );
  }
}
