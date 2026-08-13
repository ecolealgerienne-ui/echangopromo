import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../app/theme.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/commercant_origin_verification.dart';
import '../../../domain/enums/registre_status.dart';
import '../../../domain/models/admin_commercant_item.dart';
import '../../../domain/models/auth_session.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/core_providers.dart';
import '../../shared/l10n/enum_labels.dart';
import '../../shared/utils/maps_launcher.dart';
import '../../shared/validators/pin_validator.dart';
import '../../shared/widgets/app_settings_actions.dart';
import '../../shared/widgets/status_chip.dart';

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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
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

  /// PIN vraiment oublié (le commerçant ne peut fournir aucun ancien PIN) —
  /// l'admin/agent fixe directement un nouveau PIN, à communiquer par
  /// téléphone après avoir identifié l'appelant (décision produit
  /// 2026-07-13 : plus de remise à zéro suivie d'une revendication
  /// publique, exploitable par quiconque connaissait juste le numéro).
  Future<void> _confirmAndResetPin(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final newPin = await _promptForNewPin(
      context,
      title: l10n.resetPinDialogTitle,
      body: l10n.resetPinDialogBody,
    );
    if (newPin == null || !context.mounted) return;
    await _act(
      context,
      ref,
      () => ref.read(adminApiProvider).resetPin(item.id, newPin),
      popOnSuccess: false,
      successMessage: l10n.resetPinSuccessMessage,
    );
  }

  /// Fixe — ou libère — le plafond de promos actives de ce commerçant.
  ///
  /// ⚠️ **Le champ vide n'est pas zéro.** Il remet le commerçant sur le
  /// réglage global, ce qu'aucun chiffre ne saurait dire : écrire « 5 » pour
  /// signifier « comme tout le monde » figerait ce commerçant le jour où le
  /// global changerait. Zéro, lui, reste saisissable et signifie « ne peut
  /// plus publier » — une mesure graduée, sans suspendre le compte.
  Future<void> _modifierPlafond(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final controller =
        TextEditingController(text: item.promoActiveCap?.toString() ?? '');

    final saisie = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.promoCapDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.promoCapDialogBody),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l10n.promoCapFieldLabel),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (saisie == null || !context.mounted) return;

    // Le serveur borne à 0..50 et refuse le reste ; on ne recopie pas ces
    // bornes ici (règle #32) — on se contente de distinguer « vide » de
    // « nombre », la seule chose que l'écran doit décider.
    final plafond = saisie.isEmpty ? null : int.tryParse(saisie);
    if (saisie.isNotEmpty && plafond == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.commonInvalid)));
      return;
    }

    await _act(
      context,
      ref,
      () => ref.read(adminApiProvider).setPromoActiveCap(item.id, plafond),
      popOnSuccess: true,
    );
  }

  Future<String?> _promptForNewPin(
    BuildContext context, {
    required String title,
    required String body,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final pinController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(body, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              TextFormField(
                controller: pinController,
                decoration: InputDecoration(labelText: l10n.newPinLabel),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 12,
                validator: validatePin(context),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.commonCancel)),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context, pinController.text.trim());
            },
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    // ⚠️ **C'était le seul écran du produit à afficher un nom de commune**, et
    // il fallait une requête entière (`GET /commune`, la liste complète) pour
    // résoudre un identifiant en libellé. L'adresse, elle, est déjà là — servie
    // par la même réponse, affichée deux blocs plus haut. Le repère de lieu
    // n'est donc pas perdu : il vient d'un champ que le commerçant a saisi
    // lui-même, au lieu d'un découpage administratif.
    //
    // Même pattern que AdminPromosScreen/AdminCommercantsScreen (écran
    // partagé admin/agent, décision produit 2026-07-12) : l'admin gagne la
    // capacité de publier une promo pour un commerçant, même écran que
    // l'agent (AgentPromoFormScreen). Plus aucune garde d'appartenance côté
    // backend pour l'un comme pour l'autre depuis le 2026-08-13.
    final role = ref.read(authControllerProvider).value?.role;
    final newPromoPath = role == AppRole.agent
        ? '/agent/promo/new/${item.id}'
        : '/admin/promo/new/${item.id}';
    final dateFormat = DateFormat('dd/MM/yyyy');
    // Décode à la largeur physique réellement affichée plutôt que la pleine
    // résolution source — sans effet si ça dépasse l'original (~1200px max),
    // `memCacheWidth` ne fait jamais remonter au-dessus.
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final screenWidthPx =
        (MediaQuery.sizeOf(context).width * devicePixelRatio).round();
    final paddedWidthPx =
        (MediaQuery.sizeOf(context).width - 32) * devicePixelRatio;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.nom),
        actions: const [AppSettingsActions()],
      ),
      body: ListView(
        children: [
          if (item.photoUrl != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: item.photoUrl!,
                fit: BoxFit.cover,
                memCacheWidth: screenWidthPx,
              ),
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
                      StatusChip(
                          label: l10n.suspendedBadge, color: colorScheme.error),
                    if (item.deleted)
                      StatusChip(
                          label: l10n.deletedBadge, color: colorScheme.error),
                    if (item.originVerification != null)
                      StatusChip(
                        label: commercantOriginVerificationLabel(
                            context, item.originVerification!),
                        color: colorScheme.secondary,
                      ),
                    if (item.profilePendingReview)
                      StatusChip(
                        label: l10n.profilePendingReviewBadgeLabel,
                        color: Theme.of(context)
                            .extension<AppSemanticColors>()!
                            .warning,
                      ),
                  ],
                ),
                if (item.suspended ||
                    item.deleted ||
                    item.originVerification != null ||
                    item.profilePendingReview)
                  const SizedBox(height: 12),
                Text(categorieLabel(context, item.categorie),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.phone_outlined,
                        size: 18, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(item.telephone),
                  ],
                ),
                if (item.adresse != null && item.adresse!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.home_outlined,
                          size: 18, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item.adresse!)),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 18, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                        '${l10n.memberSinceLabel} ${dateFormat.format(item.createdAt)}'),
                  ],
                ),
                if (item.latitude != null && item.longitude != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.directions_outlined),
                    label: Text(l10n.itineraryButton),
                    onPressed: () =>
                        openMapsAt(item.latitude!, item.longitude!),
                  ),
                ],
                const Divider(height: 40),
                Text(l10n.promoCapSectionLabel,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                // ⚠️ Deux textes distincts, jamais un chiffre dans les deux
                // cas : « suit le réglage global » et « 8 » ne veulent pas
                // dire la même chose, et les confondre ferait perdre
                // l'information qui compte — ce commerçant a-t-il été réglé ?
                Text(
                  item.promoActiveCap == null
                      ? l10n.promoCapGlobalLabel
                      : l10n.promoCapCustomLabel(item.promoActiveCap!),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune),
                  label: Text(l10n.promoCapEditLabel),
                  onPressed: () => _modifierPlafond(context, ref),
                ),
                if (item.originVerification ==
                    CommercantOriginVerification.autoInscrit) ...[
                  const Divider(height: 40),
                  Text(l10n.registreSectionLabel,
                      style: Theme.of(context).textTheme.titleMedium),
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
                          child: CachedNetworkImage(
                            imageUrl: item.registreUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: paddedWidthPx.round(),
                          ),
                        ),
                      ),
                    ],
                    // Toujours modifiable, quel que soit le statut actuel —
                    // jusqu'au 2026-07-12 un rejet était définitif côté
                    // admin, sans recours pour corriger une erreur de
                    // modération sans repasser par le commerçant.
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed:
                              item.registreStatus == RegistreStatus.valide
                                  ? null
                                  : () => _act(
                                        context,
                                        ref,
                                        () => ref
                                            .read(adminApiProvider)
                                            .validerRegistre(item.id),
                                      ),
                          child: Text(l10n.validerLabel),
                        ),
                        OutlinedButton(
                          onPressed:
                              item.registreStatus == RegistreStatus.rejete
                                  ? null
                                  : () => _act(
                                        context,
                                        ref,
                                        () => ref
                                            .read(adminApiProvider)
                                            .rejeterRegistre(item.id),
                                      ),
                          child: Text(l10n.rejeterLabel),
                        ),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(l10n.newPromoTitle),
                      onPressed: (item.suspended || item.deleted)
                          ? null
                          : () =>
                              context.push(newPromoPath, extra: item.categorie),
                    ),
                    if (!item.deleted) ...[
                      item.suspended
                          ? FilledButton(
                              onPressed: () => _act(
                                context,
                                ref,
                                () => ref
                                    .read(adminApiProvider)
                                    .reactivateCommercant(item.id),
                              ),
                              child: Text(l10n.reactivateLabel),
                            )
                          : OutlinedButton(
                              onPressed: () => _confirmAndSuspend(context, ref),
                              child: Text(l10n.suspendLabel),
                            ),
                      OutlinedButton(
                        onPressed: () => _confirmAndDelete(context, ref),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.error),
                        child: Text(l10n.deleteCommercantLabel),
                      ),
                      OutlinedButton(
                        onPressed: () => _confirmAndResetPin(context, ref),
                        child: Text(l10n.resetPinLabel),
                      ),
                    ],
                    if (item.profilePendingReview)
                      FilledButton.tonal(
                        // `popOnSuccess` (défaut) plutôt que rester sur cet
                        // écran : `item` est figé au moment de la
                        // navigation, il ne se rafraîchirait pas tout seul
                        // après validation — même pattern que valider/
                        // rejeter le registre.
                        onPressed: () => _act(
                          context,
                          ref,
                          () =>
                              ref.read(adminApiProvider).validerProfil(item.id),
                        ),
                        child: Text(l10n.validerProfilLabel),
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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.suspendLabel)),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _act(context, ref,
        () => ref.read(adminApiProvider).suspendCommercant(item.id));
  }

  /// Suppression logique par l'admin/agent (2026-07-14) — distincte de la
  /// suspension : libère le numéro de téléphone et "supprime" les promos,
  /// pas de restauration prévue (contrairement à la suspension).
  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteCommercantConfirmTitle),
        content: Text(l10n.deleteCommercantConfirmMessage),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.deleteCommercantLabel,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _act(context, ref,
        () => ref.read(adminApiProvider).deleteCommercant(item.id));
  }
}
