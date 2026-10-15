import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/location.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/product.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/product_inventory_summary.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/sales/domain/entities/cart_item.dart';

void main() {
  group('Independent Stores Isolation & Zero Cross-Store Operations Tests', () {
    late UnconnectedInventoryRepository repository;
    late InventoryNotifier notifier;

    setUp(() {
      repository = UnconnectedInventoryRepository();
      notifier = InventoryNotifier(repository: repository);
    });

    tearDown(() {
      notifier.dispose();
    });

    test('1. Neemrana Sale deducts stock ONLY from Neemrana and does NOT touch Jaipur inventory', () async {
      await notifier.loadInventoryData();
      final targetProduct = notifier.products.first; // prod-101

      final summaryBefore = notifier.inventorySummaries.firstWhere((s) => s.product.id == targetProduct.id);
      final neemranaBefore = summaryBefore.neemranaFinishedStock;
      final jaipurBefore = summaryBefore.jaipurFinishedStock;

      expect(neemranaBefore, greaterThanOrEqualTo(10));
      expect(jaipurBefore, greaterThan(0));

      // Record POS sale at Neemrana for 10 units
      final sale = await notifier.recordSale(
        locationId: Location.neemranaId,
        items: [
          CartItem(
            product: targetProduct,
            quantity: 10,
            unitPrice: targetProduct.standardSellingPrice,
          ),
        ],
      );

      expect(sale, isNotNull);
      expect(sale!.locationId, Location.neemranaId);

      await notifier.loadInventoryData();
      final summaryAfter = notifier.inventorySummaries.firstWhere((s) => s.product.id == targetProduct.id);

      // Neemrana stock must be decremented by exactly 10
      expect(summaryAfter.neemranaFinishedStock, neemranaBefore - 10);

      // Jaipur stock must remain STRICTLY unchanged
      expect(summaryAfter.jaipurFinishedStock, jaipurBefore);
    });

    test('2. Jaipur Sale deducts stock ONLY from Jaipur and does NOT touch Neemrana inventory', () async {
      await notifier.loadInventoryData();
      final targetProduct = notifier.products.first; // prod-101

      final summaryBefore = notifier.inventorySummaries.firstWhere((s) => s.product.id == targetProduct.id);
      final neemranaBefore = summaryBefore.neemranaFinishedStock;
      final jaipurBefore = summaryBefore.jaipurFinishedStock;

      expect(jaipurBefore, greaterThanOrEqualTo(5));

      // Record POS sale at Jaipur for 5 units
      final sale = await notifier.recordSale(
        locationId: Location.jaipurId,
        items: [
          CartItem(
            product: targetProduct,
            quantity: 5,
            unitPrice: targetProduct.standardSellingPrice,
          ),
        ],
      );

      expect(sale, isNotNull);
      expect(sale!.locationId, Location.jaipurId);

      await notifier.loadInventoryData();
      final summaryAfter = notifier.inventorySummaries.firstWhere((s) => s.product.id == targetProduct.id);

      // Jaipur stock must be decremented by exactly 5
      expect(summaryAfter.jaipurFinishedStock, jaipurBefore - 5);

      // Neemrana stock must remain STRICTLY unchanged
      expect(summaryAfter.neemranaFinishedStock, neemranaBefore);
    });

    test('3. Stock Receipt at Neemrana increments ONLY Neemrana and does NOT touch Jaipur', () async {
      await notifier.loadInventoryData();
      final targetProduct = notifier.products.first;

      final summaryBefore = notifier.inventorySummaries.firstWhere((s) => s.product.id == targetProduct.id);
      final neemranaBefore = summaryBefore.neemranaFinishedStock;
      final jaipurBefore = summaryBefore.jaipurFinishedStock;

      // Receive 50 units at Neemrana
      final success = await notifier.receiveStoreStock(
        locationId: Location.neemranaId,
        productId: targetProduct.id,
        quantity: 50,
        notes: 'Neemrana warehouse intake batch #N-50',
      );

      expect(success, isTrue);

      await notifier.loadInventoryData();
      final summaryAfter = notifier.inventorySummaries.firstWhere((s) => s.product.id == targetProduct.id);

      expect(summaryAfter.neemranaFinishedStock, neemranaBefore + 50);
      expect(summaryAfter.jaipurFinishedStock, jaipurBefore);
    });

    test('4. Stock Receipt at Jaipur increments ONLY Jaipur and does NOT touch Neemrana', () async {
      await notifier.loadInventoryData();
      final targetProduct = notifier.products.first;

      final summaryBefore = notifier.inventorySummaries.firstWhere((s) => s.product.id == targetProduct.id);
      final neemranaBefore = summaryBefore.neemranaFinishedStock;
      final jaipurBefore = summaryBefore.jaipurFinishedStock;

      // Receive 25 units at Jaipur
      final success = await notifier.receiveStoreStock(
        locationId: Location.jaipurId,
        productId: targetProduct.id,
        quantity: 25,
        notes: 'Direct Jaipur distributor intake batch #J-25',
      );

      expect(success, isTrue);

      await notifier.loadInventoryData();
      final summaryAfter = notifier.inventorySummaries.firstWhere((s) => s.product.id == targetProduct.id);

      expect(summaryAfter.jaipurFinishedStock, jaipurBefore + 25);
      expect(summaryAfter.neemranaFinishedStock, neemranaBefore);
    });

    test('5. Stock Adjustment at Neemrana modifies ONLY Neemrana and does NOT touch Jaipur', () async {
      await notifier.loadInventoryData();
      final targetProduct = notifier.products.first;

      final summaryBefore = notifier.inventorySummaries.firstWhere((s) => s.product.id == targetProduct.id);
      final jaipurBefore = summaryBefore.jaipurFinishedStock;

      // Set explicit new physical count at Neemrana to 777
      final success = await notifier.adjustStoreStock(
        locationId: Location.neemranaId,
        productId: targetProduct.id,
        newQuantity: 777,
        reason: 'AUDIT_RECONCILIATION',
        notes: 'Monthly physical count Neemrana',
      );

      expect(success, isTrue);

      await notifier.loadInventoryData();
      final summaryAfter = notifier.inventorySummaries.firstWhere((s) => s.product.id == targetProduct.id);

      expect(summaryAfter.neemranaFinishedStock, 777);
      expect(summaryAfter.jaipurFinishedStock, jaipurBefore);
    });

    test('6. Stock Adjustment at Jaipur modifies ONLY Jaipur and does NOT touch Neemrana', () async {
      await notifier.loadInventoryData();
      final targetProduct = notifier.products.first;

      final summaryBefore = notifier.inventorySummaries.firstWhere((s) => s.product.id == targetProduct.id);
      final neemranaBefore = summaryBefore.neemranaFinishedStock;

      // Set explicit new physical count at Jaipur to 333
      final success = await notifier.adjustStoreStock(
        locationId: Location.jaipurId,
        productId: targetProduct.id,
        newQuantity: 333,
        reason: 'AUDIT_RECONCILIATION',
        notes: 'Monthly physical count Jaipur',
      );

      expect(success, isTrue);

      await notifier.loadInventoryData();
      final summaryAfter = notifier.inventorySummaries.firstWhere((s) => s.product.id == targetProduct.id);

      expect(summaryAfter.jaipurFinishedStock, 333);
      expect(summaryAfter.neemranaFinishedStock, neemranaBefore);
    });

    test('7. Inter-store transfer dispatch and receipt RPCs are permanently disabled and fail closed', () async {
      // Repository-level fail-closed verification
      expect(
        () => repository.createTransfer(
          productId: 'prod-101',
          dispatchedQuantity: 20,
        ),
        throwsA(isA<UnsupportedError>()),
      );

      expect(
        () => repository.confirmTransferReceipt(
          transferId: 'trans-1',
          receivedQuantity: 20,
        ),
        throwsA(isA<UnsupportedError>()),
      );

      // Notifier-level graceful rejection
      final createResult = await notifier.createTransfer(
        productId: 'prod-101',
        dispatchedQuantity: 20,
      );
      expect(createResult, isFalse);
      expect(
        notifier.errorMessage,
        contains('Inter-store stock transfers are permanently disabled'),
      );

      final confirmResult = await notifier.confirmTransferReceipt(
        transferId: 'trans-1',
        receivedQuantity: 20,
      );
      expect(confirmResult, isFalse);
      expect(
        notifier.errorMessage,
        contains('Inter-store stock transfers are permanently disabled'),
      );
    });

    test('8. Product catalogue is shared, but inventory balances and transferDiscrepancy are independent', () {
      final sharedProduct = Product(
        id: 'shared-prod-99',
        name: 'Shared Ayurvedic Syrup',
        packageSize: '200ml',
        sku: 'KV-SYR-200',
        createdAt: DateTime.now(),
      );

      // Case A: Neemrana has stock, Jaipur has zero
      final summaryA = ProductInventorySummary(
        product: sharedProduct,
        totalPacked: 500,
        totalNeemranaStockIn: 50,
        totalNeemranaSold: 20,
        totalJaipurStockIn: 0,
        totalJaipurSold: 0,
        totalDispatched: 0,
        totalReceived: 0,
      );

      expect(summaryA.neemranaFinishedStock, 530); // 500 + 50 - 20
      expect(summaryA.jaipurFinishedStock, 0);
      expect(summaryA.combinedTotalStock, 530);
      expect(summaryA.transferDiscrepancy, 0);

      // Case B: Jaipur receives stock directly from supplier, Neemrana untouched
      final summaryB = ProductInventorySummary(
        product: sharedProduct,
        totalPacked: 500,
        totalNeemranaStockIn: 50,
        totalNeemranaSold: 20,
        totalJaipurStockIn: 100,
        totalJaipurSold: 15,
        totalDispatched: 0,
        totalReceived: 0,
      );

      expect(summaryB.neemranaFinishedStock, 530);
      expect(summaryB.jaipurFinishedStock, 85); // 100 - 15
      expect(summaryB.combinedTotalStock, 615); // 530 + 85
      expect(summaryB.transferDiscrepancy, 0);
    });

    test('9. Canonical Location IDs for Neemrana and Jaipur are preserved', () {
      expect(Location.neemranaId, '11111111-1111-1111-1111-111111111111');
      expect(Location.jaipurId, '22222222-2222-2222-2222-222222222222');
      expect(Location.neemranaId, isNot(equals(Location.jaipurId)));
    });
  });
}
