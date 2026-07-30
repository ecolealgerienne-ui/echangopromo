import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme.dart';
import '../../../domain/enums/commercant_origin_verification.dart';
import '../../../domain/enums/promo_lifecycle_status.dart';
import '../../../domain/enums/registre_status.dart';
import '../../../domain/models/commercant.dart';
// Préfixé comme dans `notifications_panel.dart` : `Notification` entre en
// collision avec la classe du même nom du framework Flutter.
import '../../../domain/models/notification.dart' as domain;
import '../../../domain/models/promo.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/providers/notification_provider.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/app_settings_actions.dart';
import '../../shared/widgets/notifications_panel.dart';
import '../../shared/widgets/status_chip.dart';
import '../providers/commercant_providers.dart';

/// Dashboard commerçant (specs §3.2) : donne une raison concrète de revenir
/// régulièrement dans l'app, en plus de l'obligation de republication.
///
/// Organisé autour des deux questions qu'un commerçant se pose en ouvrant
/// l'app : « combien de promos ai-je en ligne ? » et « est-ce que ça
/// marche ? ». Le plafond de 5 actives est donc affiché en tête — c'est une
/// règle structurelle du produit, et il ne la découvrait jusqu'ici qu'en se
/// faisant refuser une publication.
class CommercantDashboardScreen extends ConsumerWidget {
  const CommercantDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final meAsync = ref.watch(commercantMeProvider);
    final promosAsync = ref.watch(myPromosProvider);
    final profileViewsAsync = ref.watch(commercantProfileViewsProvider);

    final promos = promosAsync.valueOrNull ?? const <Promo>[];
    final activeCount = countActivePromos(promos);
    final atCap = activeCount >= kMaxPromosActives;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const BackButtonIcon(),
          tooltip: l10n.backToHomeTooltip,
          // Ce dashboard est toujours atteint via un `go()` (jamais un
          // `push()`) depuis les écrans de connexion — la pile de
          // navigation est donc vide et Flutter n'affiche aucun bouton
          // retour automatique. Bouton explicite plutôt que de dépendre de
          // `context.canPop()`, systématiquement faux ici.
          onPressed: () => context.go('/'),
        ),
        title: Text(l10n.myCommercantSpaceTitle),
        actions: [
          const AppSettingsActions(),
          IconButton(
            icon: const NotificationBadge(),
            tooltip: l10n.notificationsTooltip,
            onPressed: () => context.push('/commercant/notifications'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (action) async {
              switch (action) {
                case 'editProfile':
                  final updated = await context.push<bool>('/commercant/profile/edit');
                  if (updated == true) ref.invalidate(commercantMeProvider);
                case 'logout':
                  await ref.read(authControllerProvider.notifier).logout();
                  if (context.mounted) context.go('/');
              }
            },
            itemBuilder: (context) => [
              // Modifier sa fiche passe en menu : un commerçant le fait deux
              // fois par an, publier une promo dix fois par mois. Les deux
              // partageaient jusqu'ici le même poids visuel.
              PopupMenuItem(value: 'editProfile', child: Text(l10n.editProfileLabel)),
              PopupMenuItem(value: 'logout', child: Text(l10n.logoutTooltip)),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(commercantMeProvider);
          ref.invalidate(myPromosProvider);
          ref.invalidate(commercantProfileViewsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            meAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => ApiErrorText(error),
              data: (commercant) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ShopHeader(commercant: commercant),
                  _RegistreStatusBanner(commercant: commercant),
                  if (commercant.profilePendingReview) const _ProfilePendingReviewBanner(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _QuotaCard(activeCount: activeCount, loading: promosAsync.isLoading),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: l10n.profileViewsLabel,
                    value: profileViewsAsync.valueOrNull,
                    loading: profileViewsAsync.isLoading,
                    icon: Icons.storefront_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    label: l10n.dashboardPromoViewsLabel,
                    value: promosAsync.valueOrNull == null ? null : totalPromoViews(promos),
                    loading: promosAsync.isLoading,
                    icon: Icons.visibility_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Les alertes de modération restent au-dessus de la liste, pas
            // derrière l'icône cloche : le commerçant ne doit pas avoir à
            // penser à cliquer pour les découvrir.
            const _UnreadNotificationsBanner(),
            Row(
              children: [
                Expanded(
                  child: Text(l10n.myPromosLabel, style: Theme.of(context).textTheme.titleSmall),
                ),
                TextButton(
                  onPressed: () => context.push('/commercant/promos'),
                  child: Text(l10n.seeAllLabel),
                ),
              ],
            ),
            const SizedBox(height: 4),
            switch (promosAsync) {
              AsyncValue(hasError: true, :final error?) => ApiErrorText(error),
              AsyncValue(isLoading: true) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                ),
              _ => _PromoPreviewList(promos: promos),
            },
          ],
        ),
      ),
      // Une seule action mise en avant, fixée en bas : publier est ce qu'un
      // commerçant vient faire, tout le reste en découle.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: atCap ? null : () => context.push('/commercant/promos/new'),
        backgroundColor: atCap ? Theme.of(context).colorScheme.surfaceContainerHighest : null,
        foregroundColor: atCap ? Theme.of(context).colorScheme.onSurfaceVariant : null,
        icon: Icon(atCap ? Icons.block : Icons.add),
        // Désactivé plutôt que masqué au plafond : sa disparition laisserait
        // croire à un bug, alors que le message explique la limite.
        label: Text(atCap ? l10n.capReachedLabel : l10n.newPromoTitle),
      ),
    );
  }
}

/// Nom, catégorie et badge « Vérifié » — l'identité que le client voit.
class _ShopHeader extends StatelessWidget {
  const _ShopHeader({required this.commercant});

  final Commercant commercant;

  String get _initials {
    final words =
        commercant.nom.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return (words[0].characters.first + words[1].characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final semanticColors = Theme.of(context).extension<AppSemanticColors>()!;
    final verified = isRegistreVerified(commercant);

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: commercant.photoUrl != null
              ? CachedNetworkImage(
                  imageUrl: commercant.photoUrl!,
                  width: 46,
                  height: 46,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => _InitialsBox(initials: _initials),
                )
              : _InitialsBox(initials: _initials),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                commercant.nom,
                style: textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      categorieLabel(context, commercant.categorie),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.verified, size: 15, color: semanticColors.success),
                    const SizedBox(width: 2),
                    Text(
                      l10n.verifiedBadge,
                      style: textTheme.bodySmall?.copyWith(
                        color: semanticColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InitialsBox extends StatelessWidget {
  const _InitialsBox({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.md),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.secondary, colorScheme.primary],
        ),
      ),
      child: Text(
        initials,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(color: colorScheme.onPrimary),
      ),
    );
  }
}

/// Emplacements de promos occupés sur le plafond autorisé. Le plafond est une
/// règle serveur appliquée à tout le monde ; l'afficher évite au commerçant
/// de ne le découvrir qu'au moment d'un refus de publication.
class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.activeCount, required this.loading});

  final int activeCount;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final remaining = kMaxPromosActives - activeCount;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.dashboardActivePromosLabel.toUpperCase(),
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (loading)
                      const SizedBox(
                        height: 28,
                        width: 28,
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    else
                      Text.rich(
                        TextSpan(
                          text: '$activeCount',
                          style: textTheme.headlineMedium,
                          children: [
                            TextSpan(
                              text: ' / $kMaxPromosActives',
                              style: textTheme.titleMedium
                                  ?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (!loading)
                Flexible(
                  child: Text(
                    l10n.dashboardSlotsLeft(remaining),
                    textAlign: TextAlign.end,
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Une barre par emplacement : le commerçant compte d'un regard,
          // sans lire le chiffre.
          Row(
            children: [
              for (var i = 0; i < kMaxPromosActives; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(
                  child: Container(
                    height: 7,
                    decoration: BoxDecoration(
                      color: i < activeCount
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.loading,
    required this.icon,
  });

  final String label;
  final int? value;
  final bool loading;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(height: 8),
          if (loading)
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            Text(
              value?.toString() ?? '—',
              style: textTheme.titleLarge,
            ),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Trois promos au plus, avec leur statut. Assez pour savoir ce qui travaille
/// et ce qui dort ; la liste complète reste derrière « Tout voir ».
class _PromoPreviewList extends StatelessWidget {
  const _PromoPreviewList({required this.promos});

  final List<Promo> promos;

  static const _previewCount = 3;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    if (promos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            l10n.noPromosYet,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    // En ligne d'abord : c'est ce qui est visible des clients maintenant.
    final sorted = [...promos]..sort((a, b) {
      final aLive = a.lifecycleStatus == PromoLifecycleStatus.publiee ? 0 : 1;
      final bLive = b.lifecycleStatus == PromoLifecycleStatus.publiee ? 0 : 1;
      return aLive.compareTo(bLive);
    });

    return Column(
      children: [
        for (final promo in sorted.take(_previewCount))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PromoPreviewRow(promo: promo),
          ),
      ],
    );
  }
}

class _PromoPreviewRow extends StatelessWidget {
  const _PromoPreviewRow({required this.promo});

  final Promo promo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final photo = promo.thumbnailUrl ?? promo.photoUrl;
    final isExpired = promo.dateFin != null && promo.dateFin!.isBefore(DateTime.now());

    return InkWell(
      onTap: () => context.push('/commercant/promos'),
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant, width: 1.5),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: SizedBox(
                width: 44,
                height: 44,
                child: photo == null
                    ? Container(color: colorScheme.surfaceContainerHighest)
                    : CachedNetworkImage(
                        imageUrl: photo,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            Container(color: colorScheme.surfaceContainerHighest),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    promo.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      StatusChip(
                        label: promoLifecycleLabel(
                          context,
                          promo.lifecycleStatus,
                          isExpired: isExpired,
                        ),
                        color: promoLifecycleColor(
                          context,
                          promo.lifecycleStatus,
                          isExpired: isExpired,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          l10n.myPromosViewsCount(promo.viewCount ?? 0),
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
      ),
    );
  }
}

/// Alertes affichées directement sur le dashboard — pas seulement derrière
/// l'icône cloche, pour que le commerçant ne les découvre pas s'il pense à
/// cliquer dessus. Chacune reste visible tant qu'elle n'est pas marquée lue
/// (aucune republication automatique de la promo).
///
/// En slider horizontal et non plus en pile verticale (retour terrain
/// 2026-07-29) : plusieurs promos arrivant à expiration le même jour
/// produisaient autant de cartes pleine largeur, qui repoussaient le quota et
/// la liste hors de l'écran. Dix alertes occupent désormais la place d'une.
class _UnreadNotificationsBanner extends ConsumerStatefulWidget {
  const _UnreadNotificationsBanner();

  @override
  ConsumerState<_UnreadNotificationsBanner> createState() =>
      _UnreadNotificationsBannerState();
}

class _UnreadNotificationsBannerState
    extends ConsumerState<_UnreadNotificationsBanner> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _markAsRead(String notificationId) async {
    await ref.read(notificationControllerProvider).markAsRead(notificationId);
    _invalidate();
  }

  Future<void> _markAllAsRead() async {
    await ref.read(notificationControllerProvider).markAllAsRead();
    _invalidate();
  }

  void _invalidate() {
    ref.invalidate(notificationsProvider);
    ref.invalidate(notificationHistoryProvider);
    ref.invalidate(unreadNotificationCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final unread = ref.watch(notificationsProvider).valueOrNull?.items ?? const [];
    if (unread.isEmpty) return const SizedBox.shrink();

    // La page courante peut dépasser après un "marquer comme lu" : la liste
    // rétrécit sans que le PageController en soit informé.
    final index = _index.clamp(0, unread.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.notifications_active_outlined, size: 17, color: colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.alertsCount(unread.length),
                style: textTheme.titleSmall,
              ),
            ),
            // Avec plusieurs alertes du même type, les écarter une par une
            // est fastidieux — l'API sait déjà tout marquer d'un coup.
            if (unread.length > 1)
              TextButton(
                onPressed: _markAllAsRead,
                child: Text(l10n.markAllReadLabel),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          // Hauteur fixe imposée par `PageView`, calée sur trois lignes de
          // message plus la rangée d'actions.
          height: 116,
          child: PageView.builder(
            controller: _controller,
            itemCount: unread.length,
            onPageChanged: (page) => setState(() => _index = page),
            itemBuilder: (context, i) {
              final notification = unread[i];
              return Padding(
                // Laisse deviner la carte suivante : sans ce décalage, rien
                // n'indique qu'on peut faire glisser.
                padding: EdgeInsetsDirectional.only(end: i == unread.length - 1 ? 0 : 8),
                child: _AlertCard(
                  notification: notification,
                  onOpen: () => context.push('/commercant/promos'),
                  onMarkRead: () => _markAsRead(notification.id),
                ),
              );
            },
          ),
        ),
        if (unread.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < unread.length; i++)
                  AnimatedContainer(
                    duration: kAppTransitionDuration,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == index ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == index ? colorScheme.primary : colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.notification,
    required this.onOpen,
    required this.onMarkRead,
  });

  final domain.Notification notification;
  final VoidCallback onOpen;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final color = notificationIconColor(context, notification.type);

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        border: Border.all(color: color.withValues(alpha: 0.32)),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(notificationIcon(notification.type), color: color, size: 19),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    notification.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: onOpen,
                child: Text(l10n.reviewPromoCta),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.check, size: 18),
                tooltip: l10n.markAsReadTooltip,
                visualDensity: VisualDensity.compact,
                onPressed: onMarkRead,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Statut du registre pour un commerçant auto-inscrit — aucune promo ne
/// peut être publiée tant qu'il n'est pas `validé` par un admin (revert du
/// 2026-07-11, voir `CommercantService.assertRegistreValidated`). Un
/// commerçant confirmé par un agent n'est jamais concerné.
class _RegistreStatusBanner extends ConsumerWidget {
  const _RegistreStatusBanner({required this.commercant});

  final Commercant commercant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (commercant.originVerification != CommercantOriginVerification.autoInscrit) {
      return const SizedBox.shrink();
    }
    if (commercant.registreStatus == RegistreStatus.valide) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final semanticColors = Theme.of(context).extension<AppSemanticColors>()!;

    // `null` (jamais envoyé) traité comme "en attente" — même bannière.
    // Seul le cas rejeté propose une action (`RegistreResendScreen`) : un
    // "en attente" n'a rien de plus à faire qu'attendre la décision admin.
    final isRejected = commercant.registreStatus == RegistreStatus.rejete;
    final title = isRejected ? l10n.registreRejectedBannerTitle : l10n.registrePendingBannerTitle;
    final message =
        isRejected ? l10n.registreRejectedBannerMessage : l10n.registrePendingBannerMessage;
    final color = isRejected ? colorScheme.error : semanticColors.warning;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: _AlertBox(
        color: color,
        title: title,
        message: message,
        action: isRejected
            ? _AlertAction(
                label: l10n.registreResendSubmit,
                onPressed: () async {
                  final sent = await context.push<bool>('/commercant/registre/resend');
                  if (sent == true && context.mounted) ref.invalidate(commercantMeProvider);
                },
              )
            : null,
      ),
    );
  }
}

/// Bannière "profil en attente de validation" — indépendante du registre :
/// toute modification de profil (`PATCH /commercant/me`) bloque la
/// publication jusqu'à validation admin, pour tous les commerçants, y
/// compris ceux confirmés par un agent (décision produit 2026-07-12).
class _ProfilePendingReviewBanner extends StatelessWidget {
  const _ProfilePendingReviewBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semanticColors = Theme.of(context).extension<AppSemanticColors>()!;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: _AlertBox(
        color: semanticColors.warning,
        title: l10n.profilePendingReviewBannerTitle,
        message: l10n.profilePendingReviewBannerMessage,
      ),
    );
  }
}

class _AlertAction {
  const _AlertAction({required this.label, required this.onPressed});

  final String label;
  final Future<void> Function() onPressed;
}

/// Bandeau d'alerte teinté. Remplace la `Card` des deux bannières : sur fond
/// blanc, une carte grise sans bordure colorée ne se distinguait plus d'un
/// bloc de contenu ordinaire.
class _AlertBox extends StatelessWidget {
  const _AlertBox({
    required this.color,
    required this.title,
    required this.message,
    this.action,
  });

  final Color color;
  final String title;
  final String message;
  final _AlertAction? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final currentAction = action;

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                Text(message, style: textTheme.bodySmall),
                if (currentAction != null) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: color,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: currentAction.onPressed,
                    child: Text(currentAction.label),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
