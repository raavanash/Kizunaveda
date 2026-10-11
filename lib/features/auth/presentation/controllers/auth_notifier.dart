import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/auth_exception.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
}

/// Manages authentication state and role-based session lifecycle.
class AuthNotifier extends ChangeNotifier {
  final IAuthRepository authRepository;
  StreamSubscription<AuthSession?>? _subscription;

  AuthStatus _status = AuthStatus.initial;
  AuthSession? _session;
  String? _errorMessage;

  AuthNotifier({required this.authRepository}) {
    _subscription = authRepository.sessionStream.listen(_onSessionChanged);
    _init();
  }

  AuthStatus get status => _status;
  AuthSession? get session => _session;
  AuthUser? get currentUser => _session?.user;
  UserRole? get currentRole => _session?.user.role;
  String? get errorMessage => _errorMessage;

  bool get isAuthenticated => _status == AuthStatus.authenticated && _session != null;

  Future<void> _init() async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      _session = await authRepository.restoreSession();
      if (_session != null && !_session!.isExpired) {
        _status = AuthStatus.authenticated;
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  void _onSessionChanged(AuthSession? newSession) {
    _session = newSession;
    if (newSession != null && !newSession.isExpired) {
      _status = AuthStatus.authenticated;
    } else {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login({required String email, required String password}) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _session = await authRepository.loginWithEmail(
        email: email,
        password: password,
      );
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'An unexpected error occurred. Please try again.';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _status = AuthStatus.loading;
    notifyListeners();
    await authRepository.logout();
    _session = null;
    _errorMessage = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
