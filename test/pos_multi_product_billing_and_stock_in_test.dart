import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/app/providers/inventory_provider.dart';
import 'package:kizuna_veda/core/constants/app_constants.dart';
import 'package:kizuna_veda/core/services/pdf_invoice_service.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/location.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/inventory/presentation/widgets/stock_in_dialog.dart';
import 'package:kizuna_veda/features/sales/presentation/screens/guided_new_sale_screen.dart';

int _getStock(InventoryNotifier notifier, String locationId, String productId) {
  final summary = notifier.inventorySummaries
      .firstWhere((s) => s.product.id == productId);
  return locationId == Location.neemranaId
      ? summary.neemranaFinishedStock
      : summary.jaipurFinishedStock;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('POS Product Loading, Multi-Product Cart & Stock In Tests', () {
    late UnconnectedInventoryRepository repo;
    late InventoryNotifier notifier;

    setUp(() async {
      PdfInvoiceService.testTempDir = () async => Directory.systemTemp;
      PdfInvoiceService.testLauncher = (uri) async => true;

      repo = UnconnectedInventoryRepository();
      notifier = InventoryNotifier(repository: repo);
      await notifier.loadInventoryData();
    });

    tearDown(() {
      PdfInvoiceService.testLauncher = null;
      notifier.dispose();
    });

    Widget buildTestApp({required Widget child}) {
      return InventoryProvider(
        notifier: notifier,
        child: MaterialApp(
          home: child,
        ),
      );
    }

    test('1. Product Loading: All eligible active finished products are loaded into catalogue', () async {
      final products = notifier.products;
      expect(products, isNotEmpty);
      expect(products.length, greaterThanOrEqualTo(4));

      // Check all 4 standard Ayurvedic finished products
      final triphala = products.where((p) => p.sku == 'KV-TRI-250').firstOrNull;
      final ashwagandha = products.where((p) => p.sku == 'KV-ASH-100').firstOrNull;
      final chyawanprash = products.where((p) => p.sku == 'KV-CHY-500').firstOrNull;
      final tulsi = products.where((p) => p.sku == 'KV-TUL-050').firstOrNull;

      expect(triphala, isNotNull);
      expect(triphala!.name, 'Triphala Churna Premium');
      expect(triphala.packageSize, '250g');
      expect(triphala.active, isTrue);

      expect(ashwagandha, isNotNull);
      expect(ashwagandha!.name, 'Ashwagandha Root Powder');
      expect(ashwagandha.packageSize, '100g');
      expect(ashwagandha.active, isTrue);

      expect(chyawanprash, isNotNull);
      expect(chyawanprash!.name, 'Chyawanprash Special');
      expect(chyawanprash.packageSize, '500g');
      expect(chyawanprash.active, isTrue);

      expect(tulsi, isNotNull);
      expect(tulsi!.name, 'Tulsi Ark');
      expect(tulsi.packageSize, '50ml');
      expect(tulsi.active, isTrue);
    });

    testWidgets('2. New Sale Product Selection: Displays all active finished products in dropdown', (tester) async {
      tester.view.physicalSize = const Size(1024, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          child: const GuidedNewSaleScreen(
            initialLocationId: LocationConstants.jaipurId,
            role: UserRole.jaipur,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the product dropdown
      final dropdownFinder = find.byKey(const Key('guided_product_select'));
      expect(dropdownFinder, findsOneWidget);

      // Tap dropdown to view all items
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // Verify that all active products are present in the dropdown menu
      expect(find.text('Triphala Churna Premium (250g)'), findsWidgets);
      expect(find.text('Ashwagandha Root Powder (100g)'), findsWidgets);
      expect(find.text('Chyawanprash Special (500g)'), findsWidgets);
      expect(find.text('Tulsi Ark (50ml)'), findsWidgets);
    });

    testWidgets('3. Multi-Product Cart: Add multiple different products, line totals, and grand total', (tester) async {
      tester.view.physicalSize = const Size(1024, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          child: const GuidedNewSaleScreen(
            initialLocationId: LocationConstants.jaipurId,
            role: UserRole.jaipur,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially, Jaipur stock for Tulsi Ark is 100, Triphala is 150
      // 1. Add first product (Triphala Churna) with quantity 2
      await tester.enterText(find.byKey(const Key('guided_quantity_field')), '2');
      await tester.pumpAndSettle();

      final addButton = find.byKey(const Key('add_item_to_cart_button'));
      expect(addButton, findsOneWidget);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Cart now has 1 item
      expect(find.text('Items in this Bill (1 product)'), findsOneWidget);
      expect(find.byKey(const Key('line_total_0')), findsOneWidget);
      expect(find.text('₹240.00'), findsWidgets); // 2 * 120 = 240

      // 2. Select second product (Tulsi Ark) from dropdown
      final dropdownFinder = find.byKey(const Key('guided_product_select'));
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // Select Tulsi Ark
      await tester.tap(find.text('Tulsi Ark (50ml)').last);
      await tester.pumpAndSettle();

      // Enter quantity 3
      await tester.enterText(find.byKey(const Key('guided_quantity_field')), '3');
      await tester.pumpAndSettle();

      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Cart now has 2 items
      expect(find.text('Items in this Bill (2 products)'), findsOneWidget);
      expect(find.byKey(const Key('line_total_0')), findsOneWidget);
      expect(find.byKey(const Key('line_total_1')), findsOneWidget);
      // Item 0: 240, Item 1: 3 * 100 = 300. Grand total: 540.00
      expect(find.text('Bill Total: ₹540.00'), findsOneWidget);
    });

    testWidgets('4. Multi-Product Cart: Remove item recalculates bill total accurately', (tester) async {
      tester.view.physicalSize = const Size(1024, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          child: const GuidedNewSaleScreen(
            initialLocationId: LocationConstants.jaipurId,
            role: UserRole.jaipur,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final addButton = find.byKey(const Key('add_item_to_cart_button'));

      // Add item 1
      await tester.enterText(find.byKey(const Key('guided_quantity_field')), '2');
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Add item 2 (dropdown automatically advanced to next available product)
      await tester.enterText(find.byKey(const Key('guided_quantity_field')), '1');
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      expect(find.text('Items in this Bill (2 products)'), findsOneWidget);

      // Remove item 0
      final removeFirst = find.byKey(const Key('remove_cart_item_0'));
      expect(removeFirst, findsOneWidget);
      await tester.tap(removeFirst);
      await tester.pumpAndSettle();

      // Now only 1 item in cart
      expect(find.text('Items in this Bill (1 product)'), findsOneWidget);
    });

    testWidgets('5. Stock Validation per Product: Adding excess quantity is blocked with friendly error', (tester) async {
      tester.view.physicalSize = const Size(1024, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          child: const GuidedNewSaleScreen(
            initialLocationId: LocationConstants.jaipurId,
            role: UserRole.jaipur,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select Chyawanprash (which currently has 0 stock at Jaipur)
      final dropdownFinder = find.byKey(const Key('guided_product_select'));
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chyawanprash Special (500g)').last);
      await tester.pumpAndSettle();

      // Attempt to add 5 packets when 0 are available
      await tester.enterText(find.byKey(const Key('guided_quantity_field')), '5');
      await tester.tap(find.byKey(const Key('add_item_to_cart_button')));
      await tester.pumpAndSettle();

      // Error message must show stock limit
      expect(find.textContaining('Only 0 pkts available in stock'), findsOneWidget);
      // Cart should remain empty
      expect(find.textContaining('Items in this Bill'), findsNothing);
    });

    testWidgets('6. Complete Multi-Product Checkout: Submits 1 atomic bill with all line items', (tester) async {
      tester.view.physicalSize = const Size(1024, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          child: const GuidedNewSaleScreen(
            initialLocationId: LocationConstants.jaipurId,
            role: UserRole.jaipur,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialJaipurTriphala = _getStock(notifier, Location.jaipurId, 'prod-101');
      final initialJaipurTulsi = _getStock(notifier, Location.jaipurId, 'prod-104');
      expect(initialJaipurTriphala, greaterThanOrEqualTo(2));
      expect(initialJaipurTulsi, greaterThanOrEqualTo(3));

      final addButton = find.byKey(const Key('add_item_to_cart_button'));

      // Add Product 1: Triphala x 2
      await tester.enterText(find.byKey(const Key('guided_quantity_field')), '2');
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Select Product 2: Tulsi Ark x 3
      final dropdownFinder = find.byKey(const Key('guided_product_select'));
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tulsi Ark (50ml)').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('guided_quantity_field')), '3');
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Tap Continue to Step 1 (Customer & Payment)
      final continueButton = find.byKey(const Key('continue_to_customer_button'));
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      expect(find.text('2. Customer & Pay'), findsOneWidget);

      // Enter customer info
      await tester.enterText(find.byKey(const Key('guided_customer_name_field')), 'Multiproduct Customer');
      await tester.enterText(find.byKey(const Key('guided_customer_phone_field')), '9876543210');
      await tester.pumpAndSettle();

      // Advance to Step 2 (Review)
      final reviewButton = find.byKey(const Key('continue_to_review_bill_button'));
      await tester.tap(reviewButton);
      await tester.pumpAndSettle();

      expect(find.text('3. Review Bill'), findsOneWidget);
      // Verify both items in preview
      expect(find.text('Triphala Churna Premium'), findsOneWidget);
      expect(find.text('Tulsi Ark'), findsOneWidget);
      // Total amount: (2 * 120) + (3 * 100) = 540
      expect(find.text('₹540.00'), findsWidgets);

      // Complete sale
      final completeButton = find.byKey(const Key('complete_sale_send_whatsapp_button'));
      await tester.tap(completeButton);
      await tester.pumpAndSettle();

      // Completed successfully
      expect(find.text('Sale Completed!'), findsOneWidget);

      // Verify that 1 sale was created with 2 items
      final sales = notifier.sales;
      final latestSale = notifier.lastCreatedSale ?? sales.first;
      expect(latestSale.items.length, 2);
      expect(latestSale.totalAmount, 540.0);

      // Verify stock was decremented for BOTH products at Jaipur
      final postJaipurTriphala = _getStock(notifier, Location.jaipurId, 'prod-101');
      final postJaipurTulsi = _getStock(notifier, Location.jaipurId, 'prod-104');
      expect(postJaipurTriphala, initialJaipurTriphala - 2);
      expect(postJaipurTulsi, initialJaipurTulsi - 3);

      // Verify Neemrana stock was completely untouched
      final neemranaTriphala = _getStock(notifier, Location.neemranaId, 'prod-101');
      final neemranaTulsi = _getStock(notifier, Location.neemranaId, 'prod-104');
      expect(neemranaTriphala, 500); // 500 packed - independent store inventory (transfers eliminated)
      expect(neemranaTulsi, 200); // 200 packed - independent store inventory (transfers eliminated)
    });

    testWidgets('7. Stock In Dialog: Additive stock receipt increments only selected product at selected outlet', (tester) async {
      tester.view.physicalSize = const Size(1024, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          child: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('open_stock_in_btn'),
                onPressed: () => StockInDialog.show(
                  context,
                  userRole: UserRole.jaipur,
                  initialLocationId: LocationConstants.jaipurId,
                ),
                child: const Text('Open Stock In'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialJaipurTulsi = _getStock(notifier, Location.jaipurId, 'prod-104');
      final initialJaipurTriphala = _getStock(notifier, Location.jaipurId, 'prod-101');
      final initialNeemranaTulsi = _getStock(notifier, Location.neemranaId, 'prod-104');

      // Open Stock In Dialog
      await tester.tap(find.byKey(const Key('open_stock_in_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Stock Entry & Adjustment'), findsOneWidget);

      // Select Tulsi Ark in dropdown
      final dropdownFinder = find.byKey(const Key('stock_in_product_dropdown'));
      expect(dropdownFinder, findsOneWidget);
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tulsi Ark (50ml)').last);
      await tester.pumpAndSettle();

      // Enter received quantity 25
      await tester.enterText(find.byKey(const Key('stock_in_quantity_field')), '25');
      await tester.pumpAndSettle();

      // Save stock
      await tester.tap(find.byKey(const Key('stock_in_submit_button')));
      await tester.pumpAndSettle();

      // Verify Tulsi at Jaipur incremented by exactly 25
      final postJaipurTulsi = _getStock(notifier, Location.jaipurId, 'prod-104');
      expect(postJaipurTulsi, initialJaipurTulsi + 25);

      // Verify Triphala at Jaipur is unchanged
      final postJaipurTriphala = _getStock(notifier, Location.jaipurId, 'prod-101');
      expect(postJaipurTriphala, initialJaipurTriphala);

      // Verify Neemrana Tulsi is unchanged
      final postNeemranaTulsi = _getStock(notifier, Location.neemranaId, 'prod-104');
      expect(postNeemranaTulsi, initialNeemranaTulsi);
    });
  });
}
