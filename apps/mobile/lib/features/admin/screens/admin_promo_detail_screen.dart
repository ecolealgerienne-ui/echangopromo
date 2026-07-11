import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/theme.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/report_reason.dart';
import '../../../domain/models/moderation_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/widgets/language_switcher_button.dart';

/// Fiche promo côté admin/agent (modération) — même `ModerationItem` que
/// `PromoModerationTile`, en vue complète : photo, statuts lifecycle +
/// modération, répartition des motifs de signalement, actions de
/// modération. Manquait jusqu'ici : la liste (`AdminPromosScreen`,
/// `ModerationQueueScreen`) n'offrait qu'un menu d'actions sans vue détail.
class AdminPromoDetailScreen extends ConsumerWidget {
  const AdminPromoDetailScreen({super.key, required this.item});

  final ModerationItem item;

  Future<void> _act(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await action();
      if (context.mounted) Navigator.of(context).pop(true);
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
    final colorScheme = Theme.of(context).colorScheme;
    final api = ref.read(adminApiProvider);
    final currency = NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0);
    final discountPercent = ((item.prixAvant - item.prixApres) / item.prixAvant * 100).round();
    final reasonBreakdown = item.reasonBreakdown;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.promoDetailTitle),
        actions: const [LanguageSwitcherButton()],
      ),
      body: ListView(
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: item.photoUrl != null
                    ? CachedNetworkImage(imageUrl: item.photoUrl!, fit: BoxFit.cover)
                    : Container(color: colorScheme.surfaceContainerHighest),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    '-$discountPercent%',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.description, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      currency.format(item.prixAvant),
                      style: TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      currency.format(item.prixApres),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(categorieLabel(context, item.categorie)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusChip(
                      label: promoLifecycleLabel(context, item.lifecycleStatus, isExpired: false),
                      color: promoLifecycleColor(item.lifecycleStatus, isExpired: false),
                    ),
                    _StatusChip(
                      label: moderationStatusLabel(context, item.moderationStatus),
                      color: moderationStatusColor(item.moderationStatus),
                    ),
                  ],
                ),
                const Divider(height: 32),
                Text(item.commercantNom, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.phone_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(item.commercantTelephone),
                  ],
                ),
                if (item.activeReportCount != null) ...[
                  const Divider(height: 32),
                  Text(l10n.reportCountLabel(item.activeReportCount!),
                      style: Theme.of(context).textTheme.titleMedium),
                  if (reasonBreakdown != null && reasonBreakdown.isNotEmpty) ...[
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
                    OutlinedButton(
                      onPressed: () => _act(context, ref, () => api.masquerPromo(item.id)),
                      child: Text(l10n.masquerLabel),
                    ),
                    OutlinedButton(
                      onPressed: () => _act(context, ref, () => api.verifierOkPromo(item.id)),
                      child: Text(l10n.verifierOkLabel),
                    ),
                    OutlinedButton(
                      onPressed: () => _act(context, ref, () => api.avertirPromo(item.id)),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
