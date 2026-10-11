import 'dart:async';
import '../../../../core/error/auth_exception.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/services/session_storage.dart';

/// Authentication repository prepared for Supabase backend integration.
/// Contains ZERO hardcoded passwords, ZERO fake auth rules, and ZERO mock user lists.
class UnconnectedAuthRepository implements IAuthRepository {
  final ISessionStorage sessionStorage;
  final _sessionController = StreamController<AuthSession?>.broadcast();
  AuthSession? _currentSession;

  UnconnectedAuthRepository({required this.sessionStorage});

  @override
  Stream<AuthSession?> get sessionStream => _sessionController.stream;

  @override
  AuthSession? get currentSession => _currentSession;

  @override
  Future<AuthSession?> restoreSession() async {
    final session = await sessionStorage.readSession();
    if (session != null && !session.isExpired) {
      _currentSession = session;
      _sessionController.add(_currentSession);
      return _currentSession;
    }
    await logout();
    return null;
  }

  @override
  Future<AuthSession> loginWithEmail({
    required String email,
    required String password,
  }) async {
    // Validate input format on client side without storing password
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      throw const AuthException('Please enter a valid email address.');
    }
    if (password.trim().isEmpty) {
      throw const AuthException('Please enter your password.');
    }

    // Backend credentials have not been configured yet in Phase 2.
    // Strictly refrains from hardcoded passwords or fake authentication.
    throw const AuthException(
      'Backend authentication service is not connected yet. '
      'Real authentication will be wired when Supabase backend credentials are supplied.',
      code: 'BACKEND_NOT_CONFIGURED',
    );
  }

  @override
  Future<void> logout() async {
    await sessionStorage.clearSession();
    _currentSession = null;
    _sessionController.add(null);
  }

  /// Helper method for session injection testing or manual session setup (e.g. after backend auth callback).
  void setSessionForTesting(AuthSession? session) {
    _currentSession = session;
    if (session != null) {
      sessionStorage.writeSession(session);
    } else {
      sessionStorage.clearSession();
    }
    _sessionController.add(_currentSession);
  }

  void dispose() {
    _sessionController.close();
  }
}
