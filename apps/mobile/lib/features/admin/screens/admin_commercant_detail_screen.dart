import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/commercant_origin_verification.dart';
import '../../../domain/enums/registre_status.dart';
import '../../../domain/models/admin_commercant_item.dart';
import '../../../domain/models/commune.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/utils/maps_launcher.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/status_chip.dart';

final _communesProvider = FutureProvider.autoDispose((ref) => ref.watch(communeApiProvider).list());

/// Fiche commerçant côté admin — la liste (`AdminCommercantsScreen`)
/// n'affichait que nom/téléphone tronqués. `GET /admin/commercant` charge
/// déjà l'entité complète (aucune requête supplémentaire) mais n'en
/// exposait qu'une fraction ; complété côté backend (adresse, catégorie,
/// photo, position GPS, origine de vérification) pour cette fiche.
class AdminCommercantDetailScreen extends ConsumerWidget {
  const AdminCommercantDetailScreen({super.key, required this.item});

  final AdminCommercantItem item;

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action, {
    bool popOnSuccess = true,
    String? successMessage,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await action();
      if (!context.mounted) return;
      if (popOnSuccess) {
        Navigator.of(context).pop(true);
      } else if (successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
      }
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

  Future<void> _confirmAndResetPin(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.resetPinConfirmTitle),
        content: Text(l10n.resetPinConfirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.resetPinLabel)),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _act(
      context,
      ref,
      () => ref.read(adminApiProvider).resetPin(item.id),
      popOnSuccess: false,
      successMessage: l10n.resetPinSuccessMessage,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final communesAsync = ref.watch(_communesProvider);
    String? communeName;
    for (final commune in communesAsync.valueOrNull ?? const <Commune>[]) {
      if (commune.id == item.communeId) {
        communeName = commune.nom;
        break;
      }
    }
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(item.nom),
        actions: const [LanguageSwitcherButton()],
      ),
      body: ListView(
        children: [
          if (item.photoUrl != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(imageUrl: item.photoUrl!, fit: BoxFit.cover),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (item.suspended)
                      StatusChip(label: l10n.suspendedBadge, color: colorScheme.error),
                    if (item.originVerification != null)
                      StatusChip(
                        label: commercantOriginVerificationLabel(context, item.originVerification!),
                        color: colorScheme.secondary,
                      ),
                  ],
                ),
                if (item.suspended || item.originVerification != null) const SizedBox(height: 12),
                Text(categorieLabel(context, item.categorie), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.phone_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(item.telephone),
                  ],
                ),
                if (item.adresse != null && item.adresse!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.home_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item.adresse!)),
                    ],
                  ),
                ],
                if (communeName != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(communeName),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text('${l10n.memberSinceLabel} ${dateFormat.format(item.createdAt)}'),
                  ],
                ),
                if (item.latitude != null && item.longitude != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.directions_outlined),
                    label: Text(l10n.itineraryButton),
                    onPressed: () => openMapsAt(item.latitude!, item.longitude!),
                  ),
                ],
                if (item.originVerification == CommercantOriginVerification.autoInscrit) ...[
                  const Divider(height: 40),
                  Text(l10n.registreSectionLabel, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (item.registreStatus == null)
                    Text(l10n.registreNotSentLabel,
                        style: TextStyle(color: colorScheme.onSurfaceVariant))
                  else ...[
                    StatusChip(
                      label: registreStatusLabel(context, item.registreStatus!),
                      color: registreStatusColor(context, item.registreStatus!),
                    ),
                    if (item.registreUrl != null) ...[
                      const SizedBox(height: 12),
                      AspectRatio(
                        aspectRatio: 4 / 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(imageUrl: item.registreUrl!, fit: BoxFit.cover),
                        ),
                      ),
                    ],
                    if (item.registreStatus == RegistreStatus.enAttente) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: () => _act(
                              context,
                              ref,
                              () => ref.read(adminApiProvider).validerRegistre(item.id),
                            ),
                            child: Text(l10n.validerLabel),
                          ),
                          OutlinedButton(
                            onPressed: () => _act(
                              context,
                              ref,
                              () => ref.read(adminApiProvider).rejeterRegistre(item.id),
                            ),
                            child: Text(l10n.rejeterLabel),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    item.suspended
                        ? FilledButton(
                            onPressed: () => _act(
                              context,
                              ref,
                              () => ref.read(adminApiProvider).reactivateCommercant(item.id),
                            ),
                            child: Text(l10n.reactivateLabel),
                          )
                        : OutlinedButton(
                            onPressed: () => _confirmAndSuspend(context, ref),
                            child: Text(l10n.suspendLabel),
                          ),
                    OutlinedButton(
                      onPressed: () => _confirmAndResetPin(context, ref),
                      child: Text(l10n.resetPinLabel),
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

  Future<void> _confirmAndSuspend(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.suspendConfirmTitle),
        content: Text(l10n.suspendConfirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.suspendLabel)),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _act(context, ref, () => ref.read(adminApiProvider).suspendCommercant(item.id));
  }
}
