import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../domain/enums/report_reason.dart';
import '../../../domain/models/moderation_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/widgets/status_chip.dart';

/// Ligne "promo à modérer" (masquer / vérifier OK / avertir) — partagée
/// entre la file automatique (`ModerationQueueScreen`, signalements ≥
/// seuil) et la vue globale (`AdminPromosScreen`, toutes les promos, plan
/// de correction Phase 2). CLAUDE.md règle #21 : extrait dès la 2e
/// duplication.
class PromoModerationTile extends StatelessWidget {
  const PromoModerationTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onMasquer,
    required this.onVerifierOk,
    required this.onAvertir,
    this.loading = false,
  });

  final ModerationItem item;
  final VoidCallback onTap;
  final Future<void> Function() onMasquer;
  final Future<void> Function() onVerifierOk;
  final Future<void> Function() onAvertir;

  /// Action en cours (masquer/vérifier/avertir) sur cette ligne — désactive
  /// le menu et affiche un spinner, sans quoi un double-tap pendant la
  /// latence réseau peut déclencher l'action deux fois (audit UX 2026-07-11).
  final bool loading;

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

    // CircleAvatar par défaut : 40dp de diamètre — décodage limité à cette
    // taille plutôt qu'à la résolution source de l'image.
    final avatarCachePx = (40 * MediaQuery.of(context).devicePixelRatio).round();

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundImage: item.photoUrl != null
            ? ResizeImage(CachedNetworkImageProvider(item.photoUrl!), width: avatarCachePx)
            : null,
      ),
      // Sans ce badge, le statut réel (signalée/masquée/vérifiée) n'était
      // visible qu'après avoir ouvert la fiche détail de chaque promo une
      // par une (audit design 2026-07-11).
      title: Row(
        children: [
          Expanded(
            child: Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          StatusChip(
            label: moderationStatusLabel(context, item.moderationStatus),
            color: moderationStatusColor(context, item.moderationStatus),
          ),
        ],
      ),
      subtitle: Text(subtitle),
      isThreeLine: true,
      trailing: loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : PopupMenuButton<String>(
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
