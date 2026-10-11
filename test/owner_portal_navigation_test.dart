import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/app/routes/app_routes.dart';
import 'package:kizuna_veda/core/constants/app_constants.dart';
import 'package:kizuna_veda/features/auth/data/repositories/unconnected_auth_repository.dart';
import 'package:kizuna_veda/features/auth/data/services/local_session_storage.dart';
import 'package:kizuna_veda/features/auth/domain/entities/auth_session.dart';
import 'package:kizuna_veda/features/auth/domain/entities/auth_user.dart';
import 'package:kizuna_veda/features/auth/presentation/controllers/auth_notifier.dart';
import 'package:kizuna_veda/features/jaipur/presentation/screens/ebill_history_screen.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/jaipur_stock_screen.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/neemrana_stock_screen.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/owner_home_screen.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/user_management_screen.dart';

void main() {
  group('Owner Portal Card Navigation Tests', () {
    late LocalSessionStorage sessionStorage;
    late UnconnectedAuthRepository repository;
    late AuthNotifier authNotifier;

    setUp(() {
      sessionStorage = LocalSessionStorage();
      repository = UnconnectedAuthRepository(sessionStorage: sessionStorage);
      const user = AuthUser(
        id: 'owner-test-1',
        email: 'owner@kizunaveda.com',
        fullName: 'Test Owner',
        role: UserRole.owner,
      );
      repository.setSessionForTesting(const AuthSession(user: user, accessToken: 'test-token'));
      authNotifier = AuthNotifier(authRepository: repository);
    });

    tearDown(() {
      authNotifier.dispose();
      repository.dispose();
    });

    Widget buildTestApp() {
      return MaterialApp(
        routes: AppRoutes.routes,
        home: OwnerHomeScreen(
          authNotifier: authNotifier,
          autoShowOnboarding: false,
        ),
      );
    }

    testWidgets('Tapping Neemrana Store card navigates to NeemranaStockScreen and pops back', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final cardFinder = find.text('Neemrana Store & Billing');
      expect(cardFinder, findsOneWidget);
      await tester.ensureVisible(cardFinder);

      await tester.tap(cardFinder);
      await tester.pumpAndSettle();

      expect(find.byType(NeemranaStockScreen), findsOneWidget);

      final backButton = find.byType(BackButton);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(find.byType(OwnerHomeScreen), findsOneWidget);
    });

    testWidgets('Tapping Jaipur Store card navigates to JaipurStockScreen and pops back', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final cardFinder = find.text('Jaipur Store & Billing');
      expect(cardFinder, findsOneWidget);
      await tester.ensureVisible(cardFinder);

      await tester.tap(cardFinder);
      await tester.pumpAndSettle();

      expect(find.byType(JaipurStockScreen), findsOneWidget);
      expect(find.text('Independent retail store inventory, sales & cash/UPI collections.'), findsOneWidget);

      final backButton = find.byType(BackButton);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(find.byType(OwnerHomeScreen), findsOneWidget);
    });

    testWidgets('Tapping Sales & E-Bill History card navigates to EBillHistoryScreen and pops back', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final cardFinder = find.text('Sales & E-Bill History');
      expect(cardFinder, findsOneWidget);
      await tester.ensureVisible(cardFinder);

      await tester.tap(cardFinder);
      await tester.pumpAndSettle();

      expect(find.byType(EBillHistoryScreen), findsOneWidget);

      final backButton = find.byType(BackButton);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(find.byType(OwnerHomeScreen), findsOneWidget);
    });

    testWidgets('Tapping User Management card navigates to UserManagementScreen and pops back', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final cardFinder = find.text('User Management & Security');
      expect(cardFinder, findsOneWidget);
      await tester.ensureVisible(cardFinder);

      await tester.tap(cardFinder);
      await tester.pumpAndSettle();

      expect(find.byType(UserManagementScreen), findsOneWidget);
      expect(find.text('Manage authorized company users and roles.'), findsOneWidget);

      final backButton = find.byType(BackButton);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(find.byType(OwnerHomeScreen), findsOneWidget);
    });
  });
}
