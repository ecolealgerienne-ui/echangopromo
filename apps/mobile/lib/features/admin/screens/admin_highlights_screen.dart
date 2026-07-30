import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/models/highlight.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/core_providers.dart';
import '../../shared/widgets/api_error_text.dart';
import '../../shared/widgets/app_settings_actions.dart';
import '../providers/highlight_providers.dart';

/// Curation du bandeau « Top promos » de l'accueil client.
///
/// Ce bandeau était purement calculé (la plus forte réduction l'emportait,
/// prix avant gonflé compris) : cet écran donne à l'admin la main sur ce qui
/// s'y affiche, dans quel ordre, et avec quelle image. Vider la liste ne
/// casse rien — le backend retombe alors sur le classement d'avant, d'où
/// l'état vide qui l'explique plutôt que d'alerter.
class AdminHighlightsScreen extends ConsumerWidget {
  const AdminHighlightsScreen({super.key});

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await action();
      ref.invalidate(adminHighlightsProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(extractApiErrorMessage(
            error,
            fallback: l10n.operationFailed,
            locale: Localizations.localeOf(context),
          )),
        ),
      );
      // Recharge malgré l'échec : l'ordre local peut avoir bougé à l'écran
      // (glisser-déposer optimiste) sans être accepté par le serveur.
      ref.invalidate(adminHighlightsProvider);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Highlight highlight,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.highlightDeleteConfirmTitle),
        content: Text(l10n.highlightDeleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.highlightDeleteLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(highlightApiProvider).delete(highlight.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final highlightsAsync = ref.watch(adminHighlightsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.highlightsTitle),
        actions: const [AppSettingsActions()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/highlights/new'),
        icon: const Icon(Icons.add),
        label: Text(l10n.highlightAddLabel),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminHighlightsProvider),
        child: highlightsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [ApiErrorText(error)],
          ),
          data: (highlights) => highlights.isEmpty
              ? _EmptyState(onAdd: () => context.push('/admin/highlights/new'))
              : _HighlightList(
                  highlights: highlights,
                  onReorder: (ids) => _run(
                    context,
                    ref,
                    () => ref.read(highlightApiProvider).reorder(ids),
                  ),
                  onToggleActive: (highlight, active) => _run(
                    context,
                    ref,
                    () => ref
                        .read(highlightApiProvider)
                        .update(highlight.id, active: active),
                  ),
                  onEdit: (highlight) =>
                      context.push('/admin/highlights/edit', extra: highlight),
                  onDelete: (highlight) => _confirmDelete(context, ref, highlight),
                ),
        ),
      ),
    );
  }
}

/// L'absence de mise en avant n'est pas une anomalie : c'est le mode par
/// défaut du produit. L'état vide décrit ce qui se passe alors, plutôt que
/// de presser l'admin d'agir.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
      children: [
        Icon(Icons.view_carousel_outlined, size: 56, color: colorScheme.outline),
        const SizedBox(height: 16),
        Text(
          l10n.highlightsEmptyTitle,
          textAlign: TextAlign.center,
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.highlightsEmptyBody,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: Text(l10n.highlightAddLabel),
        ),
      ],
    );
  }
}

class _HighlightList extends StatelessWidget {
  const _HighlightList({
    required this.highlights,
    required this.onReorder,
    required this.onToggleActive,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Highlight> highlights;
  final ValueChanged<List<String>> onReorder;
  final void Function(Highlight highlight, bool active) onToggleActive;
  final ValueChanged<Highlight> onEdit;
  final ValueChanged<Highlight> onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: highlights.length,
      // `header` reste hors du glisser-déposer : seuls les enfants
      // construits par `itemBuilder` sont déplaçables.
      header: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
        child: Text(
          l10n.highlightsReorderHint,
          style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
      onReorder: (oldIndex, newIndex) {
        // Convention Flutter : `newIndex` est calculé avant retrait de
        // l'élément déplacé, il faut le décrémenter quand on descend.
        final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
        final ids = highlights.map((highlight) => highlight.id).toList();
        ids.insert(target, ids.removeAt(oldIndex));
        // Envoi de l'ordre complet : le backend refuse une liste partielle
        // (`HIGHLIGHT_REORDER_MISMATCH`) pour ne jamais laisser deux
        // diapositives sur la même position.
        onReorder(ids);
      },
      itemBuilder: (context, index) {
        final highlight = highlights[index];
        return Padding(
          key: ValueKey(highlight.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: _HighlightTile(
            highlight: highlight,
            onToggleActive: (active) => onToggleActive(highlight, active),
            onEdit: () => onEdit(highlight),
            onDelete: () => onDelete(highlight),
          ),
        );
      },
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile({
    required this.highlight,
    required this.onToggleActive,
    required this.onEdit,
    required this.onDelete,
  });

  final Highlight highlight;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final active = highlight.active ?? true;
    final photo = highlight.imageUrl ?? highlight.promoPhotoUrl;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        color: colorScheme.surface,
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: SizedBox(
              width: 64,
              height: 64,
              child: photo == null
                  ? Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.image_outlined, color: colorScheme.outline),
                    )
                  : CachedNetworkImage(
                      imageUrl: photo,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Container(color: colorScheme.surfaceContainerHighest),
                      errorWidget: (context, url, error) =>
                          Container(color: colorScheme.surfaceContainerHighest),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  highlight.displayTitre ?? l10n.highlightNoPromoSelected,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall,
                ),
                if (highlight.displaySousTitre != null)
                  Text(
                    highlight.displaySousTitre!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (!active)
                      _Tag(label: l10n.highlightHiddenBadge, tone: colorScheme.outline),
                    // La diapositive existe mais ne s'affiche nulle part :
                    // sans ce signal, l'admin la croit publiée.
                    if (highlight.promoVisible == false)
                      _Tag(
                        label: l10n.highlightPromoUnavailableBadge,
                        tone: colorScheme.error,
                      ),
                    if (highlight.imageKey != null)
                      _Tag(
                        label: l10n.highlightCustomImageBadge,
                        tone: colorScheme.primary,
                      ),
                    if (highlight.promoId == null)
                      _Tag(
                        label: l10n.highlightBannerOnlyBadge,
                        tone: colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(value: active, onChanged: onToggleActive),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (action) {
                  if (action == 'edit') onEdit();
                  if (action == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'edit', child: Text(l10n.editItem)),
                  PopupMenuItem(value: 'delete', child: Text(l10n.highlightDeleteLabel)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tone),
      ),
    );
  }
}
