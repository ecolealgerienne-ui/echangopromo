import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../app/theme.dart';
import '../../../config/env.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/report_reason.dart';
import '../../../domain/models/commercant.dart';
import '../../../domain/models/promo.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/utils/maps_launcher.dart';
import '../../shared/utils/phone_launcher.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/promo_discount_badge.dart';
import '../../shared/widgets/promo_photo_hero.dart';
import '../providers/favorites_provider.dart';
import '../providers/promo_providers.dart';

/// Fiche promo (specs §3.1). Écran de décision : il répond à « combien »,
/// « jusqu'à quand » et « où » avant tout défilement, et garde l'appel et
/// l'itinéraire fixés en bas — les deux seules actions qui font se déplacer
/// un client n'ont pas à être cherchées.
class PromoDetailScreen extends ConsumerWidget {
  const PromoDetailScreen({super.key, required this.promoId});

  final String promoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promoAsync = ref.watch(promoDetailProvider(promoId));

    return Scaffold(
      body: promoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: ApiErrorText(error)),
        data: (promo) => _PromoDetailBody(
          promo: promo,
          onShare: () => _share(context, promo),
          onReport: () => _report(context, ref),
        ),
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

class _PromoDetailBody extends ConsumerWidget {
  const _PromoDetailBody({
    required this.promo,
    required this.onShare,
    required this.onReport,
  });

  final Promo promo;
  final VoidCallback onShare;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isFavorite = ref.watch(favoritesProvider).contains(promo.id);
    final commercantAsync = ref.watch(commercantPublicProfileProvider(promo.commercantId));
    final commercant = commercantAsync.valueOrNull;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Stack(
                children: [
                  PromoPhotoHero(
                    photoUrls: promo.photoUrls,
                    prixAvant: promo.prixAvant,
                    prixApres: promo.prixApres,
                  ),
                  // Retour, partage et favori flottent sur la photo plutôt
                  // que dans une AppBar : la photo garde toute sa hauteur.
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          _GlassButton(
                            icon: Icons.arrow_back,
                            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                            onTap: () =>
                                context.canPop() ? context.pop() : context.go('/'),
                          ),
                          const Spacer(),
                          _GlassButton(
                            icon: Icons.share_outlined,
                            tooltip: l10n.shareTooltip,
                            onTap: onShare,
                          ),
                          const SizedBox(width: 6),
                          _GlassButton(
                            icon: isFavorite ? Icons.favorite : Icons.favorite_border,
                            tooltip: isFavorite
                                ? l10n.removeFavoriteTooltip
                                : l10n.addFavoriteTooltip,
                            highlighted: isFavorite,
                            onTap: () => ref.read(favoritesProvider.notifier).toggle(promo.id),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(promo.description, style: textTheme.titleLarge),
                    const SizedBox(height: 12),
                    _PriceBlock(promo: promo),
                    if (promo.dateFin != null) ...[
                      const SizedBox(height: 12),
                      _DeadlineChip(dateFin: promo.dateFin!),
                    ],
                    const Divider(height: 32),
                    if (commercantAsync.hasError)
                      ApiErrorText(commercantAsync.error!)
                    else if (commercant == null)
                      const SizedBox(
                        height: 64,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      _ShopCard(commercant: commercant),
                    _OtherShopPromos(
                      commercantId: promo.commercantId,
                      excludePromoId: promo.id,
                    ),
                    // Le signalement reste en bas et en discret : nécessaire
                    // à la modération, mais ce n'est pas ce qu'on vient faire
                    // sur cette fiche.
                    Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.flag_outlined, size: 18),
                        label: Text(l10n.reportButton),
                        style: TextButton.styleFrom(
                          foregroundColor: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: onReport,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
        _ActionBar(commercant: commercant),
      ],
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        color: highlighted ? colorScheme.primary : colorScheme.onSurface,
        onPressed: onTap,
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Prix barré, prix promo, puis l'économie **en dinars** : un montant parle
/// plus qu'un pourcentage, lequel figure déjà sur la photo.
class _PriceBlock extends StatelessWidget {
  const _PriceBlock({required this.promo});

  final Promo promo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final semanticColors = Theme.of(context).extension<AppSemanticColors>()!;
    final currency = NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0);
    final saved = promo.prixAvant - promo.prixApres;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currency.format(promo.prixAvant),
                style: textTheme.bodyMedium?.copyWith(
                  decoration: TextDecoration.lineThrough,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                currency.format(promo.prixApres),
                style: textTheme.headlineMedium?.copyWith(color: colorScheme.primary),
              ),
            ],
          ),
        ),
        if (saved > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: semanticColors.success.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              l10n.youSave(currency.format(saved)),
              style: textTheme.labelMedium?.copyWith(
                color: semanticColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

/// Échéance en durée relative plutôt qu'en date : « se termine demain » fait
/// se déplacer aujourd'hui, « 30/07/2026 » demande un calcul mental.
class _DeadlineChip extends StatelessWidget {
  const _DeadlineChip({required this.dateFin});

  final DateTime dateFin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final semanticColors = Theme.of(context).extension<AppSemanticColors>()!;

    // Comparaison sur les jours calendaires, pas sur 24h glissantes : une
    // promo finissant ce soir à 23h et une autre demain à 1h ne doivent pas
    // afficher la même chose.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDay = DateTime(dateFin.year, dateFin.month, dateFin.day);
    final days = endDay.difference(today).inDays;

    final label = switch (days) {
      <= 0 => l10n.endsToday,
      1 => l10n.endsTomorrow,
      _ => l10n.endsInDays(days),
    };
    final urgent = days <= 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (urgent ? semanticColors.warning : colorScheme.onSurfaceVariant)
            .withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: 18,
            color: urgent ? semanticColors.warning : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: textTheme.labelLarge?.copyWith(
                color: urgent ? semanticColors.warning : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.commercant});

  final Commercant commercant;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          if (commercant.photoUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: CachedNetworkImage(
                imageUrl: commercant.photoUrl!,
                width: 46,
                height: 46,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    Container(color: colorScheme.surfaceContainerHighest),
              ),
            )
          else
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.md),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colorScheme.secondary, colorScheme.primary],
                ),
              ),
              child: Icon(Icons.storefront, color: colorScheme.onPrimary, size: 22),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(commercant.nom, style: textTheme.titleSmall),
                if (commercant.adresse != null && commercant.adresse!.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.place_outlined,
                          size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          commercant.adresse!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
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

/// « Autres promos du magasin » — réutilise `GET /promo` avec un filtre
/// `commercantId`, sans nouvel endpoint. Section absente s'il n'y en a pas.
class _OtherShopPromos extends ConsumerWidget {
  const _OtherShopPromos({required this.commercantId, required this.excludePromoId});

  final String commercantId;
  final String excludePromoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final promos = ref
            .watch(shopPromosProvider(
                (commercantId: commercantId, excludePromoId: excludePromoId)))
            .valueOrNull ??
        const <Promo>[];
    if (promos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Text(l10n.otherShopPromosTitle, style: textTheme.titleSmall),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: promos.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) => _MiniPromoCard(promo: promos[index]),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _MiniPromoCard extends StatelessWidget {
  const _MiniPromoCard({required this.promo});

  final Promo promo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final currency = NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0);
    final photo =
        promo.thumbnailUrl ?? (promo.photoUrls.isNotEmpty ? promo.photoUrls.first : null);

    return SizedBox(
      width: 132,
      child: InkWell(
        // `pushReplacement` : enchaîner les promos d'un même magasin ne doit
        // pas empiler dix fiches dans l'historique de retour.
        onTap: () => context.pushReplacement('/promo/${promo.id}'),
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Stack(
                children: [
                  SizedBox(
                    height: 92,
                    width: 132,
                    child: photo == null
                        ? Container(color: colorScheme.surfaceContainerHighest)
                        : CachedNetworkImage(
                            imageUrl: photo,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                Container(color: colorScheme.surfaceContainerHighest),
                          ),
                  ),
                  PositionedDirectional(
                    top: 6,
                    start: 6,
                    child: PromoDiscountBadge(
                      prixAvant: promo.prixAvant,
                      prixApres: promo.prixApres,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      textStyle: textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              promo.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall,
            ),
            Text(
              currency.format(promo.prixApres),
              style: textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Appeler et Itinéraire, fixés en bas. Un bouton est désactivé plutôt que
/// masqué quand la donnée manque : sa disparition ferait bouger l'autre
/// d'une fiche à l'autre.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.commercant});

  final Commercant? commercant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final telephone = commercant?.telephone;
    final latitude = commercant?.latitude;
    final longitude = commercant?.longitude;

    return Material(
      color: colorScheme.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.phone),
                  label: Text(l10n.callButton),
                  onPressed: (telephone != null && telephone.isNotEmpty)
                      ? () => callPhone(telephone)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.directions_outlined),
                  label: Text(l10n.itineraryButton),
                  onPressed: (latitude != null && longitude != null)
                      ? () => openMapsAt(latitude, longitude)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
