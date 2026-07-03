import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../domain/models/auth_session.dart';

/// Session commerçant OU agent (jamais les deux à la fois — l'app est
/// utilisée par une seule personne à la fois dans un seul rôle). Stockée
/// en stockage sécurisé, jamais en clair (contient un JWT).
class AuthSessionStore {
  AuthSessionStore(this._storage);

  static const _roleKey = 'auth_role';
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'auth_user_id';

  final FlutterSecureStorage _storage;

  Future<AuthSession?> read() async {
    final values = await Future.wait([
      _storage.read(key: _roleKey),
      _storage.read(key: _tokenKey),
      _storage.read(key: _userIdKey),
    ]);
    return AuthSession.fromStorageMap({
      'role': values[0],
      'token': values[1],
      'userId': values[2],
    });
  }

  Future<void> save(AuthSession session) async {
    final map = session.toStorageMap();
    await Future.wait([
      _storage.write(key: _roleKey, value: map['role']),
      _storage.write(key: _tokenKey, value: map['token']),
      _storage.write(key: _userIdKey, value: map['userId']),
    ]);
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _roleKey),
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _userIdKey),
    ]);
  }
}
