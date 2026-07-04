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

const _commercantProtectedPaths = [
  '/commercant/dashboard',
  '/commercant/promos',
  '/commercant/promos/new',
  '/commercant/profile/edit',
];
const _agentProtectedPaths = ['/agent/zone', '/agent/commercant/new'];

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

      if (path == '/commercant') {
        return session?.role == AppRole.commercant ? '/commercant/dashboard' : '/commercant/login';
      }
      if (_commercantProtectedPaths.contains(path) && session?.role != AppRole.commercant) {
        return '/commercant/login';
      }

      if (path == '/agent') {
        return session?.role == AppRole.agent ? '/agent/zone' : '/agent/login';
      }
      final isAgentPromoForm = path.startsWith('/agent/promo/new/');
      if ((_agentProtectedPaths.contains(path) || isAgentPromoForm) && session?.role != AppRole.agent) {
        return '/agent/login';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const PromoListScreen()),
      GoRoute(path: '/select-commune', builder: (context, state) => const CommuneSelectionScreen()),
      GoRoute(
        path: '/promo/:id',
        builder: (context, state) => PromoDetailScreen(promoId: state.pathParameters['id']!),
      ),

      // Commerçant
      GoRoute(path: '/commercant', builder: (context, state) => const CommercantLoginScreen()),
      GoRoute(path: '/commercant/login', builder: (context, state) => const CommercantLoginScreen()),
      GoRoute(
        path: '/commercant/register',
        builder: (context, state) => const CommercantRegisterScreen(),
      ),
      GoRoute(
        path: '/commercant/dashboard',
        builder: (context, state) => const CommercantDashboardScreen(),
      ),
      GoRoute(path: '/commercant/promos', builder: (context, state) => const MyPromosScreen()),
      GoRoute(
        path: '/commercant/profile/edit',
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/commercant/promos/new',
        builder: (context, state) => PromoFormScreen(existingPromo: state.extra as Promo?),
      ),

      // Agent
      GoRoute(path: '/agent', builder: (context, state) => const AgentLoginScreen()),
      GoRoute(path: '/agent/login', builder: (context, state) => const AgentLoginScreen()),
      GoRoute(path: '/agent/zone', builder: (context, state) => const ZoneCommercesScreen()),
      GoRoute(
        path: '/agent/commercant/new',
        builder: (context, state) => const CreateCommercantScreen(),
      ),
      GoRoute(
        path: '/agent/promo/new/:commercantId',
        builder: (context, state) => AgentPromoFormScreen(
          commercantId: state.pathParameters['commercantId']!,
          defaultCategorie: state.extra as Categorie?,
        ),
      ),
    ],
  );
});
