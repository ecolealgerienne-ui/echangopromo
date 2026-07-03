import 'package:go_router/go_router.dart';
import '../features/agent/screens/agent_login_screen.dart';
import '../features/client/screens/promo_list_screen.dart';
import '../features/commercant/screens/commercant_login_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const PromoListScreen(),
    ),
    GoRoute(
      path: '/commercant',
      builder: (context, state) => const CommercantLoginScreen(),
    ),
    GoRoute(
      path: '/agent',
      builder: (context, state) => const AgentLoginScreen(),
    ),
  ],
);
