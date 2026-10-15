import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/app/providers/inventory_provider.dart';
import 'package:kizuna_veda/core/constants/app_constants.dart';
import 'package:kizuna_veda/core/services/pdf_invoice_service.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/location.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/product.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/inventory/presentation/widgets/stock_in_dialog.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/product_master_screen.dart';
import 'package:kizuna_veda/features/sales/presentation/screens/guided_new_sale_screen.dart';

int _getStock(InventoryNotifier notifier, String locationId, String productId) {
  final summary = notifier.inventorySummaries
      .firstWhere((s) => s.product.id == productId);
  return locationId == Location.neemranaId
      ? summary.neemranaFinishedStock
      : summary.jaipurFinishedStock;
}

Widget buildTestApp({
  required Widget child,
  required InventoryNotifier notifier,
}) {
  return MaterialApp(
    home: InventoryProvider(
      notifier: notifier,
      child: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UnconnectedInventoryRepository repository;
  late InventoryNotifier notifier;

  setUp(() async {
    PdfInvoiceService.testLauncher = (uri) async => true;
    PdfInvoiceService.testSharer = (files, {text}) async {};

    repository = UnconnectedInventoryRepository();
    notifier = InventoryNotifier(repository: repository);
    await notifier.loadInventoryData();
  });

  group('Product Master, Units & Multi-Product Dry Fruits Billing Tests', () {
    testWidgets('1. Owner-only Product Master & Access Guard for Cashier', (tester) async {
      tester.view.physicalSize = const Size(1024, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Cashier role: Access should be restricted
      await tester.pumpWidget(
        buildTestApp(
          notifier: notifier,
          child: const ProductMasterScreen(role: UserRole.jaipur),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsOneWidget);
      expect(find.textContaining('restricted to authorized Owners'), findsOneWidget);

      // Owner role: Renders catalog and Add Product button
      await tester.pumpWidget(
        buildTestApp(
          notifier: notifier,
          child: const ProductMasterScreen(role: UserRole.owner),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Product Master Catalog'), findsOneWidget);
      expect(find.byKey(const Key('add_new_product_button')), findsOneWidget);
      expect(find.byKey(const Key('quick_add_dry_fruits_button')), findsOneWidget);
    });

    testWidgets('2. Owner creates new product and duplicate SKU is rejected', (tester) async {
      tester.view.physicalSize = const Size(1024, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          notifier: notifier,
          child: const ProductMasterScreen(role: UserRole.owner),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Add Product
      await tester.tap(find.byKey(const Key('add_new_product_button')));
      await tester.pumpAndSettle();

      expect(find.text('Add New Product'), findsOneWidget);

      // Attempt to add a product with existing SKU (KV-ALM-250)
      await tester.enterText(find.byKey(const Key('product_form_name_field')), 'Duplicate Badam');
      await tester.enterText(find.byKey(const Key('product_form_pack_size_field')), '250g');
      await tester.enterText(find.byKey(const Key('product_form_sku_field')), 'KV-ALM-250');
      await tester.enterText(find.byKey(const Key('product_form_price_field')), '320.00');
      await tester.enterText(find.byKey(const Key('product_form_cost_field')), '190.00');

      await tester.tap(find.byKey(const Key('product_form_submit_button')));
      await tester.pumpAndSettle();

      // Duplicate SKU error must appear
      expect(find.textContaining('Product with SKU "KV-ALM-250" already exists'), findsOneWidget);

      // Change to a unique SKU: KV-PST-500 (Pistachios 500g)
      await tester.enterText(find.byKey(const Key('product_form_name_field')), 'Pistachios / Pista');
      await tester.enterText(find.byKey(const Key('product_form_pack_size_field')), '500g');
      await tester.enterText(find.byKey(const Key('product_form_sku_field')), 'KV-PST-500');
      await tester.enterText(find.byKey(const Key('product_form_price_field')), '650.00');
      await tester.enterText(find.byKey(const Key('product_form_cost_field')), '420.00');

      await tester.tap(find.byKey(const Key('product_form_submit_button')));
      await tester.pumpAndSettle();

      // Dialog closed, snackbar shown
      expect(find.text('Add New Product'), findsNothing);
      expect(find.textContaining('Pistachios / Pista (500g)'), findsWidgets);

      // Verify product added in notifier
      final newProd = notifier.products.where((p) => p.sku == 'KV-PST-500').firstOrNull;
      expect(newProd, isNotNull);
      expect(newProd!.standardSellingPrice, 650.0);
      expect(newProd.purchaseCost, 420.0);
      expect(newProd.packageSize, '500g');
    });

    testWidgets('3. Pack Size, Quantity and Total Weight Calculation', (tester) async {
      // Test the unit and weight calculation helper
      final alm250 = Product(
        id: 'test-1',
        name: 'Almonds',
        packageSize: '250g',
        sku: 'TEST-1',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(alm250.calculateTotalWeight(1), '250 g');
      expect(alm250.calculateTotalWeight(2), '500 g');
      expect(alm250.calculateTotalWeight(3), '750 g');
      expect(alm250.calculateTotalWeight(4), '1000 g (1 kg)');

      final date500 = Product(
        id: 'test-2',
        name: 'Dates',
        packageSize: '500g',
        sku: 'TEST-2',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(date500.calculateTotalWeight(2), '1000 g (1 kg)');
      expect(date500.calculateTotalWeight(3), '1500 g (1.50 kg)');

      final alm1kg = Product(
        id: 'test-3',
        name: 'Almonds Bulk',
        packageSize: '1kg',
        sku: 'TEST-3',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(alm1kg.calculateTotalWeight(3), '3 kg');

      final tulsi50ml = Product(
        id: 'test-4',
        name: 'Tulsi Ark',
        packageSize: '50ml',
        sku: 'TEST-4',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(tulsi50ml.calculateTotalWeight(2), '100 ml');
    });

    testWidgets('4. Deactivation hides product from New Sale & Stock In while preserving historical sales', (tester) async {
      tester.view.physicalSize = const Size(1024, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Target product: Raisins / Kishmish (prod-107)
      final initialSalesCount = notifier.sales.length;

      // 1. Deactivate prod-107
      final success = await notifier.toggleProductActive(id: 'prod-107', active: false);
      expect(success, isTrue);

      final raisins = notifier.products.firstWhere((p) => p.id == 'prod-107');
      expect(raisins.active, isFalse);

      // 2. Open New Sale: Raisins must NOT be present in active dropdown items
      await tester.pumpWidget(
        buildTestApp(
          notifier: notifier,
          child: const GuidedNewSaleScreen(
            initialLocationId: LocationConstants.jaipurId,
            role: UserRole.jaipur,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dropdownFinder = find.byKey(const Key('guided_product_select'));
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      expect(find.text('Raisins / Kishmish (250g)'), findsNothing);
      // But active products like Almonds and Kaju must be visible
      expect(find.text('Almonds / Badam (250g)'), findsWidgets);
      expect(find.text('Kaju / Cashews (250g)'), findsWidgets);

      // Close dropdown
      await tester.tap(find.text('Almonds / Badam (250g)').last);
      await tester.pumpAndSettle();

      // 3. Open Stock In Dialog: Raisins must NOT be in active list
      await tester.pumpWidget(
        buildTestApp(
          notifier: notifier,
          child: const StockInDialog(userRole: UserRole.jaipur),
        ),
      );
      await tester.pumpAndSettle();

      final stockInDropdown = find.byKey(const Key('stock_in_product_dropdown'));
      await tester.tap(stockInDropdown);
      await tester.pumpAndSettle();
      expect(find.text('Raisins / Kishmish (250g)'), findsNothing);

      // 4. Assert historical sales records are untouched
      expect(notifier.sales.length, initialSalesCount);

      // 5. Reactivate Raisins
      await notifier.toggleProductActive(id: 'prod-107', active: true);
      expect(notifier.products.firstWhere((p) => p.id == 'prod-107').active, isTrue);
    });

    testWidgets('5. Multi-Product Billing: Almonds + Kaju + Raisins in 1 atomic bill', (tester) async {
      tester.view.physicalSize = const Size(1024, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          notifier: notifier,
          child: const GuidedNewSaleScreen(
            initialLocationId: LocationConstants.jaipurId,
            role: UserRole.jaipur,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialJaipurAlmonds = _getStock(notifier, Location.jaipurId, 'prod-105');
      final initialJaipurKaju = _getStock(notifier, Location.jaipurId, 'prod-106');
      final initialJaipurRaisins = _getStock(notifier, Location.jaipurId, 'prod-107');
      final initialNeemranaAlmonds = _getStock(notifier, Location.neemranaId, 'prod-105');

      expect(initialJaipurAlmonds, greaterThanOrEqualTo(2));
      expect(initialJaipurKaju, greaterThanOrEqualTo(1));
      expect(initialJaipurRaisins, greaterThanOrEqualTo(3));

      final addButton = find.byKey(const Key('add_item_to_cart_button'));
      final dropdownFinder = find.byKey(const Key('guided_product_select'));

      // Product 1: Almonds 250g × 2 packets @ ₹300 = ₹600
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Almonds / Badam (250g)').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('guided_quantity_field')), '2');
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Product 2: Kaju 250g × 1 packet @ ₹350 = ₹350
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaju / Cashews (250g)').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('guided_quantity_field')), '1');
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Product 3: Raisins 250g × 3 packets @ ₹180 = ₹540
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Raisins / Kishmish (250g)').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('guided_quantity_field')), '3');
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Verify cart has 3 products and total is 600 + 350 + 540 = 1490
      expect(find.text('Items in this Bill (3 products)'), findsOneWidget);
      expect(find.text('Bill Total: ₹1490.00'), findsOneWidget);

      // Verify line totals in cart
      expect(find.byKey(const Key('line_total_0')), findsOneWidget);
      expect(find.text('₹600.00'), findsWidgets);
      expect(find.byKey(const Key('line_total_1')), findsOneWidget);
      expect(find.text('₹350.00'), findsWidgets);
      expect(find.byKey(const Key('line_total_2')), findsOneWidget);
      expect(find.text('₹540.00'), findsWidgets);

      // Advance to Step 1: Customer Info
      await tester.tap(find.byKey(const Key('continue_to_customer_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('guided_customer_name_field')), 'Dry Fruits Buyer');
      await tester.enterText(find.byKey(const Key('guided_customer_phone_field')), '9812345678');
      await tester.pumpAndSettle();

      // Advance to Step 2: Review Bill
      await tester.tap(find.byKey(const Key('continue_to_review_bill_button')));
      await tester.pumpAndSettle();

      expect(find.text('3. Review Bill'), findsOneWidget);
      expect(find.text('Almonds / Badam'), findsOneWidget);
      expect(find.text('Kaju / Cashews'), findsOneWidget);
      expect(find.text('Raisins / Kishmish'), findsOneWidget);
      expect(find.text('₹1490.00'), findsWidgets);

      // Complete sale
      await tester.tap(find.byKey(const Key('complete_sale_send_whatsapp_button')));
      await tester.pumpAndSettle();

      expect(find.text('Sale Completed!'), findsOneWidget);

      // Verify that 1 sale was recorded with 3 line items
      final latestSale = notifier.lastCreatedSale ?? notifier.sales.first;
      expect(latestSale.items.length, 3);
      expect(latestSale.totalAmount, 1490.0);
      expect(latestSale.customerName, 'Dry Fruits Buyer');

      // Verify stock was decremented from Jaipur for all 3 products
      expect(_getStock(notifier, Location.jaipurId, 'prod-105'), initialJaipurAlmonds - 2);
      expect(_getStock(notifier, Location.jaipurId, 'prod-106'), initialJaipurKaju - 1);
      expect(_getStock(notifier, Location.jaipurId, 'prod-107'), initialJaipurRaisins - 3);

      // Neemrana stock was completely untouched
      expect(_getStock(notifier, Location.neemranaId, 'prod-105'), initialNeemranaAlmonds);
    });

    testWidgets('6. Additive Stock Receipt: Updates only selected product at selected store', (tester) async {
      final initialJaipurAlmonds = _getStock(notifier, Location.jaipurId, 'prod-105');
      final initialNeemranaAlmonds = _getStock(notifier, Location.neemranaId, 'prod-105');
      final initialJaipurKaju = _getStock(notifier, Location.jaipurId, 'prod-106');

      final success = await notifier.receiveStoreStock(
        locationId: Location.jaipurId,
        productId: 'prod-105',
        quantity: 25,
        notes: 'Fresh almond delivery',
      );
      expect(success, isTrue);

      // Jaipur Almonds increased by 25
      expect(_getStock(notifier, Location.jaipurId, 'prod-105'), initialJaipurAlmonds + 25);
      // Neemrana Almonds untouched
      expect(_getStock(notifier, Location.neemranaId, 'prod-105'), initialNeemranaAlmonds);
      // Jaipur Kaju untouched
      expect(_getStock(notifier, Location.jaipurId, 'prod-106'), initialJaipurKaju);
    });

    testWidgets('7. Idempotent Checkout Retry prevents duplicate sale and second stock deduction', (tester) async {
      final initialStock = _getStock(notifier, Location.jaipurId, 'prod-105');
      const reqId = 'client-req-dryfruit-123';

      final sale1 = await repository.recordSale(
        clientRequestId: reqId,
        locationId: Location.jaipurId,
        productId: 'prod-105',
        quantity: 5,
        unitPrice: 300.0,
        totalAmount: 1500.0,
      );
      expect(sale1, isNotNull);

      await notifier.loadInventoryData();
      expect(_getStock(notifier, Location.jaipurId, 'prod-105'), initialStock - 5);

      // Retry same clientRequestId
      final sale2 = await repository.recordSale(
        clientRequestId: reqId,
        locationId: Location.jaipurId,
        productId: 'prod-105',
        quantity: 5,
        unitPrice: 300.0,
        totalAmount: 1500.0,
      );

      expect(sale2.id, sale1.id);

      await notifier.loadInventoryData();
      // Stock should remain initialStock - 5 (NO second stock deduction)
      expect(_getStock(notifier, Location.jaipurId, 'prod-105'), initialStock - 5);
    });
  });
}
