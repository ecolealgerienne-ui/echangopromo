import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme.dart';
import '../../../domain/enums/commercant_origin_verification.dart';
import '../../../domain/enums/registre_status.dart';
import '../../../domain/models/commercant.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';
import '../../shared/providers/notification_provider.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/notifications_panel.dart';

/// Dashboard commerçant (specs §3.2) : donne une raison concrète de revenir
/// régulièrement dans l'app, en plus de l'obligation de republication.
class CommercantDashboardScreen extends ConsumerWidget {
  const CommercantDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final meAsync = ref.watch(_meProvider);
    final statsAsync = ref.watch(_statsProvider);

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
          const LanguageSwitcherButton(),
          IconButton(
            icon: const NotificationBadge(),
            tooltip: l10n.notificationsTooltip,
            onPressed: () => context.push('/commercant/notifications'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (action) async {
              switch (action) {
                case 'logout':
                  await ref.read(authControllerProvider.notifier).logout();
                  if (context.mounted) context.go('/');
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'logout', child: Text(l10n.logoutTooltip)),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_meProvider);
          ref.invalidate(_statsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _UnreadNotificationsBanner(),
            meAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => ApiErrorText(error),
              data: (commercant) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(commercant.nom, style: Theme.of(context).textTheme.headlineSmall),
                  _RegistreStatusBanner(commercant: commercant),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text(l10n.profileViewsLabel),
                trailing: statsAsync.when(
                  loading: () => const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => const Text('-'),
                  data: (count) => Text('$count', style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.local_offer_outlined),
              label: Text(l10n.myPromosLabel),
              onPressed: () => context.push('/commercant/promos'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.storefront_outlined),
              label: Text(l10n.editProfileLabel),
              onPressed: () async {
                final updated = await context.push<bool>('/commercant/profile/edit');
                if (updated == true) {
                  ref.invalidate(_meProvider);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

final _meProvider = FutureProvider.autoDispose((ref) => ref.watch(commercantApiProvider).me());
final _statsProvider =
    FutureProvider.autoDispose((ref) => ref.watch(commercantApiProvider).dashboardProfileViewCount());

/// Alertes de modération affichées directement sur le dashboard — pas
/// seulement derrière l'icône cloche, pour que le commerçant ne les
/// découvre pas seulement s'il pense à cliquer dessus. Reste affichée tant
/// que le commerçant n'a pas marqué la notification comme lue (aucune
/// republication automatique de la promo).
class _UnreadNotificationsBanner extends ConsumerWidget {
  const _UnreadNotificationsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final notificationsAsync = ref.watch(notificationsProvider);
    final controller = ref.watch(notificationControllerProvider);

    return notificationsAsync.maybeWhen(
      data: (paginated) {
        final unread = paginated.items;
        if (unread.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final notification in unread)
              Card(
                color: notificationIconColor(context, notification.type).withValues(alpha: 0.1),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    notificationIcon(notification.type),
                    color: notificationIconColor(context, notification.type),
                  ),
                  title: Text(notification.message),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => context.push('/commercant/promos'),
                        child: Text(l10n.reviewPromoCta),
                      ),
                      // Sans ce bouton, une notification traitée (promo déjà
                      // republiée) n'avait aucun moyen de quitter la liste
                      // des non lues — elle ne passait jamais à l'historique.
                      IconButton(
                        icon: const Icon(Icons.check),
                        tooltip: l10n.markAsReadTooltip,
                        onPressed: () async {
                          await controller.markAsRead(notification.id);
                          ref.invalidate(notificationsProvider);
                          ref.invalidate(notificationHistoryProvider);
                          ref.invalidate(unreadNotificationCountProvider);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
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
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: color.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(message),
                    if (isRejected) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () async {
                          final sent = await context.push<bool>('/commercant/registre/resend');
                          if (sent == true && context.mounted) ref.invalidate(_meProvider);
                        },
                        child: Text(l10n.registreResendSubmit),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
