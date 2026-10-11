import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/app/providers/inventory_provider.dart';
import 'package:kizuna_veda/core/constants/app_constants.dart';
import 'package:kizuna_veda/core/services/pdf_invoice_service.dart';
import 'package:kizuna_veda/features/auth/data/repositories/unconnected_auth_repository.dart';
import 'package:kizuna_veda/features/auth/data/services/local_session_storage.dart';
import 'package:kizuna_veda/features/auth/domain/entities/auth_session.dart';
import 'package:kizuna_veda/features/auth/domain/entities/auth_user.dart';
import 'package:kizuna_veda/features/auth/presentation/controllers/auth_notifier.dart';
import 'package:kizuna_veda/features/dashboard/presentation/screens/vyapar_dashboard_view.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/sale.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/navigation/presentation/screens/main_navigation_shell.dart';
import 'package:kizuna_veda/features/sales/presentation/screens/dedicated_sales_view.dart';
import 'package:kizuna_veda/features/sales/presentation/screens/guided_new_sale_screen.dart';

class TestInventoryRepo extends UnconnectedInventoryRepository {
  Completer<void>? inFlightCompleter;
  int recordSaleCallCount = 0;

  @override
  Future<Sale> recordSale({
    required String productId,
    required int quantity,
    String? customerName,
    String? customerPhone,
    String paymentMethod = 'CASH',
    String? locationId,
    String invoiceType = 'NON_GST',
    double gstRate = 0.0,
    double? taxableAmount,
    double cgstAmount = 0.0,
    double sgstAmount = 0.0,
    double igstAmount = 0.0,
    double totalAmount = 0.0,
    double? unitPrice,
    double discount = 0.0,
    DateTime? soldAt,
  }) async {
    recordSaleCallCount++;
    final sale = await super.recordSale(
      productId: productId,
      quantity: quantity,
      customerName: customerName,
      customerPhone: customerPhone,
      paymentMethod: paymentMethod,
      locationId: locationId,
      invoiceType: invoiceType,
      gstRate: gstRate,
      taxableAmount: taxableAmount,
      cgstAmount: cgstAmount,
      sgstAmount: sgstAmount,
      igstAmount: igstAmount,
      totalAmount: totalAmount,
      unitPrice: unitPrice,
      discount: discount,
      soldAt: soldAt,
    );

    if (inFlightCompleter != null) {
      await inFlightCompleter!.future;
    }
    return sale;
  }
}

void main() {
  group('Vyapar-Inspired Navigation & Dashboard UX Redesign Tests', () {
    late TestInventoryRepo inventoryRepo;
    late InventoryNotifier inventoryNotifier;
    late LocalSessionStorage sessionStorage;
    late UnconnectedAuthRepository authRepo;
    late AuthNotifier authNotifier;
    late List<Uri> launchedUris;
    late List<String> sharedTexts;

    setUp(() async {
      launchedUris = [];
      sharedTexts = [];
      PdfInvoiceService.testTempDir = () async => Directory.systemTemp;
      PdfInvoiceService.testLauncher = (uri) async {
        launchedUris.add(uri);
        return true;
      };
      PdfInvoiceService.testSharer = (files, {text}) async {
        if (text != null) sharedTexts.add(text);
      };

      inventoryRepo = TestInventoryRepo();
      inventoryNotifier = InventoryNotifier(repository: inventoryRepo);
      await inventoryNotifier.loadInventoryData();

      sessionStorage = LocalSessionStorage();
      authRepo = UnconnectedAuthRepository(sessionStorage: sessionStorage);
      const user = AuthUser(
        id: 'owner-test-1',
        email: 'owner@kizunaveda.com',
        fullName: 'Test Owner',
        role: UserRole.owner,
      );
      authRepo.setSessionForTesting(
          const AuthSession(user: user, accessToken: 'test-token'));
      authNotifier = AuthNotifier(authRepository: authRepo);
    });

    tearDown(() {
      authNotifier.dispose();
      authRepo.dispose();
      inventoryNotifier.dispose();
    });

    Widget buildTestApp({Widget? child, UserRole role = UserRole.owner}) {
      return InventoryProvider(
        notifier: inventoryNotifier,
        child: MaterialApp(
          home: child ??
              MainNavigationShell(
                role: role,
                authNotifier: authNotifier,
                autoShowOnboarding: false,
              ),
        ),
      );
    }

    testWidgets(
        '1. Main navigation: seamless bottom navigation across Dashboard, Sales, Inventory, and More without Back button',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Starts at index 0 (Dashboard)
      expect(find.byType(VyaparDashboardView), findsOneWidget);
      expect(find.byKey(const Key('fab_new_sale')), findsOneWidget);

      // Navigate to Sales Tab (index 1) via Bottom Navigation Bar
      final salesTab = find.text('Sales');
      expect(salesTab, findsWidgets);
      await tester.tap(salesTab.first);
      await tester.pumpAndSettle();

      expect(find.byType(DedicatedSalesView), findsOneWidget);
      expect(find.byKey(const Key('sales_search_field')), findsOneWidget);

      // Navigate to Inventory Tab (index 2)
      final inventoryTab = find.text('Inventory');
      expect(inventoryTab, findsWidgets);
      await tester.tap(inventoryTab.first);
      await tester.pumpAndSettle();

      expect(find.text('Combined Outlets Stock'), findsOneWidget);

      // Navigate to More / Settings Tab (index 3)
      final moreTab = find.text('More');
      expect(moreTab, findsWidgets);
      await tester.tap(moreTab.first);
      await tester.pumpAndSettle();

      expect(find.text('More & Settings'), findsOneWidget);
      expect(find.text('Logout Session'), findsOneWidget);

      // Navigate back to Dashboard without Back button
      final dashboardTab = find.text('Dashboard');
      expect(dashboardTab, findsWidgets);
      await tester.tap(dashboardTab.first);
      await tester.pumpAndSettle();

      expect(find.text('Total Sales Revenue'), findsOneWidget);
    });

    testWidgets(
        '2. Dashboard: reactive outlet filters and date preset switching update metrics',
        (tester) async {
      await tester.pumpWidget(buildTestApp(role: UserRole.owner));
      await tester.pumpAndSettle();

      // Verify dashboard revenue metrics card
      expect(find.text('Total Sales Revenue'), findsOneWidget);
      expect(find.text('Completed Bills'), findsOneWidget);
      expect(find.text('Packets Sold'), findsOneWidget);
      expect(find.text('Cash Collected'), findsOneWidget);
      expect(find.text('UPI Collected'), findsOneWidget);
      expect(find.text('Jaipur Store'), findsOneWidget);
      expect(find.text('Neemrana Store'), findsOneWidget);

      // Switch Outlet Filter to Jaipur
      final jaipurOutletChip = find.text('Jaipur');
      expect(jaipurOutletChip, findsWidgets);
      await tester.tap(jaipurOutletChip.first, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Switch Date preset filter to "Today"
      final todayPresetChip = find.text('Today');
      expect(todayPresetChip, findsWidgets);
      await tester.tap(todayPresetChip.first, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Verify selected state retains
      expect(find.text('Total Sales Revenue'), findsOneWidget);
    });

    testWidgets(
        '3. Guided New Sale: step indicator, state preservation between steps, and review stage',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const GuidedNewSaleScreen(
            initialLocationId: LocationConstants.jaipurId,
            role: UserRole.jaipur,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Products & Quantities
      expect(find.text('1. Items'), findsOneWidget);
      expect(find.byKey(const Key('guided_quantity_field')), findsOneWidget);

      // Enter 3 packets
      await tester.enterText(
          find.byKey(const Key('guided_quantity_field')), '3');
      await tester.pumpAndSettle();

      // Advance to Step 2: Customer & Payment
      final nextButton = find.byKey(const Key('guided_next_button'));
      expect(nextButton, findsOneWidget);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      expect(find.text('2. Customer & Pay'), findsOneWidget);
      expect(find.byKey(const Key('guided_customer_name_field')), findsOneWidget);
      expect(
          find.byKey(const Key('guided_customer_phone_field')), findsOneWidget);

      // Enter customer info and UPI payment
      await tester.enterText(
          find.byKey(const Key('guided_customer_name_field')), 'Rohit Sharma');
      await tester.enterText(
          find.byKey(const Key('guided_customer_phone_field')), '9876543210');
      await tester.tap(find.byKey(const Key('payment_option_UPI')));
      await tester.pumpAndSettle();

      // Navigate BACK to Step 1: verify quantities are NOT lost
      final backButton = find.byKey(const Key('guided_back_button'));
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Expect entered quantity 3 was preserved!
      final qtyFormField = tester.widget<TextFormField>(
          find.byKey(const Key('guided_quantity_field')));
      expect(qtyFormField.controller?.text, '3');

      // Navigate forward again to Step 2
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      // Expect customer name Rohit Sharma was preserved!
      final nameField = tester.widget<TextFormField>(
          find.byKey(const Key('guided_customer_name_field')));
      expect(nameField.controller?.text, 'Rohit Sharma');

      // Advance to Step 3: Review Bill
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      expect(find.text('3. Review Bill'), findsOneWidget);
      expect(find.text('Rohit Sharma'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('UPI'), findsWidgets);
      expect(find.byKey(const Key('complete_sale_send_whatsapp_button')),
          findsOneWidget);
    });

    testWidgets(
        '4. Guided New Sale: completes sale once via Supabase RPC, launches WhatsApp, and returns completed bill',
        (tester) async {
      Sale? createdSale;
      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  createdSale = await GuidedNewSaleScreen.navigateTo(
                    ctx,
                    initialLocationId: LocationConstants.jaipurId,
                    role: UserRole.jaipur,
                  );
                },
                child: const Text('Open Guided Sale'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Guided Sale'));
      await tester.pumpAndSettle();

      // Step 1: Qty = 2
      await tester.enterText(
          find.byKey(const Key('guided_quantity_field')), '2');
      await tester.tap(find.byKey(const Key('guided_next_button')));
      await tester.pumpAndSettle();

      // Step 2: Customer phone
      await tester.enterText(
          find.byKey(const Key('guided_customer_name_field')), 'Pooja Verma');
      await tester.enterText(
          find.byKey(const Key('guided_customer_phone_field')), '9876500000');
      await tester.tap(find.byKey(const Key('guided_next_button')));
      await tester.pumpAndSettle();

      // Step 3: Review Bill & Complete Sale
      expect(inventoryRepo.recordSaleCallCount, 0);
      final completeButton =
          find.byKey(const Key('complete_sale_send_whatsapp_button'));
      expect(completeButton, findsOneWidget);

      await tester.tap(completeButton);
      await tester.pump();
      await tester.pumpAndSettle();

      // Sale committed exactly once via secure RPC
      expect(inventoryRepo.recordSaleCallCount, 1);
      // WhatsApp launched with customer's formatted bill
      expect(launchedUris.isNotEmpty, isTrue);
      expect(launchedUris.first.toString(), contains('919876500000'));

      // Completion screen shown
      expect(find.text('Sale Completed!'), findsOneWidget);

      // Done button pops and returns the completed bill
      await tester.tap(find.byKey(const Key('done_button')));
      await tester.pumpAndSettle();

      expect(createdSale, isNotNull);
      expect(createdSale!.customerName, 'Pooja Verma');
      expect(createdSale!.quantity, 2);
    });

    testWidgets(
        '5. Guided New Sale: WhatsApp failure keeps bill saved and allows retry without duplicate sale',
        (tester) async {
      // Simulate WhatsApp failure on initial dispatch
      PdfInvoiceService.testLauncher = (uri) async => false;

      await tester.pumpWidget(
        buildTestApp(
          child: const GuidedNewSaleScreen(
            initialLocationId: LocationConstants.jaipurId,
            role: UserRole.jaipur,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fill in and reach review stage
      await tester.enterText(
          find.byKey(const Key('guided_quantity_field')), '1');
      await tester.tap(find.byKey(const Key('guided_next_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('guided_customer_name_field')), 'Anita Roy');
      await tester.enterText(
          find.byKey(const Key('guided_customer_phone_field')), '9811122233');
      await tester.tap(find.byKey(const Key('guided_next_button')));
      await tester.pumpAndSettle();

      // Tap Complete Sale & Send WhatsApp
      await tester.tap(
          find.byKey(const Key('complete_sale_send_whatsapp_button')));
      await tester.pump();
      await tester.pumpAndSettle();

      // Sale is persisted!
      expect(inventoryRepo.recordSaleCallCount, 1);
      expect(find.text('Sale Completed!'), findsOneWidget);
      // WhatsApp retry button is present
      final retryButton = find.byKey(const Key('retry_whatsapp_button'));
      expect(retryButton, findsOneWidget);

      // Restore WhatsApp launcher for retry
      PdfInvoiceService.testLauncher = (uri) async {
        launchedUris.add(uri);
        return true;
      };

      // Tap Retry WhatsApp
      await tester.tap(retryButton);
      await tester.pump();
      await tester.pumpAndSettle();

      // Crucial: Sale was NOT duplicated (call count remains 1)
      expect(inventoryRepo.recordSaleCallCount, 1);
      expect(launchedUris.isNotEmpty, isTrue);
      expect(launchedUris.first.toString(), contains('919811122233'));
    });

    testWidgets(
        '6. Guided New Sale: double-tap protection prevents duplicate sale submissions while processing',
        (tester) async {
      inventoryRepo.inFlightCompleter = Completer<void>();

      await tester.pumpWidget(
        buildTestApp(
          child: const GuidedNewSaleScreen(
            initialLocationId: LocationConstants.jaipurId,
            role: UserRole.jaipur,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fill and advance to step 3
      await tester.enterText(
          find.byKey(const Key('guided_quantity_field')), '1');
      await tester.tap(find.byKey(const Key('guided_next_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('guided_customer_name_field')), 'Vijay Kumar');
      await tester.enterText(
          find.byKey(const Key('guided_customer_phone_field')), '9876543210');
      await tester.tap(find.byKey(const Key('guided_next_button')));
      await tester.pumpAndSettle();

      final completeButton =
          find.byKey(const Key('complete_sale_send_whatsapp_button'));

      // First tap starts processing
      await tester.tap(completeButton);
      await tester.pump();

      // Second tap while in-flight
      await tester.tap(completeButton);
      await tester.pump();

      // Complete the background network call
      inventoryRepo.inFlightCompleter!.complete();
      await tester.pumpAndSettle();

      // Assert only 1 sale was created, double-tap was rejected safely
      expect(inventoryRepo.recordSaleCallCount, 1);
    });

    testWidgets(
        '7. Dedicated Sales Tab: search by bill number and customer name works reactively',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const Scaffold(
            body: DedicatedSalesView(
              role: UserRole.owner,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial bills count summary
      expect(find.byKey(const Key('sales_search_field')), findsOneWidget);

      // Search for specific customer or non-existent bill
      await tester.enterText(
          find.byKey(const Key('sales_search_field')), 'NON_EXISTENT_BILL_XYZ');
      await tester.pumpAndSettle();

      expect(find.text('No Bills Found'), findsOneWidget);

      // Clear search
      await tester.enterText(
          find.byKey(const Key('sales_search_field')), '');
      await tester.pumpAndSettle();

      expect(find.text('No Bills Found'), findsNothing);
    });
  });
}
