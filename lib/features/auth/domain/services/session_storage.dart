import '../entities/auth_session.dart';

/// Abstract storage interface for session persistence.
abstract class ISessionStorage {
  Future<AuthSession?> readSession();
  Future<void> writeSession(AuthSession session);
  Future<void> clearSession();
}
