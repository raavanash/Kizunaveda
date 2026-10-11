import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/auth_exception.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/services/session_storage.dart';

/// Authentication repository connected to Supabase Auth.
class SupabaseAuthRepository implements IAuthRepository {
  final supabase.SupabaseClient? _customClient;
  final ISessionStorage sessionStorage;

  final _sessionController = StreamController<AuthSession?>.broadcast();
  AuthSession? _currentSession;
  StreamSubscription<supabase.AuthState>? _authSubscription;

  SupabaseAuthRepository({
    supabase.SupabaseClient? supabaseClient,
    required this.sessionStorage,
  }) : _customClient = supabaseClient {
    final client = _effectiveClient;
    if (client != null) {
      _authSubscription = client.auth.onAuthStateChange.listen((data) {
        final session = data.session;
        if (session != null) {
          _currentSession = _mapSupabaseSessionToAuthSession(session);
          sessionStorage.writeSession(_currentSession!);
        } else {
          _currentSession = null;
          sessionStorage.clearSession();
        }
        _sessionController.add(_currentSession);
      });
    }
  }

  supabase.SupabaseClient? get _effectiveClient {
    if (_customClient != null) return _customClient;
    try {
      return supabase.Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<AuthSession?> get sessionStream => _sessionController.stream;

  @override
  AuthSession? get currentSession => _currentSession;

  @override
  Future<AuthSession?> restoreSession() async {
    final client = _effectiveClient;
    if (client != null) {
      final activeSession = client.auth.currentSession;
      debugPrint(
        '[AUTH_DIAGNOSTIC] Active Supabase client session check: sessionExists=${activeSession != null}, userId=${activeSession?.user.id}',
      );
      if (activeSession != null && !activeSession.isExpired) {
        _currentSession = _mapSupabaseSessionToAuthSession(activeSession);
        await sessionStorage.writeSession(_currentSession!);
        _sessionController.add(_currentSession);
        return _currentSession;
      }
    }

    final localSession = await sessionStorage.readSession();
    if (localSession != null && !localSession.isExpired) {
      if (client != null &&
          localSession.refreshToken != null &&
          localSession.refreshToken!.isNotEmpty) {
        try {
          final response =
              await client.auth.setSession(localSession.refreshToken!);
          final restoredSession = response.session;
          if (restoredSession != null && !restoredSession.isExpired) {
            _currentSession =
                _mapSupabaseSessionToAuthSession(restoredSession);
            await sessionStorage.writeSession(_currentSession!);
            _sessionController.add(_currentSession);
            debugPrint(
              '[AUTH_DIAGNOSTIC] Restored Supabase client session from refresh token: userId=${restoredSession.user.id}',
            );
            return _currentSession;
          }
        } catch (e) {
          debugPrint(
            '[AUTH_DIAGNOSTIC] Failed to restore Supabase client session from refresh token: $e',
          );
        }
      }
    }

    await logout();
    return null;
  }

  @override
  Future<AuthSession> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      throw const AuthException('Please enter a valid email address.');
    }
    if (password.trim().isEmpty) {
      throw const AuthException('Please enter your password.');
    }

    final client = _effectiveClient;
    if (client == null) {
      throw const AuthException(
        'Supabase client is not initialized. Please configure app environment.',
        code: 'SUPABASE_NOT_INITIALIZED',
      );
    }

    try {
      final response = await client.auth.signInWithPassword(
        email: trimmedEmail,
        password: password,
      );

      final session = response.session;
      final user = response.user;

      debugPrint(
        '[AUTH_DIAGNOSTIC] Post-login auth check: sessionExists=${session != null}, userId=${user?.id}',
      );

      if (session == null || user == null) {
        throw const AuthException(
          'Authentication failed. Invalid email or password.',
          code: 'INVALID_CREDENTIALS',
        );
      }


      final authSession = _mapSupabaseSessionToAuthSession(session);
      _currentSession = authSession;
      await sessionStorage.writeSession(authSession);
      _sessionController.add(_currentSession);
      return authSession;
    } on supabase.AuthException catch (e) {
      throw AuthException(
        _formatSupabaseAuthError(e),
        code: e.statusCode ?? 'AUTH_ERROR',
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      throw const AuthException(
        'Connection error. Please check your network connection and try again.',
        code: 'NETWORK_ERROR',
      );
    }
  }

  @override
  Future<void> logout() async {
    final client = _effectiveClient;
    if (client != null) {
      try {
        await client.auth.signOut();
      } catch (_) {
        // Ignore network errors during local logout cleanup
      }
    }
    await sessionStorage.clearSession();
    _currentSession = null;
    _sessionController.add(null);
  }

  AuthUser _mapSupabaseUserToAuthUser(supabase.User user) {
    final meta = user.userMetadata ?? {};
    final appMeta = user.appMetadata;
    final roleStr = appMeta['role']?.toString().toLowerCase();

    final role = UserRole.values.firstWhere(
      (r) => r.name == roleStr,
      orElse: () => UserRole.jaipur,
    );

    return AuthUser(
      id: user.id,
      email: user.email ?? '',
      fullName: (meta['full_name'] ?? meta['fullName']) as String?,
      role: role,
      facilityLocation:
          (meta['facility_location'] ?? meta['facilityLocation']) as String?,
    );
  }

  AuthSession _mapSupabaseSessionToAuthSession(supabase.Session session) {
    return AuthSession(
      user: _mapSupabaseUserToAuthUser(session.user),
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      expiresAt: session.expiresAt != null
          ? DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)
          : null,
    );
  }

  String _formatSupabaseAuthError(supabase.AuthException error) {
    final msg = error.message.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return 'Invalid email or password. Please check your credentials.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Email address has not been confirmed by system administrator.';
    }
    if (msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('connection')) {
      return 'Network connection error. Please check your internet connection.';
    }
    return error.message;
  }

  void dispose() {
    _authSubscription?.cancel();
    _sessionController.close();
  }
}
