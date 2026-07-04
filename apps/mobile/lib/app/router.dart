import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/enums/categorie.dart';
import '../domain/models/auth_session.dart';
import '../domain/models/promo.dart';
import '../features/agent/screens/agent_login_screen.dart';
import '../features/agent/screens/agent_promo_form_screen.dart';
import '../features/agent/screens/create_commercant_screen.dart';
import '../features/agent/screens/zone_commerces_screen.dart';
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
  _AppRoute(
    '/promo/:id',
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

  // Agent
  _AppRoute('/agent', (context, state) => const AgentLoginScreen()),
  _AppRoute('/agent/login', (context, state) => const AgentLoginScreen()),
  _AppRoute(
    '/agent/zone',
    (context, state) => const ZoneCommercesScreen(),
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
];

String _loginPathFor(AppRole role) =>
    role == AppRole.commercant ? '/commercant/login' : '/agent/login';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: ref.watch(routerRefreshProvider),
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      if (authState.isLoading) return null;
      final session = authState.value;
      final path = state.matchedLocation;

      if (path == '/' && ref.read(selectedCommuneProvider) == null) {
        return '/select-commune';
      }

      // Points d'entrée par rôle : redirigent vers le dashboard si déjà
      // connecté avec ce rôle, sinon vers l'écran de connexion — distinct
      // d'une protection de route (pas de `requiredRole` à vérifier ici).
      if (path == '/commercant') {
        return session?.role == AppRole.commercant ? '/commercant/dashboard' : '/commercant/login';
      }
      if (path == '/agent') {
        return session?.role == AppRole.agent ? '/agent/zone' : '/agent/login';
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
