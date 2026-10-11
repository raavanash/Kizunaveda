import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/core/constants/app_constants.dart';
import 'package:kizuna_veda/features/auth/data/repositories/unconnected_auth_repository.dart';
import 'package:kizuna_veda/features/auth/data/services/local_session_storage.dart';
import 'package:kizuna_veda/features/auth/domain/entities/auth_session.dart';
import 'package:kizuna_veda/features/auth/domain/entities/auth_user.dart';
import 'package:kizuna_veda/features/auth/presentation/controllers/auth_notifier.dart';
import 'package:kizuna_veda/features/dashboard/presentation/screens/vyapar_dashboard_view.dart';
import 'package:kizuna_veda/features/more/presentation/screens/more_settings_view.dart';
import 'package:kizuna_veda/features/navigation/presentation/screens/main_navigation_shell.dart';
import 'package:kizuna_veda/features/onboarding/data/services/onboarding_storage.dart';
import 'package:kizuna_veda/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:kizuna_veda/features/onboarding/presentation/screens/help_and_setup_guide_screen.dart';
import 'package:kizuna_veda/features/onboarding/presentation/screens/role_onboarding_dialog.dart';

void main() {
  setUp(() {
    OnboardingStorage.instance.clearMemory();
  });

  group('1. Role-Tailored Onboarding Domain Logic', () {
    test('Owner steps contain executive analytics and two-store inventory governance', () {
      final steps = OnboardingStep.getStepsForRole(UserRole.owner);
      expect(steps.length, 4);

      expect(steps[0].title, contains('Owner Portal'));
      expect(steps[0].shortcutType, OnboardingShortcutType.dashboard);

      expect(steps[1].title, contains('Business Metrics'));
      expect(steps[1].bulletPoints.any((b) => b.contains('Cash vs. UPI')), isTrue);

      expect(steps[2].title, contains('Two Independent Store Inventories'));
      expect(
        steps[2].bulletPoints.any((b) => b.contains('Combined stock is calculated')),
        isTrue,
      );

      expect(steps[3].title, contains('Bill History & Governance'));
    });

    test('Neemrana steps enforce green theme, physical count, and single-store stock deduction', () {
      final steps = OnboardingStep.getStepsForRole(UserRole.neemrana);
      expect(steps.length, 4);

      expect(steps[0].title, contains('Neemrana Store'));
      expect(steps[0].bulletPoints.any((b) => b.contains('green theme')), isTrue);
      expect(steps[0].bulletPoints.any((b) => b.contains('never alter Jaipur stock')), isTrue);

      expect(steps[1].title, contains('Neemrana Inventory'));
      expect(steps[1].shortcutType, OnboardingShortcutType.inventory);

      expect(steps[2].title, contains('Fast Guided New Sale'));
      expect(steps[2].shortcutType, OnboardingShortcutType.pos);

      expect(steps[3].title, contains('WhatsApp Handoff'));
      expect(steps[3].bulletPoints.any((b) => b.contains('deducted exactly once')), isTrue);
    });

    test('Jaipur steps enforce amber theme, Jaipur stock isolation, and retail POS flow', () {
      final steps = OnboardingStep.getStepsForRole(UserRole.jaipur);
      expect(steps.length, 4);

      expect(steps[0].title, contains('Jaipur Store'));
      expect(steps[0].bulletPoints.any((b) => b.contains('amber theme')), isTrue);
      expect(steps[0].bulletPoints.any((b) => b.contains('never directly modify Neemrana')), isTrue);

      expect(steps[1].title, contains('Jaipur Inventory'));
      expect(steps[2].title, contains('Guided Retail Billing'));
      expect(steps[3].title, contains('WhatsApp Handoff'));
    });
  });

  group('2. User-Scoped Onboarding Storage Persistence', () {
    test('Tracking status is user-scoped and supports restart reset', () async {
      final storage = OnboardingStorage();

      expect(await storage.isCompleted('user-owner-1'), isFalse);
      expect(await storage.isCompleted('user-neemrana-1'), isFalse);

      await storage.markCompleted('user-owner-1');
      expect(await storage.isCompleted('user-owner-1'), isTrue);
      expect(await storage.isCompleted('user-neemrana-1'), isFalse);

      // Reset allows restarting guided tour
      await storage.reset('user-owner-1');
      expect(await storage.isCompleted('user-owner-1'), isFalse);
    });
  });

  group('3. RoleOnboardingDialog Interactive Walkthrough', () {
    testWidgets('Walkthrough displays progress, navigates forward/back, and finishes', (tester) async {
      bool isFinished = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleOnboardingDialog(
              role: UserRole.owner,
              onFinish: () => isFinished = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1
      expect(find.byKey(const Key('onboarding_dialog')), findsOneWidget);
      expect(find.text('KIZUNA VEDA'), findsOneWidget);
      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(find.byKey(const Key('onboarding_back_button')), findsNothing);

      // Tap Continue -> Step 2
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      expect(find.text('Step 2 of 4'), findsOneWidget);
      expect(find.byKey(const Key('onboarding_back_button')), findsOneWidget);

      // Tap Back -> Returns to Step 1
      await tester.tap(find.byKey(const Key('onboarding_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 4'), findsOneWidget);

      // Advance to Step 4 (Finish)
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      expect(find.text('Step 4 of 4'), findsOneWidget);
      final finishBtn = find.byKey(const Key('onboarding_finish_button'));
      expect(finishBtn, findsOneWidget);
      expect(find.text('Finish Guide'), findsOneWidget);

      await tester.tap(finishBtn);
      await tester.pumpAndSettle();

      expect(isFinished, isTrue);
    });

    testWidgets('Skip button immediately triggers onFinish and dismisses dialog', (tester) async {
      bool isSkipped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleOnboardingDialog(
              role: UserRole.neemrana,
              onFinish: () => isSkipped = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final skipBtn = find.byKey(const Key('onboarding_skip_button'));
      expect(skipBtn, findsOneWidget);

      await tester.tap(skipBtn);
      await tester.pumpAndSettle();

      expect(isSkipped, isTrue);
    });

    testWidgets('Actionable shortcut buttons trigger provided callbacks', (tester) async {
      int? navigatedTab;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleOnboardingDialog(
              role: UserRole.jaipur,
              onNavigateToTab: (idx) => navigatedTab = idx,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1 has 'Open Dashboard' shortcut
      final shortcutBtn = find.byKey(const Key('onboarding_shortcut_button'));
      expect(shortcutBtn, findsOneWidget);
      expect(find.text('Open Dashboard'), findsOneWidget);

      await tester.ensureVisible(shortcutBtn);
      await tester.tap(shortcutBtn);
      await tester.pumpAndSettle();

      expect(navigatedTab, 0);
    });
  });

  group('4. MainNavigationShell First-Login Onboarding Trigger', () {
    late LocalSessionStorage sessionStorage;
    late UnconnectedAuthRepository authRepo;
    late AuthNotifier authNotifier;

    setUp(() {
      sessionStorage = LocalSessionStorage();
      authRepo = UnconnectedAuthRepository(sessionStorage: sessionStorage);
      const user = AuthUser(
        id: 'new-neemrana-user-1',
        email: 'staff@neemrana.kizunaveda.com',
        fullName: 'Counter Staff',
        role: UserRole.neemrana,
      );
      authRepo.setSessionForTesting(const AuthSession(user: user, accessToken: 'token-123'));
      authNotifier = AuthNotifier(authRepository: authRepo);
    });

    tearDown(() {
      authNotifier.dispose();
      authRepo.dispose();
    });

    testWidgets('Shows onboarding on first login, then suppresses on next launch once marked', (tester) async {
      // First launch: onboarding not completed
      expect(await OnboardingStorage.instance.isCompleted('new-neemrana-user-1'), isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: MainNavigationShell(
            role: UserRole.neemrana,
            authNotifier: authNotifier,
            autoShowOnboarding: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Onboarding dialog is presented
      expect(find.byKey(const Key('onboarding_dialog')), findsOneWidget);
      expect(find.text(UserRole.neemrana.displayName.toUpperCase()), findsWidgets);

      // Dismiss via Skip
      await tester.tap(find.byKey(const Key('onboarding_skip_button')));
      await tester.pumpAndSettle();

      // Dialog is dismissed and marked completed in storage
      expect(find.byKey(const Key('onboarding_dialog')), findsNothing);
      expect(await OnboardingStorage.instance.isCompleted('new-neemrana-user-1'), isTrue);

      // Re-mount MainNavigationShell: should NOT show onboarding again
      await tester.pumpWidget(
        MaterialApp(
          home: MainNavigationShell(
            role: UserRole.neemrana,
            authNotifier: authNotifier,
            autoShowOnboarding: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('onboarding_dialog')), findsNothing);
    });
  });

  group('5. Persistent Help & Setup Guide Screen', () {
    testWidgets('HelpAndSetupGuideScreen renders role workflows, FAQ, shortcuts, and restart tour', (tester) async {
      int? tabSelected;
      bool newSaleOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: HelpAndSetupGuideScreen(
            role: UserRole.owner,
            userId: 'test-owner-id',
            onNavigateToTab: (idx) => tabSelected = idx,
            onOpenNewSale: () => newSaleOpened = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Title & Header
      expect(find.text('Help & Setup Guide'), findsOneWidget);
      expect(find.text('${UserRole.owner.displayName} Guide'), findsOneWidget);
      expect(find.byKey(const Key('btn_restart_tour')), findsOneWidget);

      // Direct task shortcuts
      expect(find.byKey(const Key('shortcut_dashboard')), findsOneWidget);
      expect(find.byKey(const Key('shortcut_inventory')), findsOneWidget);
      expect(find.byKey(const Key('shortcut_new_sale')), findsOneWidget);
      expect(find.byKey(const Key('shortcut_sales_history')), findsOneWidget);

      // Role workflows
      expect(find.text('1. Executive Metrics & Sales Analysis'), findsOneWidget);
      expect(find.text('2. Multi-Store Inventory Governance'), findsOneWidget);
      expect(find.text('Why are dashboard metrics showing zero?'), findsOneWidget);

      // Test shortcut tapping
      await tester.tap(find.byKey(const Key('shortcut_inventory')));
      await tester.pumpAndSettle();
      expect(tabSelected, 2);

      await tester.tap(find.byKey(const Key('shortcut_new_sale')));
      await tester.pumpAndSettle();
      expect(newSaleOpened, isTrue);
    });

    testWidgets('MoreSettingsView contains Help & Setup Guide entry tile', (tester) async {
      bool helpOpened = false;
      final authRepo = UnconnectedAuthRepository(sessionStorage: LocalSessionStorage());
      const user = AuthUser(
        id: 'owner-test',
        email: 'owner@kizunaveda.com',
        role: UserRole.owner,
      );
      authRepo.setSessionForTesting(const AuthSession(user: user, accessToken: 'token'));
      final notifier = AuthNotifier(authRepository: authRepo);

      await tester.pumpWidget(
        MaterialApp(
          home: MoreSettingsView(
            role: UserRole.owner,
            authNotifier: notifier,
            onOpenHelpGuide: () => helpOpened = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final helpTile = find.byKey(const Key('tile_help_guide'));
      expect(helpTile, findsOneWidget);
      expect(find.text('Help & Setup Guide'), findsOneWidget);

      await tester.ensureVisible(helpTile);
      await tester.tap(helpTile);
      await tester.pumpAndSettle();

      expect(helpOpened, isTrue);

      notifier.dispose();
      authRepo.dispose();
    });

    testWidgets('VyaparDashboardView AppBar contains Help IconButton', (tester) async {
      bool helpOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: VyaparDashboardView(
            role: UserRole.jaipur,
            onOpenHelpGuide: () => helpOpened = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final helpBtn = find.byKey(const Key('btn_help_guide'));
      expect(helpBtn, findsOneWidget);

      await tester.tap(helpBtn);
      await tester.pumpAndSettle();

      expect(helpOpened, isTrue);
    });
  });
}
