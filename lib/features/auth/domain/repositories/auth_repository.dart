import '../entities/auth_session.dart';

/// Abstract contract for authentication operations.
/// Compatible with Supabase, custom REST APIs, or local encrypted storage.
abstract class IAuthRepository {
  /// Stream of session state changes (null when logged out).
  Stream<AuthSession?> get sessionStream;

  /// Current session if available.
  AuthSession? get currentSession;

  /// Restores persisted session during app startup.
  Future<AuthSession?> restoreSession();

  /// Authenticates user with email and password.
  /// Passwords are processed in transit and never stored locally.
  Future<AuthSession> loginWithEmail({
    required String email,
    required String password,
  });

  /// Ends authenticated session.
  Future<void> logout();
}
