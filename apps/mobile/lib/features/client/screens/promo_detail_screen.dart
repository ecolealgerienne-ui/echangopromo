import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/commercant.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../providers/favorites_provider.dart';
import '../providers/promo_providers.dart';

/// Fiche promo (specs §3.1) : photo, description, prix avant/après, nom et
/// adresse du commerçant, date de fin de validité, signalement.
class PromoDetailScreen extends ConsumerWidget {
  const PromoDetailScreen({super.key, required this.promoId});

  final String promoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final promoAsync = ref.watch(promoDetailProvider(promoId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.promoDetailTitle),
        actions: const [LanguageSwitcherButton()],
      ),
      body: promoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.commonError(error.toString()))),
        data: (promo) {
          final favorites = ref.watch(favoritesProvider);
          final isFavorite = favorites.contains(promo.commercantId);
          final currency = NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0);
          final dateFormat = DateFormat('dd/MM/yyyy');

          return ListView(
            children: [
              if (promo.photoUrl != null)
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: CachedNetworkImage(imageUrl: promo.photoUrl!, fit: BoxFit.cover),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(promo.description, style: Theme.of(context).textTheme.headlineSmall),
                        ),
                        IconButton(
                          icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                          onPressed: () =>
                              ref.read(favoritesProvider.notifier).toggle(promo.commercantId),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          currency.format(promo.prixAvant),
                          style: const TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          currency.format(promo.prixApres),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (promo.dateFin != null)
                      Text(l10n.validUntil(dateFormat.format(promo.dateFin!))),
                    const Divider(height: 32),
                    _CommercantInfo(commercantId: promo.commercantId),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(l10n.reportButton),
                      onPressed: () => _report(context, ref),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);
    try {
      await ref.read(reportApiProvider).create(promoId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.reportSent)));
      }
    } catch (error) {
      final message = extractApiErrorMessage(error, fallback: l10n.reportFailed, locale: locale);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
}

final _commercantPublicProfileProvider =
    FutureProvider.autoDispose.family<Commercant, String>((ref, commercantId) {
  return ref.watch(commercantApiProvider).publicProfile(commercantId);
});

class _CommercantInfo extends ConsumerWidget {
  const _CommercantInfo({required this.commercantId});

  final String commercantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final commercantAsync = ref.watch(_commercantPublicProfileProvider(commercantId));

    return commercantAsync.when(
      loading: () => const SizedBox(height: 40, child: Center(child: CircularProgressIndicator())),
      error: (error, _) => Text(l10n.commonError(error.toString())),
      data: (commercant) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (commercant.photoUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: commercant.photoUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(commercant.nom, style: Theme.of(context).textTheme.titleMedium),
              ),
            ],
          ),
          if (commercant.adresse != null && commercant.adresse!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 18, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(child: Text(commercant.adresse!)),
              ],
            ),
          ],
          if (commercant.latitude != null && commercant.longitude != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.directions_outlined),
              label: Text(l10n.itineraryButton),
              onPressed: () => _openMaps(commercant.latitude!, commercant.longitude!),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openMaps(double latitude, double longitude) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
