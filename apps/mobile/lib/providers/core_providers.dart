import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/api/admin_api.dart';
import '../data/api/agent_api.dart';
import '../data/api/api_client.dart';
import '../data/api/commercant_api.dart';
import '../data/api/highlight_api.dart';
import '../data/api/promo_api.dart';
import '../data/api/report_api.dart';
import '../data/api/storage_api.dart';
import '../data/api/notification_api.dart';
import '../data/local/auth_session_store.dart';
import '../data/local/device_id_store.dart';
import '../data/local/favorites_store.dart';
import '../data/local/point_proposal_store.dart';
import '../data/local/etag_cache_store.dart';
import '../data/local/onboarding_store.dart';
import 'auth_provider.dart';

/// Surchargé dans `main()` une fois `SharedPreferences.getInstance()` résolu.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
      'sharedPreferencesProvider doit être surchargé dans main()'),
);

final secureStorageProvider =
    Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

final deviceIdStoreProvider =
    Provider((ref) => DeviceIdStore(ref.watch(sharedPreferencesProvider)));

final deviceIdProvider =
    Provider<String>((ref) => ref.watch(deviceIdStoreProvider).getOrCreate());

final favoritesStoreProvider =
    Provider((ref) => FavoritesStore(ref.watch(sharedPreferencesProvider)));

/// Distinct de la demande de localisation : l'activer et
/// enregistrer une ville sont deux décisions différentes, écartables
/// séparément (voir `PointProposalStore`).
final pointProposalStoreProvider =
    Provider((ref) => PointProposalStore(ref.watch(sharedPreferencesProvider)));

/// Cache de revalidation HTTP — voir `EtagCacheInterceptor` pour ce qu'il
/// conserve et, surtout, ce qu'il refuse de conserver.
final etagCacheStoreProvider =
    Provider((ref) => EtagCacheStore(ref.watch(sharedPreferencesProvider)));

final onboardingStoreProvider =
    Provider((ref) => OnboardingStore(ref.watch(sharedPreferencesProvider)));

final authSessionStoreProvider =
    Provider((ref) => AuthSessionStore(ref.watch(secureStorageProvider)));

final apiClientProvider = Provider<ApiClient>((ref) {
  final authController = ref.watch(authControllerProvider.notifier);
  return ApiClient(
    getDeviceId: () => ref.read(deviceIdProvider),
    getToken: () => authController.currentToken,
    // Déconnecte automatiquement dès que le backend rejette le token
    // (révoqué, invalide/expiré) — sinon router.dart ne redirige jamais
    // vers le login puisque authControllerProvider ne change jamais tout
    // seul (audit V1 §8).
    onAuthInvalid: () => authController.logout(),
    // Revalidation conditionnelle des routes publiques : le backend posait un
    // `ETag` que personne ne lisait (règle 31, mesuré le 2026-08-13).
    etagCache: ref.watch(etagCacheStoreProvider),
  );
});

final promoApiProvider =
    Provider((ref) => PromoApi(ref.watch(apiClientProvider).dio));
final commercantApiProvider =
    Provider((ref) => CommercantApi(ref.watch(apiClientProvider).dio));
final agentApiProvider =
    Provider((ref) => AgentApi(ref.watch(apiClientProvider).dio));
final reportApiProvider =
    Provider((ref) => ReportApi(ref.watch(apiClientProvider).dio));
final storageApiProvider =
    Provider((ref) => StorageApi(ref.watch(apiClientProvider).dio));
final adminApiProvider =
    Provider((ref) => AdminApi(ref.watch(apiClientProvider).dio));
final highlightApiProvider =
    Provider((ref) => HighlightApi(ref.watch(apiClientProvider).dio));
final notificationApiProvider =
    Provider((ref) => NotificationApi(ref.watch(apiClientProvider).dio));
