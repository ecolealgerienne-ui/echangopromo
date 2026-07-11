import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../domain/enums/report_reason.dart';
import '../../../domain/models/moderation_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/l10n/enum_labels.dart';

/// Ligne "promo à modérer" (masquer / vérifier OK / avertir) — partagée
/// entre la file automatique (`ModerationQueueScreen`, signalements ≥
/// seuil) et la vue globale (`AdminPromosScreen`, toutes les promos, plan
/// de correction Phase 2). CLAUDE.md règle #21 : extrait dès la 2e
/// duplication.
class PromoModerationTile extends StatelessWidget {
  const PromoModerationTile({
    super.key,
    required this.item,
    required this.onMasquer,
    required this.onVerifierOk,
    required this.onAvertir,
  });

  final ModerationItem item;
  final Future<void> Function() onMasquer;
  final Future<void> Function() onVerifierOk;
  final Future<void> Function() onAvertir;

  String _reasonBreakdownText(BuildContext context) {
    final breakdown = item.reasonBreakdown;
    if (breakdown == null || breakdown.isEmpty) return '';
    return breakdown.entries
        .map((entry) => '${entry.value} ${reportReasonLabel(context, ReportReason.fromValue(entry.key))}')
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final secondLine = item.activeReportCount != null
        ? l10n.reportCountLabel(item.activeReportCount!)
        : promoLifecycleLabel(context, item.lifecycleStatus, isExpired: false);
    final reasonText = _reasonBreakdownText(context);
    final subtitle = [
      '${item.commercantNom} · ${item.commercantTelephone}',
      if (reasonText.isNotEmpty) '$secondLine ($reasonText)' else secondLine,
    ].join('\n');

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: item.photoUrl != null ? CachedNetworkImageProvider(item.photoUrl!) : null,
      ),
      title: Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (action) {
          switch (action) {
            case 'masquer':
              onMasquer();
            case 'verifier':
              onVerifierOk();
            case 'avertir':
              onAvertir();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'masquer', child: Text(l10n.masquerLabel)),
          PopupMenuItem(value: 'verifier', child: Text(l10n.verifierOkLabel)),
          PopupMenuItem(value: 'avertir', child: Text(l10n.avertirLabel)),
        ],
      ),
    );
  }
}
