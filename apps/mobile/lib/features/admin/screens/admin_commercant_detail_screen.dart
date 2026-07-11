import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/admin_commercant_item.dart';
import '../../../domain/models/commune.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/language_switcher_button.dart';

final _communesProvider = FutureProvider.autoDispose((ref) => ref.watch(communeApiProvider).list());

/// Fiche commerçant côté admin — la liste (`AdminCommercantsScreen`)
/// n'affichait que nom/téléphone tronqués, sans vue détail ni accès à la
/// date d'inscription ou à la commune.
class AdminCommercantDetailScreen extends ConsumerWidget {
  const AdminCommercantDetailScreen({super.key, required this.item});

  final AdminCommercantItem item;

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
        padding: const EdgeInsets.all(16),
        children: [
          if (item.suspended)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colorScheme.error),
              ),
              child: Text(
                l10n.suspendedBadge,
                style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.w600),
              ),
            ),
          Row(
            children: [
              Icon(Icons.phone_outlined, size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(item.telephone),
            ],
          ),
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
          const SizedBox(height: 24),
          item.suspended
              ? FilledButton(
                  onPressed: () =>
                      _act(context, ref, () => ref.read(adminApiProvider).reactivateCommercant(item.id)),
                  child: Text(l10n.reactivateLabel),
                )
              : OutlinedButton(
                  onPressed: () => _confirmAndSuspend(context, ref),
                  child: Text(l10n.suspendLabel),
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
