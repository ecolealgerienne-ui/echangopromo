import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/enums/categorie.dart';
import '../domain/models/auth_session.dart';
import '../domain/models/admin_commercant_item.dart';
import '../domain/models/agent.dart';
import '../domain/models/moderation_item.dart';
import '../domain/models/promo.dart';
import '../features/admin/screens/admin_agent_detail_screen.dart';
import '../features/admin/screens/admin_audit_log_screen.dart';
import '../features/admin/screens/admin_commercant_detail_screen.dart';
import '../features/admin/screens/admin_commercants_screen.dart';
import '../features/admin/screens/admin_dashboard_screen.dart';
import '../features/admin/screens/admin_login_screen.dart';
import '../features/admin/screens/admin_promo_detail_screen.dart';
import '../features/admin/screens/admin_promos_screen.dart';
import '../features/admin/screens/agent_list_screen.dart';
import '../features/admin/screens/create_agent_screen.dart';
import '../features/admin/screens/moderation_queue_screen.dart';
import '../features/agent/screens/agent_login_screen.dart';
import '../features/agent/screens/agent_promo_form_screen.dart';
import '../features/agent/screens/create_commercant_screen.dart';
import '../features/agent/screens/commune_commerces_screen.dart';
import '../features/client/screens/commune_selection_screen.dart';
import '../features/client/screens/promo_detail_screen.dart';
import '../features/client/screens/promo_list_screen.dart';
import '../features/client/providers/commune_providers.dart';
import '../features/commercant/screens/commercant_dashboard_screen.dart';
import '../features/commercant/screens/commercant_login_screen.dart';
import '../features/commercant/screens/commercant_register_screen.dart';
import '../features/commercant/screens/edit_profile_screen.dart';
import '../features/commercant/screens/my_promos_screen.dart';
import '../features/commercant/screens/promo_form_screen.dart';
import '../features/commercant/screens/registre_resend_screen.dart';
import '../features/dev/screens/dev_profile_switcher_screen.dart';
import '../features/shared/screens/legal_document_screen.dart';
import '../features/shared/screens/notifications_screen.dart';
import '../providers/auth_provider.dart';

/// Associe le rôle requis directement à la déclaration de route plutôt qu'à
/// une liste de chemins protégés maintenue à part (audit règle #22) — un
/// écran ajouté ici sans `requiredRole` est public par construction, pas par
/// oubli d'une liste séparée à mettre à jour.
class _AppRoute {
  const _AppRoute(this.path, this.builder, {this.requiredRole});

  final String path;
  final Widget Function(BuildContext, GoRouterState) builder;
  final AppRole? requiredRole;

  /// Un segment dynamique (`:id`) n'apparaît jamais tel quel dans
  /// `state.matchedLocation` — on compare alors par préfixe jusqu'au `:`.
  bool matches(String actualPath) {
    final paramIndex = path.indexOf(':');
    if (paramIndex == -1) return actualPath == path;
    return actualPath.startsWith(path.substring(0, paramIndex));
  }
}

Widget _unusedBuilder(BuildContext context, GoRouterState state) => const SizedBox.shrink();

final _appRoutes = <_AppRoute>[
  _AppRoute('/', (context, state) => const PromoListScreen()),
  _AppRoute('/select-commune', (context, state) => const CommuneSelectionScreen()),
  // Publics, sans rôle requis — accessibles depuis l'inscription commerçant
  // et un lien général (plan de correction, Phase 4).
  _AppRoute('/legal/cgu', (context, state) => const LegalDocumentScreen.cgu()),
  _AppRoute('/legal/confidentialite', (context, state) => const LegalDocumentScreen.privacy()),
  // TEMPORAIRE — écran de test pour basculer entre profils, à supprimer
  // avant l'ouverture publique (voir commentaire en tête du fichier).
  _AppRoute('/dev/profiles', (context, state) => const DevProfileSwitcherScreen()),
  _AppRoute(
    '/promo/:id',
    (context, state) => PromoDetailScreen(promoId: state.pathParameters['id']!),
  ),
  // Chemin des liens App Links/Universal Links (promo.echango.com/p/:id,
  // voir AppLinksController côté backend) — volontairement différent de
  // /promo/:id (route interne classique, ex. depuis PromoListScreen) pour
  // ne jamais entrer en collision avec l'API JSON `GET /promo/:id` si les
  // deux finissent sur le même sous-domaine. Même écran, même id.
  _AppRoute(
    '/p/:id',
    (context, state) => PromoDetailScreen(promoId: state.pathParameters['id']!),
  ),

  // Commerçant
  _AppRoute('/commercant', (context, state) => const CommercantLoginScreen()),
  _AppRoute('/commercant/login', (context, state) => const CommercantLoginScreen()),
  _AppRoute('/commercant/register', (context, state) => const CommercantRegisterScreen()),
  _AppRoute(
    '/commercant/dashboard',
    (context, state) => const CommercantDashboardScreen(),
    requiredRole: AppRole.commercant,
  ),
  _AppRoute(
    '/commercant/promos',
    (context, state) => const MyPromosScreen(),
    requiredRole: AppRole.commercant,
  ),
  _AppRoute(
    '/commercant/profile/edit',
    (context, state) => const EditProfileScreen(),
    requiredRole: AppRole.commercant,
  ),
  _AppRoute(
    '/commercant/promos/new',
    (context, state) => PromoFormScreen(existingPromo: state.extra as Promo?),
    requiredRole: AppRole.commercant,
  ),
  _AppRoute(
    '/commercant/notifications',
    (context, state) => const NotificationsScreen(),
    requiredRole: AppRole.commercant,
  ),
  _AppRoute(
    '/commercant/registre/resend',
    (context, state) => const RegistreResendScreen(),
    requiredRole: AppRole.commercant,
  ),

  // Agent
  _AppRoute('/agent', (context, state) => const AgentLoginScreen()),
  _AppRoute('/agent/login', (context, state) => const AgentLoginScreen()),
  _AppRoute(
    '/agent/communes',
    (context, state) => const CommuneCommercesScreen(),
    requiredRole: AppRole.agent,
  ),
  _AppRoute(
    '/agent/commercant/new',
    (context, state) => const CreateCommercantScreen(),
    requiredRole: AppRole.agent,
  ),
  _AppRoute(
    '/agent/promo/new/:commercantId',
    (context, state) => AgentPromoFormScreen(
      commercantId: state.pathParameters['commercantId']!,
      defaultCategorie: state.extra as Categorie?,
    ),
    requiredRole: AppRole.agent,
  ),
  // Agent = modérateur (plan de correction, Phase 2) : mêmes écrans que
  // l'admin, le backend scope automatiquement aux communes de l'agent
  // (voir AdminController.scopedCommuneIds) — pas de duplication d'écran.
  _AppRoute(
    '/agent/moderation',
    (context, state) => const ModerationQueueScreen(),
    requiredRole: AppRole.agent,
  ),
  _AppRoute(
    '/agent/promos',
    (context, state) => const AdminPromosScreen(),
    requiredRole: AppRole.agent,
  ),
  // Fiche promo modération — mêmes deux chemins par rôle que
  // moderation/promos ci-dessus (widget partagé, backend scope par JWT).
  _AppRoute(
    '/agent/promo-detail',
    (context, state) => AdminPromoDetailScreen(item: state.extra as ModerationItem),
    requiredRole: AppRole.agent,
  ),

  // Admin (specs §3.4) — compte unique en V0, pas d'auto-inscription, pas
  // d'entrée dans le menu "espace pro" public (accès direct par URL
  // uniquement, décision produit : ne pas rendre cet écran découvrable
  // depuis l'app grand public).
  _AppRoute('/admin', (context, state) => const AdminLoginScreen()),
  _AppRoute('/admin/login', (context, state) => const AdminLoginScreen()),
  _AppRoute(
    '/admin/dashboard',
    (context, state) => const AdminDashboardScreen(),
    requiredRole: AppRole.admin,
  ),
  _AppRoute(
    '/admin/moderation',
    (context, state) => const ModerationQueueScreen(),
    requiredRole: AppRole.admin,
  ),
  _AppRoute(
    '/admin/promos',
    (context, state) => const AdminPromosScreen(),
    requiredRole: AppRole.admin,
  ),
  _AppRoute(
    '/admin/promo-detail',
    (context, state) => AdminPromoDetailScreen(item: state.extra as ModerationItem),
    requiredRole: AppRole.admin,
  ),
  _AppRoute(
    '/admin/commercants',
    (context, state) => const AdminCommercantsScreen(),
    requiredRole: AppRole.admin,
  ),
  _AppRoute(
    '/admin/commercants/detail',
    (context, state) => AdminCommercantDetailScreen(item: state.extra as AdminCommercantItem),
    requiredRole: AppRole.admin,
  ),
  _AppRoute(
    '/admin/audit-log',
    (context, state) => const AdminAuditLogScreen(),
    requiredRole: AppRole.admin,
  ),
  _AppRoute(
    '/admin/agents',
    (context, state) => const AgentListScreen(),
    requiredRole: AppRole.admin,
  ),
  _AppRoute(
    '/admin/agents/detail',
    (context, state) => AdminAgentDetailScreen(agent: state.extra as Agent),
    requiredRole: AppRole.admin,
  ),
  _AppRoute(
    '/admin/agents/new',
    (context, state) => const CreateAgentScreen(),
    requiredRole: AppRole.admin,
  ),
];

String _loginPathFor(AppRole role) {
  switch (role) {
    case AppRole.commercant:
      return '/commercant/login';
    case AppRole.agent:
      return '/agent/login';
    case AppRole.admin:
      return '/admin/login';
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: ref.watch(routerRefreshProvider),
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      if (authState.isLoading) return null;
      final session = authState.value;
      final path = state.matchedLocation;

      if (path == '/' && ref.read(selectedCommunesProvider).isEmpty) {
        return '/select-commune';
      }

      // Points d'entrée par rôle : redirigent vers le dashboard si déjà
      // connecté avec ce rôle, sinon vers l'écran de connexion — distinct
      // d'une protection de route (pas de `requiredRole` à vérifier ici).
      if (path == '/commercant') {
        return session?.role == AppRole.commercant ? '/commercant/dashboard' : '/commercant/login';
      }
      if (path == '/agent') {
        return session?.role == AppRole.agent ? '/agent/communes' : '/agent/login';
      }
      if (path == '/admin') {
        return session?.role == AppRole.admin ? '/admin/dashboard' : '/admin/login';
      }

      final requiredRole = _appRoutes
          .firstWhere(
            (route) => route.matches(path),
            orElse: () => const _AppRoute('', _unusedBuilder),
          )
          .requiredRole;
      if (requiredRole != null && session?.role != requiredRole) {
        return _loginPathFor(requiredRole);
      }

      return null;
    },
    routes: [
      for (final route in _appRoutes) GoRoute(path: route.path, builder: route.builder),
    ],
  );
});
