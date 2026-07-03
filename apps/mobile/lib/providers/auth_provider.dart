import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/local/auth_session_store.dart';
import '../domain/models/auth_session.dart';
import 'core_providers.dart';

class AuthController extends StateNotifier<AsyncValue<AuthSession?>> {
  AuthController(this._store) : super(const AsyncValue.loading()) {
    _load();
  }

  final AuthSessionStore _store;

  Future<void> _load() async {
    state = AsyncValue.data(await _store.read());
  }

  String? get currentToken => state.value?.token;

  Future<void> login(AuthSession session) async {
    await _store.save(session);
    state = AsyncValue.data(session);
  }

  /// Le login renvoie seulement un JWT (le `sub` n'est pas exposé côté
  /// client) : on active d'abord une session avec un id vide pour que la
  /// requête `fetchId` soit authentifiée, puis on complète l'id réel.
  Future<void> loginThenResolveId({
    required AppRole role,
    required String token,
    required Future<String> Function() fetchId,
  }) async {
    await login(AuthSession(role: role, token: token, userId: ''));
    final userId = await fetchId();
    await login(AuthSession(role: role, token: token, userId: userId));
  }

  Future<void> logout() async {
    await _store.clear();
    state = const AsyncValue.data(null);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<AuthSession?>>(
  (ref) => AuthController(ref.watch(authSessionStoreProvider)),
);

/// Pont entre l'état Riverpod et `GoRouter.refreshListenable`, qui attend un
/// [Listenable] classique et ne peut pas observer un provider directement.
class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (_, __) => notifyListeners());
  }
}

final routerRefreshProvider = Provider((ref) => RouterRefreshNotifier(ref));
