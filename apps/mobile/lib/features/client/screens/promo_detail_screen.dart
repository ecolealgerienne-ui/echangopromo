import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/env.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/report_reason.dart';
import '../../../domain/models/commercant.dart';
import '../../../domain/models/promo.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/promo_photo_hero.dart';
import '../../shared/widgets/promo_price_row.dart';
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
          final isFavorite = favorites.contains(promo.id);
          final dateFormat = DateFormat('dd/MM/yyyy');

          return ListView(
            children: [
              PromoPhotoHero(
                photoUrl: promo.photoUrl,
                prixAvant: promo.prixAvant,
                prixApres: promo.prixApres,
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
                          icon: const Icon(Icons.share_outlined),
                          tooltip: l10n.shareTooltip,
                          onPressed: () => _share(context, promo),
                        ),
                        IconButton(
                          icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                          onPressed: () =>
                              ref.read(favoritesProvider.notifier).toggle(promo.id),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    PromoPriceRow(prixAvant: promo.prixAvant, prixApres: promo.prixApres),
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

  /// Texte + photo (si disponible) vers le sélecteur de partage natif du
  /// téléphone (WhatsApp, SMS, email...) — pas de lien profond vers l'app
  /// (pas de présence web pour l'instant), juste un message autonome. La
  /// ligne d'installation n'apparaît que si `Env.playStoreUrl`/`appStoreUrl`
  /// est renseigné (vide tant que l'app n'est pas publiée).
  Future<void> _share(BuildContext context, Promo promo) async {
    final l10n = AppLocalizations.of(context)!;
    final currency = NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0);

    final buffer = StringBuffer(
      l10n.shareMessage(
        promo.description,
        promo.commercantNom ?? '',
        currency.format(promo.prixApres),
        currency.format(promo.prixAvant),
      ),
    );
    final storeUrl = Platform.isIOS ? Env.appStoreUrl : Env.playStoreUrl;
    if (storeUrl.isNotEmpty) {
      buffer
        ..writeln()
        ..write(l10n.shareInstallCta(storeUrl));
    }
    final message = buffer.toString();

    final photo = promo.photoUrl != null ? await _downloadForShare(promo.photoUrl!) : null;
    if (photo != null) {
      // Certaines applis (Messenger notamment) ignorent le texte joint à une
      // image dans l'intent de partage natif et n'affichent que la photo —
      // on copie donc le texte dans le presse-papier en complément, pour que
      // l'utilisateur puisse le coller manuellement si l'appli le laisse tomber.
      await Clipboard.setData(ClipboardData(text: message));
      await Share.shareXFiles([XFile(photo.path)], text: message);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.shareTextCopiedNotice)),
        );
      }
    } else {
      await Share.share(message);
    }
  }

  /// `Share` a besoin d'un fichier local, pas d'une URL S3 — un échec de
  /// téléchargement (réseau, image absente) ne doit pas empêcher le
  /// partage, juste le faire retomber sur le texte seul.
  Future<File?> _downloadForShare(String url) async {
    try {
      final dir = await getTemporaryDirectory();
      final path = p.join(dir.path, 'share_promo_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await Dio().download(url, path);
      return File(path);
    } catch (_) {
      return null;
    }
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final reason = await showModalBottomSheet<ReportReason>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.reportReasonTitle, style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final option in ReportReason.values)
              ListTile(
                title: Text(reportReasonLabel(context, option)),
                onTap: () => Navigator.pop(context, option),
              ),
          ],
        ),
      ),
    );
    if (reason == null || !context.mounted) return;

    final locale = Localizations.localeOf(context);
    try {
      await ref.read(reportApiProvider).create(promoId, reason);
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
                Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
