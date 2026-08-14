import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/report_reason.dart';
import '../../../domain/models/moderation_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/widgets/app_settings_actions.dart';
import '../../shared/widgets/promo_photo_hero.dart';
import '../../shared/widgets/promo_price_row.dart';
import '../../shared/widgets/status_chip.dart';

/// Fiche promo côté admin/agent (modération) — même `ModerationItem` que
/// `PromoModerationTile`, en vue complète : photo, statuts lifecycle +
/// modération, répartition des motifs de signalement, actions de
/// modération. Manquait jusqu'ici : la liste (`AdminPromosScreen`,
/// `ModerationQueueScreen`) n'offrait qu'un menu d'actions sans vue détail.
class AdminPromoDetailScreen extends ConsumerWidget {
  const AdminPromoDetailScreen({super.key, required this.item});

  final ModerationItem item;

  Future<void> _act(BuildContext context, WidgetRef ref,
      Future<void> Function() action) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await action();
      if (context.mounted) Navigator.of(context).pop(true);
    } catch (error) {
      // ⚠️ Sur conflit, **on referme aussi**. Cet écran tient son `item` en
      // paramètre (`extra` de la route) : il ne sait pas se recharger, et le
      // statut qu'il affiche est justement celui qui vient d'être démenti.
      // Rester dessus laisserait le modérateur retaper le même bouton contre
      // une donnée périmée. `pop(true)` fait recharger la liste d'où il vient,
      // et il rouvrira la fiche à jour s'il veut toujours décider.
      if (apiErrorCode(error) == 'MODERATION_STATE_CHANGED' &&
          context.mounted) {
        Navigator.of(context).pop(true);
      }
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
    final colorScheme = Theme.of(context).colorScheme;
    final api = ref.read(adminApiProvider);
    final reasonBreakdown = item.reasonBreakdown;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.promoDetailTitle),
        actions: const [AppSettingsActions()],
      ),
      body: ListView(
        children: [
          PromoPhotoHero(
            photoUrls: item.photoUrls,
            prixAvant: item.prixAvant,
            prixApres: item.prixApres,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.description,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                PromoPriceRow(
                    prixAvant: item.prixAvant, prixApres: item.prixApres),
                const SizedBox(height: 4),
                Text(categorieLabel(context, item.categorie)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusChip(
                      label: promoLifecycleLabel(context, item.lifecycleStatus,
                          isExpired: item.isExpired),
                      color: promoLifecycleColor(context, item.lifecycleStatus,
                          isExpired: item.isExpired),
                    ),
                    StatusChip(
                      label:
                          moderationStatusLabel(context, item.moderationStatus),
                      color:
                          moderationStatusColor(context, item.moderationStatus),
                    ),
                  ],
                ),
                const Divider(height: 32),
                Text(item.commercantNom,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.phone_outlined,
                        size: 18, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(item.commercantTelephone),
                  ],
                ),
                if (item.activeReportCount != null) ...[
                  const Divider(height: 32),
                  Text(l10n.reportCountLabel(item.activeReportCount!),
                      style: Theme.of(context).textTheme.titleMedium),
                  if (reasonBreakdown != null &&
                      reasonBreakdown.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final entry in reasonBreakdown.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${entry.value} · ${reportReasonLabel(context, ReportReason.fromValue(entry.key))}',
                        ),
                      ),
                  ],
                ],
                const Divider(height: 32),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // ⚠️ `item.moderationStatus` — **le même que celui affiché
                    // douze lignes plus haut**, et c'est tout l'intérêt : cet
                    // écran est le seul d'où l'on peut trancher une promo qui
                    // n'est PAS `signalee` (revenir sur un masquage, par
                    // exemple). Y écrire un statut en dur ferait échouer
                    // chacune de ces corrections en `MODERATION_STATE_CHANGED`.
                    OutlinedButton(
                      onPressed: () => _act(
                          context,
                          ref,
                          () =>
                              api.masquerPromo(item.id, item.moderationStatus)),
                      child: Text(l10n.masquerLabel),
                    ),
                    OutlinedButton(
                      onPressed: () => _act(
                          context,
                          ref,
                          () => api.verifierOkPromo(
                              item.id, item.moderationStatus)),
                      child: Text(l10n.verifierOkLabel),
                    ),
                    OutlinedButton(
                      onPressed: () => _act(
                          context,
                          ref,
                          () =>
                              api.avertirPromo(item.id, item.moderationStatus)),
                      child: Text(l10n.avertirLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
