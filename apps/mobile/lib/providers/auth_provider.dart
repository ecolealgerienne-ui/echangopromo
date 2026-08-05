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
