import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/core/constants/app_constants.dart';
import 'package:kizuna_veda/core/error/auth_exception.dart';
import 'package:kizuna_veda/features/auth/data/repositories/supabase_auth_repository.dart';
import 'package:kizuna_veda/features/auth/data/repositories/unconnected_auth_repository.dart';
import 'package:kizuna_veda/features/auth/data/services/local_session_storage.dart';
import 'package:kizuna_veda/features/auth/domain/entities/auth_session.dart';
import 'package:kizuna_veda/features/auth/domain/entities/auth_user.dart';
import 'package:kizuna_veda/features/auth/presentation/controllers/auth_notifier.dart';
import 'package:kizuna_veda/features/auth/presentation/screens/auth_gate.dart';
import 'package:kizuna_veda/features/jaipur/presentation/screens/jaipur_home_screen.dart';
import 'package:kizuna_veda/features/neemrana/presentation/screens/neemrana_home_screen.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/owner_home_screen.dart';

void main() {
  group('Auth Domain Entities', () {
    test('AuthUser serialization and deserialization', () {
      const user = AuthUser(
        id: 'usr-101',
        email: 'owner@kizunaveda.com',
        fullName: 'Kizuna Owner',
        role: UserRole.owner,
        facilityLocation: 'HQ',
      );

      final json = user.toJson();
      expect(json['id'], 'usr-101');
      expect(json['role'], 'owner');

      final deserialized = AuthUser.fromJson(json);
      expect(deserialized.id, user.id);
      expect(deserialized.role, UserRole.owner);
    });

    test('AuthSession expiration check', () {
      const user = AuthUser(
        id: 'usr-102',
        email: 'neemrana@kizunaveda.com',
        role: UserRole.neemrana,
      );

      final session = AuthSession(
        user: user,
        accessToken: 'token-abc',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      expect(session.isExpired, isTrue);
    });
  });

  group('SupabaseAuthRepository', () {
    late LocalSessionStorage sessionStorage;
    late SupabaseAuthRepository repository;

    setUp(() {
      sessionStorage = LocalSessionStorage();
      repository = SupabaseAuthRepository(sessionStorage: sessionStorage);
    });

    tearDown(() {
      repository.dispose();
    });

    test('loginWithEmail validates invalid email format', () async {
      expect(
        () => repository.loginWithEmail(
          email: 'invalid-email',
          password: 'password123',
        ),
        throwsA(isA<AuthException>().having(
          (e) => e.message,
          'message',
          'Please enter a valid email address.',
        )),
      );
    });

    test('loginWithEmail validates empty password', () async {
      expect(
        () => repository.loginWithEmail(
          email: 'user@kizunaveda.com',
          password: '   ',
        ),
        throwsA(isA<AuthException>().having(
          (e) => e.message,
          'message',
          'Please enter your password.',
        )),
      );
    });

    test('logout clears local session storage', () async {
      await repository.logout();
      expect(repository.currentSession, isNull);
    });
  });

  group('UnconnectedAuthRepository', () {
    late LocalSessionStorage sessionStorage;
    late UnconnectedAuthRepository repository;

    setUp(() {
      sessionStorage = LocalSessionStorage();
      repository = UnconnectedAuthRepository(sessionStorage: sessionStorage);
    });

    tearDown(() {
      repository.dispose();
    });

    test('loginWithEmail fails safely without hardcoded credentials', () async {
      expect(
        () => repository.loginWithEmail(
          email: 'admin@kizunaveda.com',
          password: 'secretPassword123',
        ),
        throwsA(isA<AuthException>().having(
          (e) => e.code,
          'code',
          'BACKEND_NOT_CONFIGURED',
        )),
      );
    });

    test('logout clears session correctly', () async {
      const user = AuthUser(
        id: 'usr-103',
        email: 'jaipur@kizunaveda.com',
        role: UserRole.jaipur,
      );
      const session = AuthSession(user: user, accessToken: 'dummy');

      repository.setSessionForTesting(session);
      expect(repository.currentSession, isNotNull);

      await repository.logout();
      expect(repository.currentSession, isNull);
    });
  });

  group('AuthGate Role Navigation', () {
    late LocalSessionStorage sessionStorage;
    late UnconnectedAuthRepository repository;
    late AuthNotifier authNotifier;

    setUp(() {
      sessionStorage = LocalSessionStorage();
      repository = UnconnectedAuthRepository(sessionStorage: sessionStorage);
      authNotifier = AuthNotifier(authRepository: repository);
    });

    tearDown(() {
      authNotifier.dispose();
      repository.dispose();
    });

    testWidgets('Routes unauthenticated user to LoginScreen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(authNotifier: authNotifier),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign In to Enterprise Portal'), findsOneWidget);
    });

    testWidgets('Routes OWNER role to OwnerHomeScreen', (tester) async {
      const user = AuthUser(
        id: 'u-owner',
        email: 'owner@kizunaveda.com',
        role: UserRole.owner,
      );
      repository.setSessionForTesting(const AuthSession(user: user, accessToken: 't'));

      final testNotifier = AuthNotifier(authRepository: repository);
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(authNotifier: testNotifier),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(OwnerHomeScreen), findsOneWidget);
      expect(find.text('Kizuna Veda • Owner Portal'), findsOneWidget);
      testNotifier.dispose();
    });

    testWidgets('Routes NEEMRANA role to NeemranaHomeScreen', (tester) async {
      const user = AuthUser(
        id: 'u-neemrana',
        email: 'neemrana@kizunaveda.com',
        role: UserRole.neemrana,
      );
      repository.setSessionForTesting(const AuthSession(user: user, accessToken: 't'));

      final testNotifier = AuthNotifier(authRepository: repository);
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(authNotifier: testNotifier),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(NeemranaHomeScreen), findsOneWidget);
      expect(find.text('Neemrana Store & Billing'), findsOneWidget);
      testNotifier.dispose();
    });

    testWidgets('Routes JAIPUR role to JaipurHomeScreen', (tester) async {
      const user = AuthUser(
        id: 'u-jaipur',
        email: 'jaipur@kizunaveda.com',
        role: UserRole.jaipur,
      );
      repository.setSessionForTesting(const AuthSession(user: user, accessToken: 't'));

      final testNotifier = AuthNotifier(authRepository: repository);
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(authNotifier: testNotifier),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(JaipurHomeScreen), findsOneWidget);
      expect(find.text('Jaipur Outlet & Billing'), findsOneWidget);
      testNotifier.dispose();
    });

    testWidgets('Selected context or user_metadata cannot override authenticated app_metadata.role', (tester) async {
      // User has app_metadata.role = jaipur but user_metadata trying to spoof owner
      const user = AuthUser(
        id: 'u-spoof',
        email: 'jaipur@kizunaveda.com',
        role: UserRole.jaipur,
      );
      repository.setSessionForTesting(const AuthSession(user: user, accessToken: 't'));

      final testNotifier = AuthNotifier(authRepository: repository);
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(authNotifier: testNotifier),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // System MUST route to JaipurHomeScreen based on authoritative app_metadata.role
      expect(find.byType(JaipurHomeScreen), findsOneWidget);
      expect(find.byType(OwnerHomeScreen), findsNothing);
      testNotifier.dispose();
    });
  });
}
