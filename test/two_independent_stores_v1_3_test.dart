import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/core/config/app_config.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/location.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/product.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/product_inventory_summary.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';

void main() {
  group('V1.3 Two Independent Stores - Core Inventory & Sales Specifications', () {
    late UnconnectedInventoryRepository repository;
    late InventoryNotifier notifier;
    late Product testProduct;

    setUp(() async {
      repository = UnconnectedInventoryRepository();
      notifier = InventoryNotifier(repository: repository);
      await notifier.loadInventoryData();
      testProduct = notifier.products.first;
    });

    tearDown(() {
      notifier.dispose();
    });

    test('1. Independent store stock: Neemrana and Jaipur maintain independent quantities', () async {
      // Set Neemrana stock to 50
      await repository.adjustStoreStock(
        locationId: Location.neemranaId,
        productId: testProduct.id,
        newQuantity: 50,
        reason: 'OPENING_STOCK',
      );

      // Set Jaipur stock to 80
      await repository.adjustStoreStock(
        locationId: Location.jaipurId,
        productId: testProduct.id,
        newQuantity: 80,
        reason: 'OPENING_STOCK',
      );

      await notifier.loadInventoryData();
      final summary = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == testProduct.id);

      expect(summary.neemranaFinishedStock, equals(50));
      expect(summary.jaipurFinishedStock, equals(80));

      // Adjusting Neemrana does not alter Jaipur
      await repository.adjustStoreStock(
        locationId: Location.neemranaId,
        productId: testProduct.id,
        newQuantity: 45,
        reason: 'AUDIT_CORRECTION',
      );

      await notifier.loadInventoryData();
      final updatedSummary = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == testProduct.id);

      expect(updatedSummary.neemranaFinishedStock, equals(45));
      expect(updatedSummary.jaipurFinishedStock, equals(80));
    });

    test('2. Manual opening stock and corrections: Auditable ledger records quantity before/after and reasons', () async {
      // Step A: Record initial physical opening count
      final adj1 = await repository.adjustStoreStock(
        locationId: Location.neemranaId,
        productId: testProduct.id,
        newQuantity: 100,
        reason: 'OPENING_STOCK',
        notes: 'Initial physical inventory count at store opening',
      );

      expect(adj1.previousQuantity, equals(0));
      expect(adj1.newQuantity, equals(100));
      expect(adj1.changeQuantity, equals(100));
      expect(adj1.reason, equals('OPENING_STOCK'));
      expect(adj1.notes, contains('Initial physical inventory'));

      // Step B: Record later physical count correction
      final adj2 = await repository.adjustStoreStock(
        locationId: Location.neemranaId,
        productId: testProduct.id,
        newQuantity: 95,
        reason: 'PHYSICAL_AUDIT',
        notes: 'Shelf recount verified 5 packets damaged',
      );

      expect(adj2.previousQuantity, equals(100));
      expect(adj2.newQuantity, equals(95));
      expect(adj2.changeQuantity, equals(-5));
      expect(adj2.reason, equals('PHYSICAL_AUDIT'));

      // Check ledger entries are queryable
      final ledger = await repository.getStockAdjustments(locationId: Location.neemranaId);
      expect(ledger.length, greaterThanOrEqualTo(2));
      expect(ledger.first.newQuantity, equals(95));
      expect(ledger.first.changeQuantity, equals(-5));
    });

    test('3. Exact deductions for 1, 2, and 10 units: atomically deducts from selling store only', () async {
      // Initialize Neemrana stock to 50
      await repository.adjustStoreStock(
        locationId: Location.neemranaId,
        productId: testProduct.id,
        newQuantity: 50,
      );
      // Initialize Jaipur stock to 30
      await repository.adjustStoreStock(
        locationId: Location.jaipurId,
        productId: testProduct.id,
        newQuantity: 30,
      );

      // Sell 1 packet from Neemrana -> deduct 1
      final sale1 = await notifier.recordSale(
        productId: testProduct.id,
        quantity: 1,
        locationId: Location.neemranaId,
        customerName: 'Customer One',
        customerPhone: '9876543210',
        paymentMethod: 'CASH',
        totalAmount: 150.0,
      );
      expect(sale1, isNotNull);

      var summary = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == testProduct.id);
      expect(summary.neemranaFinishedStock, equals(49));
      expect(summary.jaipurFinishedStock, equals(30)); // Jaipur untouched

      // Sell 2 packets from Neemrana -> deduct 2
      final sale2 = await notifier.recordSale(
        productId: testProduct.id,
        quantity: 2,
        locationId: Location.neemranaId,
        customerName: 'Customer Two',
        customerPhone: '9876543211',
        paymentMethod: 'UPI',
        totalAmount: 300.0,
      );
      expect(sale2, isNotNull);

      summary = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == testProduct.id);
      expect(summary.neemranaFinishedStock, equals(47));
      expect(summary.jaipurFinishedStock, equals(30));

      // Sell 10 packets from Neemrana -> deduct 10
      final sale3 = await notifier.recordSale(
        productId: testProduct.id,
        quantity: 10,
        locationId: Location.neemranaId,
        customerName: 'Customer Ten',
        customerPhone: '9876543212',
        paymentMethod: 'CASH',
        totalAmount: 1500.0,
      );
      expect(sale3, isNotNull);

      summary = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == testProduct.id);
      expect(summary.neemranaFinishedStock, equals(37));
      expect(summary.jaipurFinishedStock, equals(30)); // Jaipur remains 30
    });

    test('4. Combined stock calculation: combined = Neemrana + Jaipur dynamically', () async {
      await repository.adjustStoreStock(
        locationId: Location.neemranaId,
        productId: testProduct.id,
        newQuantity: 37,
      );
      await repository.adjustStoreStock(
        locationId: Location.jaipurId,
        productId: testProduct.id,
        newQuantity: 63,
      );

      await notifier.loadInventoryData();
      final summary = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == testProduct.id);

      expect(summary.neemranaFinishedStock, equals(37));
      expect(summary.jaipurFinishedStock, equals(63));
      expect(summary.combinedTotalStock, equals(100)); // Dynamic sum
    });

    test('5. Insufficient stock prevention: Cannot sell more than available store stock', () async {
      await repository.adjustStoreStock(
        locationId: Location.jaipurId,
        productId: testProduct.id,
        newQuantity: 5,
      );
      await notifier.loadInventoryData();

      // Attempt to sell 6 packets when only 5 are on hand
      final sale = await notifier.recordSale(
        productId: testProduct.id,
        quantity: 6,
        locationId: Location.jaipurId,
        customerName: 'Oversell Tester',
        customerPhone: '9876543210',
        paymentMethod: 'CASH',
        totalAmount: 600.0,
      );

      expect(sale, isNull);
      expect(notifier.errorMessage, contains('Only 5 finished packets available at Jaipur'));
    });

    test('6. Voiding restores stock effect exactly once', () async {
      await repository.adjustStoreStock(
        locationId: Location.jaipurId,
        productId: testProduct.id,
        newQuantity: 20,
      );
      await notifier.loadInventoryData();

      // Sell 5 units
      final sale = await notifier.recordSale(
        productId: testProduct.id,
        quantity: 5,
        locationId: Location.jaipurId,
        customerName: 'Void Customer',
        customerPhone: '9876543210',
        paymentMethod: 'CASH',
        totalAmount: 500.0,
      );
      expect(sale, isNotNull);

      var summary = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == testProduct.id);
      expect(summary.jaipurFinishedStock, equals(15));

      // Void sale: restores 5 units back to 20
      final voided = await notifier.voidSale(saleId: sale!.id);
      expect(voided, isTrue);

      summary = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == testProduct.id);
      expect(summary.jaipurFinishedStock, equals(20));

      // Attempt to void again: fails and does not restore again
      final voidAgain = await notifier.voidSale(saleId: sale.id);
      expect(voidAgain, isFalse);
      expect(notifier.errorMessage, contains('already voided'));

      summary = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == testProduct.id);
      expect(summary.jaipurFinishedStock, equals(20)); // Stock remained 20
    });

    test('7. Prevent invalid negative quantities in stock adjustment', () async {
      expect(
        () => repository.adjustStoreStock(
          locationId: Location.neemranaId,
          productId: testProduct.id,
          newQuantity: -10,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('8. GST restriction: GST toggle is disabled until official configuration is in place', () {
      // Configuration check
      expect(AppConfig.isGstConfigured, isFalse);
      expect(AppConfig.gstin, isEmpty);
    });

    test('9. Legacy stock reconciliation without double-counting', () async {
      // If a product has legacy packed=500 in database, but store operator enters actual count=42,
      // the canonical balance must be 42, NOT 500 + 42 = 542.
      final summaryLegacy = ProductInventorySummary(
        product: testProduct,
        totalPacked: 500,
        totalDispatched: 0,
        totalReceived: 0,
        totalNeemranaSold: 0,
        totalJaipurSold: 0,
      );
      // Legacy fallback when physical count is not yet entered
      expect(summaryLegacy.neemranaFinishedStock, equals(500));

      // With canonical physical count entered:
      final summaryCanonical = ProductInventorySummary(
        product: testProduct,
        totalPacked: 500,
        totalDispatched: 0,
        totalReceived: 0,
        totalNeemranaSold: 0,
        totalJaipurSold: 0,
        neemranaPhysicalStock: 42, // Physical on-hand count entered
      );
      // Uses canonical physical stock: 42, NOT 542!
      expect(summaryCanonical.neemranaFinishedStock, equals(42));
      expect(summaryCanonical.neemranaRemaining, equals(42));
    });
  });
}
