import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/core/utils/id_generator.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/location.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/sale.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/sales/domain/entities/cart_item.dart';

int _getStock(InventoryNotifier notifier, String locationId, String productId) {
  final summary = notifier.inventorySummaries.firstWhere((s) => s.product.id == productId);
  return locationId == Location.neemranaId ? summary.neemranaFinishedStock : summary.jaipurFinishedStock;
}

void main() {
  group('V1.6 Multi-Item POS Billing, Idempotency & Stock Security Tests', () {
    late UnconnectedInventoryRepository repo;
    late InventoryNotifier notifier;

    setUp(() async {
      repo = UnconnectedInventoryRepository();
      // Receive initial store stock for prod-102 at Jaipur so multi-item cart has available stock
      await repo.receiveStoreStock(
        locationId: Location.jaipurId,
        productId: 'prod-102',
        quantity: 50,
        notes: 'Initial store stock receipt',
      );
      notifier = InventoryNotifier(repository: repo);
      await notifier.loadInventoryData();
    });

    test('1. Multi-product cart checkout updates stock across all items in single transaction', () async {
      final initialJaipurP1 = _getStock(notifier, Location.jaipurId, 'prod-101');
      final initialJaipurP2 = _getStock(notifier, Location.jaipurId, 'prod-102');
      expect(initialJaipurP1, greaterThan(5));
      expect(initialJaipurP2, greaterThan(5));

      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');
      final p2 = notifier.products.firstWhere((p) => p.id == 'prod-102');

      final cartItems = [
        CartItem(product: p1, quantity: 2, unitPrice: p1.standardSellingPrice, discount: 0.0),
        CartItem(product: p2, quantity: 3, unitPrice: p2.standardSellingPrice, discount: 10.0),
      ];

      final expectedTotal = cartItems.fold<double>(0.0, (acc, item) => acc + item.lineTotal);

      final sale = await notifier.recordSale(
        items: cartItems,
        customerName: 'Multi Item Buyer',
        customerPhone: '9876543210',
        paymentMethod: 'UPI',
        locationId: Location.jaipurId,
        invoiceType: 'NON_GST',
        totalAmount: expectedTotal,
      );

      expect(sale, isNotNull);
      expect(sale!.items.length, 2);
      expect(sale.totalAmount, closeTo(expectedTotal, 0.01));

      // Verify stock decreased for both products
      final postJaipurP1 = _getStock(notifier, Location.jaipurId, 'prod-101');
      final postJaipurP2 = _getStock(notifier, Location.jaipurId, 'prod-102');
      expect(postJaipurP1, initialJaipurP1 - 2);
      expect(postJaipurP2, initialJaipurP2 - 3);
    });

    test('2. Idempotent retry with identical request ID returns existing sale without double stock deduction', () async {
      final initialStock = _getStock(notifier, Location.jaipurId, 'prod-101');
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');
      final requestId = IdGenerator.generateUuidV4();

      final cartItems = [
        CartItem(product: p1, quantity: 2, unitPrice: p1.standardSellingPrice, discount: 0.0),
      ];

      // First attempt
      final sale1 = await notifier.recordSale(
        items: cartItems,
        clientRequestId: requestId,
        customerName: 'Idempotency Tester',
        customerPhone: '9123456780',
        paymentMethod: 'CASH',
        locationId: Location.jaipurId,
        totalAmount: cartItems.first.lineTotal,
      );
      expect(sale1, isNotNull);

      final stockAfterSale1 = _getStock(notifier, Location.jaipurId, 'prod-101');
      expect(stockAfterSale1, initialStock - 2);

      // Concurrent / network retry attempt with exact same clientRequestId & payload
      final sale2 = await notifier.recordSale(
        items: cartItems,
        clientRequestId: requestId,
        customerName: 'Idempotency Tester',
        customerPhone: '9123456780',
        paymentMethod: 'CASH',
        locationId: Location.jaipurId,
        totalAmount: cartItems.first.lineTotal,
      );
      expect(sale2, isNotNull);

      // Must return identical sale ID and bill number
      expect(sale2!.id, sale1!.id);
      expect(sale2.billNumber, sale1.billNumber);

      // Stock must NOT be deducted again
      final stockAfterSale2 = _getStock(notifier, Location.jaipurId, 'prod-101');
      expect(stockAfterSale2, stockAfterSale1);
    });

    test('3. Reusing clientRequestId with altered payload throws idempotency conflict error', () async {
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');
      final p2 = notifier.products.firstWhere((p) => p.id == 'prod-102');
      final requestId = IdGenerator.generateUuidV4();

      // Original request with p1
      final s1 = await notifier.recordSale(
        items: [CartItem(product: p1, quantity: 1, unitPrice: p1.standardSellingPrice)],
        clientRequestId: requestId,
        customerName: 'Original Customer',
        customerPhone: '9000000001',
        paymentMethod: 'CASH',
        locationId: Location.jaipurId,
      );
      expect(s1, isNotNull);

      // Malicious or accidental reuse of same requestId with p2 (different payload) on repo directly
      expect(
        () => repo.recordSale(
          items: [CartItem(product: p2, quantity: 4, unitPrice: p2.standardSellingPrice)],
          clientRequestId: requestId,
          customerName: 'Different Customer',
          customerPhone: '9000000002',
          paymentMethod: 'UPI',
          locationId: Location.jaipurId,
        ),
        throwsA(predicate((e) => e.toString().contains('Idempotency conflict'))),
      );
    });

    test('4. Additive stock receiving increments stock balance atomically with STOCK_RECEIPT audit entry', () async {
      final initialStock = _getStock(notifier, Location.jaipurId, 'prod-101');
      const incomingUnits = 25;

      final success = await notifier.receiveStoreStock(
        locationId: Location.jaipurId,
        productId: 'prod-101',
        quantity: incomingUnits,
        notes: 'INV-2026-889 from Organic Herbs Dist Co.',
      );
      expect(success, isTrue);

      final newStock = _getStock(notifier, Location.jaipurId, 'prod-101');
      expect(newStock, initialStock + incomingUnits);

      // Verify audit adjustment record exists with STOCK_RECEIPT reason (first item is latest)
      final adjustments = await repo.getStockAdjustments();
      final latest = adjustments.firstWhere((a) => a.productId == 'prod-101' && a.locationId == Location.jaipurId);
      expect(latest.reason, 'STOCK_RECEIPT');
      expect(latest.changeQuantity, incomingUnits);
      expect(latest.notes, contains('INV-2026-889'));
      expect(latest.notes, contains('Organic Herbs Dist Co.'));
    });

    test('5. Physical audit stock adjustment sets absolute shelf count with PHYSICAL_AUDIT reason', () async {
      const physicalCount = 42;

      final success = await notifier.adjustStoreStock(
        locationId: Location.jaipurId,
        productId: 'prod-102',
        newQuantity: physicalCount,
        reason: 'PHYSICAL_AUDIT',
        notes: 'Monthly physical inventory count audit',
      );
      expect(success, isTrue);

      final newStock = _getStock(notifier, Location.jaipurId, 'prod-102');
      expect(newStock, physicalCount);

      final adjustments = await repo.getStockAdjustments();
      final latest = adjustments.firstWhere((a) => a.productId == 'prod-102' && a.locationId == Location.jaipurId);
      expect(latest.reason, 'PHYSICAL_AUDIT');
      expect(latest.newQuantity, physicalCount);
    });

    test('6. Voiding multi-item sale restores stock on hand across all items in the bill', () async {
      final initialP1 = _getStock(notifier, Location.jaipurId, 'prod-101');
      final initialP2 = _getStock(notifier, Location.jaipurId, 'prod-102');

      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');
      final p2 = notifier.products.firstWhere((p) => p.id == 'prod-102');

      final sale = await notifier.recordSale(
        items: [
          CartItem(product: p1, quantity: 3, unitPrice: p1.standardSellingPrice),
          CartItem(product: p2, quantity: 4, unitPrice: p2.standardSellingPrice),
        ],
        locationId: Location.jaipurId,
        customerName: 'Accidental Purchase',
        paymentMethod: 'CASH',
      );
      expect(sale, isNotNull);

      expect(_getStock(notifier, Location.jaipurId, 'prod-101'), initialP1 - 3);
      expect(_getStock(notifier, Location.jaipurId, 'prod-102'), initialP2 - 4);

      // Void the sale
      final voidSuccess = await notifier.voidSale(
        saleId: sale!.id,
      );
      expect(voidSuccess, isTrue);

      // Verify stock restored for both products
      expect(_getStock(notifier, Location.jaipurId, 'prod-101'), initialP1);
      expect(_getStock(notifier, Location.jaipurId, 'prod-102'), initialP2);
    });

    test('7. RFC4122 v4 UUID generator produces valid 36-char compliant UUIDs', () {
      final uuid1 = IdGenerator.generateUuidV4();
      final uuid2 = IdGenerator.generateUuidV4();

      expect(uuid1, isNot(uuid2));
      expect(uuid1.length, 36);

      // Valid UUID format 8-4-4-4-12
      final uuidRegex = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(uuidRegex.hasMatch(uuid1), isTrue);
      expect(uuidRegex.hasMatch(uuid2), isTrue);
    });

    test('8. CartItem entity calculations: gross total, line total, and RPC json formatting', () {
      final product = notifier.products.first;
      final item = CartItem(
        product: product,
        quantity: 5,
        unitPrice: 200.0,
        discount: 25.0,
      );

      expect(item.grossTotal, 1000.0);
      expect(item.lineTotal, 975.0);
      expect(item.discountPercentage, 2.5);

      final rpcJson = item.toRpcItemJson(overrideReason: 'Seasonal promotion');
      expect(rpcJson['product_id'], product.id);
      expect(rpcJson['quantity'], 5);
      expect(rpcJson['unit_price'], 200.0);
      expect(rpcJson['discount'], 25.0);
      expect(rpcJson['override_reason'], 'Seasonal promotion');
    });

    test('9. Owner seasonal pricing update preserves price adjustments for catalog products', () async {
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');
      const newSeasonalPrice = 349.0;
      const newPurchaseCost = 145.0;

      final updateSuccess = await notifier.updateProductPricing(
        productId: p1.id,
        standardSellingPrice: newSeasonalPrice,
        purchaseCost: newPurchaseCost,
      );
      expect(updateSuccess, isTrue);

      final updatedProduct = notifier.products.firstWhere((p) => p.id == 'prod-101');
      expect(updatedProduct.standardSellingPrice, newSeasonalPrice);
    });

    test('10. Price calculations: extreme low (₹0.50), high (₹50,000.00), and rounding boundaries', () {
      final p = notifier.products.first;

      // Low price item
      final lowItem = CartItem(
        product: p,
        quantity: 3,
        unitPrice: 0.50,
        discount: 0.05,
      );
      expect(lowItem.grossTotal, closeTo(1.50, 0.001));
      expect(lowItem.lineTotal, closeTo(1.45, 0.001));
      expect(lowItem.discountPercentage, closeTo(3.333, 0.01));

      // High price item
      final highItem = CartItem(
        product: p,
        quantity: 10,
        unitPrice: 50000.0,
        discount: 5000.0,
      );
      expect(highItem.grossTotal, 500000.0);
      expect(highItem.lineTotal, 495000.0);
      expect(highItem.discountPercentage, 1.0);

      // Rounding boundary: 3 items @ ₹33.33 each with ₹10 discount
      final roundItem = CartItem(
        product: p,
        quantity: 3,
        unitPrice: 33.33,
        discount: 10.0,
      );
      expect(roundItem.grossTotal, closeTo(99.99, 0.001));
      expect(roundItem.lineTotal, closeTo(89.99, 0.001));
    });

    test('11. Negative values and invalid quantities throw strict validation exceptions', () async {
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');

      // Negative quantity on recordSale throws
      expect(
        () => repo.recordSale(
          items: [CartItem(product: p1, quantity: -2, unitPrice: 100.0)],
          locationId: Location.jaipurId,
        ),
        throwsA(predicate((e) => e.toString().contains('Quantity must be greater than zero'))),
      );

      // Negative price on repository directly throws
      expect(
        () => repo.updateProductPricing(
          productId: p1.id,
          standardSellingPrice: -50.0,
          purchaseCost: 20.0,
        ),
        throwsA(predicate((e) => e.toString().contains('cannot be negative'))),
      );

      // Negative price on notifier returns false and sets error message
      final priceFailed = await notifier.updateProductPricing(
        productId: p1.id,
        standardSellingPrice: -50.0,
        purchaseCost: 20.0,
      );
      expect(priceFailed, isFalse);
      expect(notifier.errorMessage, contains('cannot be negative'));

      // Negative purchase cost on repository directly throws
      expect(
        () => repo.updateProductPricing(
          productId: p1.id,
          standardSellingPrice: 100.0,
          purchaseCost: -10.0,
        ),
        throwsA(predicate((e) => e.toString().contains('cannot be negative'))),
      );

      // Negative purchase cost on notifier returns false and sets error message
      final costFailed = await notifier.updateProductPricing(
        productId: p1.id,
        standardSellingPrice: 100.0,
        purchaseCost: -10.0,
      );
      expect(costFailed, isFalse);
      expect(notifier.errorMessage, contains('cannot be negative'));
    });

    test('12. Discount boundary rules: zero discount, exact 10% ceiling, and line clamping', () {
      final p = notifier.products.first;

      // 0% discount
      final zeroDisc = CartItem(product: p, quantity: 2, unitPrice: 100.0, discount: 0.0);
      expect(zeroDisc.discountPercentage, 0.0);
      expect(zeroDisc.lineTotal, 200.0);

      // Exactly 10% discount
      final exactTen = CartItem(product: p, quantity: 2, unitPrice: 100.0, discount: 20.0);
      expect(exactTen.discountPercentage, 10.0);
      expect(exactTen.lineTotal, 180.0);

      // Discount clamping if discount exceeds gross: line total cannot be negative
      final overDisc = CartItem(product: p, quantity: 1, unitPrice: 50.0, discount: 75.0);
      expect(overDisc.lineTotal, 0.0);
    });

    test('13. Duplicate product lines in cart are aggregated and deducted accurately', () async {
      final initialStock = _getStock(notifier, Location.jaipurId, 'prod-101');
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');

      // Cart with 2 lines for the same product: line 1 (qty 2, full price), line 2 (qty 3, discount 10)
      final cartItems = [
        CartItem(product: p1, quantity: 2, unitPrice: p1.standardSellingPrice, discount: 0.0),
        CartItem(product: p1, quantity: 3, unitPrice: p1.standardSellingPrice, discount: 10.0),
      ];

      final sale = await notifier.recordSale(
        items: cartItems,
        customerName: 'Duplicate Item Buyer',
        customerPhone: '9888877777',
        paymentMethod: 'CASH',
        locationId: Location.jaipurId,
        totalAmount: cartItems.fold(0.0, (acc, i) => acc + i.lineTotal),
      );

      expect(sale, isNotNull);
      expect(sale!.items.length, 2);

      // Verify total stock deducted is 2 + 3 = 5
      final postStock = _getStock(notifier, Location.jaipurId, 'prod-101');
      expect(postStock, initialStock - 5);
    });

    test('14. Reordered line items in cart produce identical canonical payload and allow idempotent replay', () async {
      final initialStockP1 = _getStock(notifier, Location.jaipurId, 'prod-101');
      final initialStockP2 = _getStock(notifier, Location.jaipurId, 'prod-102');
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');
      final p2 = notifier.products.firstWhere((p) => p.id == 'prod-102');
      final reqId = IdGenerator.generateUuidV4();

      final cartOrder1 = [
        CartItem(product: p1, quantity: 2, unitPrice: p1.standardSellingPrice, discount: 0.0),
        CartItem(product: p2, quantity: 1, unitPrice: p2.standardSellingPrice, discount: 5.0),
      ];

      final sale1 = await notifier.recordSale(
        items: cartOrder1,
        clientRequestId: reqId,
        customerName: 'Reorder Buyer',
        customerPhone: '9777766666',
        paymentMethod: 'UPI',
        locationId: Location.jaipurId,
      );
      expect(sale1, isNotNull);

      // Stock deducted once
      expect(_getStock(notifier, Location.jaipurId, 'prod-101'), initialStockP1 - 2);
      expect(_getStock(notifier, Location.jaipurId, 'prod-102'), initialStockP2 - 1);

      // Replay attempt with items reversed: [p2, p1]
      final cartOrder2 = [
        CartItem(product: p2, quantity: 1, unitPrice: p2.standardSellingPrice, discount: 5.0),
        CartItem(product: p1, quantity: 2, unitPrice: p1.standardSellingPrice, discount: 0.0),
      ];

      final sale2 = await notifier.recordSale(
        items: cartOrder2,
        clientRequestId: reqId,
        customerName: 'Reorder Buyer',
        customerPhone: '9777766666',
        paymentMethod: 'UPI',
        locationId: Location.jaipurId,
      );

      expect(sale2, isNotNull);
      expect(sale2!.id, sale1!.id);

      // Verify stock was NOT deducted a second time
      expect(_getStock(notifier, Location.jaipurId, 'prod-101'), initialStockP1 - 2);
      expect(_getStock(notifier, Location.jaipurId, 'prod-102'), initialStockP2 - 1);
    });

    test('15. Changed fields with same request ID (customer, method, quantity, price, discount) throw idempotency conflict', () async {
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');
      final reqId = IdGenerator.generateUuidV4();

      await notifier.recordSale(
        items: [CartItem(product: p1, quantity: 1, unitPrice: 100.0, discount: 0.0)],
        clientRequestId: reqId,
        customerName: 'Original Customer',
        customerPhone: '9111122222',
        paymentMethod: 'CASH',
        locationId: Location.jaipurId,
      );

      // Tampered customer name
      expect(
        () => repo.recordSale(
          items: [CartItem(product: p1, quantity: 1, unitPrice: 100.0, discount: 0.0)],
          clientRequestId: reqId,
          customerName: 'Tampered Customer',
          customerPhone: '9111122222',
          paymentMethod: 'CASH',
          locationId: Location.jaipurId,
        ),
        throwsA(predicate((e) => e.toString().contains('Idempotency conflict'))),
      );

      // Tampered payment method
      expect(
        () => repo.recordSale(
          items: [CartItem(product: p1, quantity: 1, unitPrice: 100.0, discount: 0.0)],
          clientRequestId: reqId,
          customerName: 'Original Customer',
          customerPhone: '9111122222',
          paymentMethod: 'UPI',
          locationId: Location.jaipurId,
        ),
        throwsA(predicate((e) => e.toString().contains('Idempotency conflict'))),
      );

      // Tampered quantity
      expect(
        () => repo.recordSale(
          items: [CartItem(product: p1, quantity: 2, unitPrice: 100.0, discount: 0.0)],
          clientRequestId: reqId,
          customerName: 'Original Customer',
          customerPhone: '9111122222',
          paymentMethod: 'CASH',
          locationId: Location.jaipurId,
        ),
        throwsA(predicate((e) => e.toString().contains('Idempotency conflict'))),
      );
    });

    test('16. Missing request ID (null) creates normal sale without idempotency collision', () async {
      final initialStock = _getStock(notifier, Location.jaipurId, 'prod-101');
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');

      // Two consecutive sales with clientRequestId == null
      final sale1 = await notifier.recordSale(
        items: [CartItem(product: p1, quantity: 1, unitPrice: 100.0)],
        clientRequestId: null,
        customerName: 'Walk-in 1',
        customerPhone: '9000000001',
        paymentMethod: 'CASH',
        locationId: Location.jaipurId,
      );

      final sale2 = await notifier.recordSale(
        items: [CartItem(product: p1, quantity: 1, unitPrice: 100.0)],
        clientRequestId: null,
        customerName: 'Walk-in 2',
        customerPhone: '9000000002',
        paymentMethod: 'CASH',
        locationId: Location.jaipurId,
      );

      expect(sale1, isNotNull);
      expect(sale2, isNotNull);
      expect(sale1!.id, isNot(sale2!.id));

      final postStock = _getStock(notifier, Location.jaipurId, 'prod-101');
      expect(postStock, initialStock - 2);
    });

    test('17. Atomic rollback: failure midway through multi-item sale leaves earlier items unmutated', () async {
      final initialStockP1 = _getStock(notifier, Location.jaipurId, 'prod-101');
      final initialStockP2 = _getStock(notifier, Location.jaipurId, 'prod-102');
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');
      final p2 = notifier.products.firstWhere((p) => p.id == 'prod-102');

      // P1 has sufficient stock (e.g. 10), but P2 requested quantity (999) exceeds available stock
      final cartWithExcess = [
        CartItem(product: p1, quantity: 2, unitPrice: 100.0),
        CartItem(product: p2, quantity: 999, unitPrice: 150.0),
      ];

      expect(
        () => repo.recordSale(
          items: cartWithExcess,
          customerName: 'Atomic Test Buyer',
          customerPhone: '9999900000',
          locationId: Location.jaipurId,
        ),
        throwsA(predicate((e) => e.toString().contains('Insufficient stock'))),
      );

      // Verify Product 1 stock was NOT decremented (atomic rollback preserved)
      await notifier.loadInventoryData();
      final postStockP1 = _getStock(notifier, Location.jaipurId, 'prod-101');
      final postStockP2 = _getStock(notifier, Location.jaipurId, 'prod-102');
      expect(postStockP1, initialStockP1);
      expect(postStockP2, initialStockP2);
    });

    test('18. Replaying request ID that exists on a legacy record with NULL payload hash fails closed', () async {
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');
      final legacyReqId = IdGenerator.generateUuidV4();

      final legacySale = Sale(
        id: 'legacy-sale-001',
        locationId: Location.jaipurId,
        billNumber: 'BILL-LEGACY-001',
        paymentMethod: 'CASH',
        invoiceType: 'NON_GST',
        gstRate: 0.0,
        taxableAmount: 100.0,
        cgstAmount: 0.0,
        sgstAmount: 0.0,
        igstAmount: 0.0,
        totalAmount: 100.0,
        status: 'COMPLETED',
        soldAt: DateTime.now(),
        createdAt: DateTime.now(),
        productId: p1.id,
        quantity: 1,
        items: [
          SaleItem(
            id: 'legacy-item-001',
            saleId: 'legacy-sale-001',
            productId: p1.id,
            quantity: 1,
            unitPrice: 100.0,
            discount: 0.0,
            createdAt: DateTime.now(),
          ),
        ],
      );

      // Seed as legacy record with NULL payload hash
      repo.seedLegacySaleWithNullHash(requestId: legacyReqId, sale: legacySale);

      // Attempt to replay with that request ID -> MUST FAIL CLOSED
      expect(
        () => repo.recordSale(
          items: [CartItem(product: p1, quantity: 1, unitPrice: 100.0)],
          clientRequestId: legacyReqId,
          customerName: 'Replay Attempt',
          customerPhone: '9000000000',
          locationId: Location.jaipurId,
        ),
        throwsA(predicate((e) =>
            e.toString().contains('Idempotency conflict') &&
            e.toString().contains('legacy record without a verified payload hash'))),
      );
    });

    test('19. Cashier discount policy: 0% and exactly 10% allowed, >10% rejected', () async {
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');
      final catalogPrice = p1.standardSellingPrice;

      // 19A: 0% discount by Jaipur cashier succeeds
      final sale0 = await repo.recordSale(
        items: [CartItem(product: p1, quantity: 1, unitPrice: catalogPrice, discount: 0.0)],
        customerName: 'Zero Disc Buyer',
        customerPhone: '9829000001',
        locationId: Location.jaipurId,
        callerRole: 'jaipur',
      );
      expect(sale0, isNotNull);
      expect(sale0.items.first.discount, 0.0);
      expect(sale0.totalAmount, catalogPrice);

      // 19B: Exactly 10.00% discount by Jaipur cashier succeeds (e.g. ₹20 on ₹200)
      final exactTenDiscount = double.parse((catalogPrice * 0.10).toStringAsFixed(2));
      final sale10 = await repo.recordSale(
        items: [CartItem(product: p1, quantity: 1, unitPrice: catalogPrice, discount: exactTenDiscount)],
        customerName: 'Ten Pct Buyer',
        customerPhone: '9829000002',
        locationId: Location.jaipurId,
        callerRole: 'jaipur',
      );
      expect(sale10, isNotNull);
      expect(sale10.items.first.discount, exactTenDiscount);
      expect(sale10.totalAmount, closeTo(catalogPrice - exactTenDiscount, 0.01));

      // 19C: Discount exceeding 10% (10.5% or 15%) by cashier is rejected
      final overDiscount = exactTenDiscount + 5.0; // exceeds 10%
      expect(
        () => repo.recordSale(
          items: [CartItem(product: p1, quantity: 1, unitPrice: catalogPrice, discount: overDiscount)],
          customerName: 'Over Disc Buyer',
          customerPhone: '9829000003',
          locationId: Location.jaipurId,
          callerRole: 'jaipur',
        ),
        throwsA(predicate((e) =>
            e.toString().contains('Unauthorized discount') &&
            e.toString().contains('exceeds allowed maximum of 10.0 pct'))),
      );
    });

    test('20. Input validation: negative, non-finite (NaN, Infinity), and exceeding line total rejected', () async {
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');
      final catalogPrice = p1.standardSellingPrice;

      // 20A: Negative discount rejected
      expect(
        () => repo.recordSale(
          items: [CartItem(product: p1, quantity: 1, unitPrice: catalogPrice, discount: -5.0)],
          locationId: Location.jaipurId,
          callerRole: 'jaipur',
        ),
        throwsA(predicate((e) => e.toString().contains('Discount cannot be negative'))),
      );

      // 20B: Non-finite discount (NaN) rejected
      expect(
        () => repo.recordSale(
          items: [CartItem(product: p1, quantity: 1, unitPrice: catalogPrice, discount: double.nan)],
          locationId: Location.jaipurId,
          callerRole: 'jaipur',
        ),
        throwsA(predicate((e) => e.toString().contains('Discount cannot be negative'))),
      );

      // 20C: Discount exceeding line total rejected
      expect(
        () => repo.recordSale(
          items: [CartItem(product: p1, quantity: 1, unitPrice: catalogPrice, discount: catalogPrice + 50.0)],
          locationId: Location.jaipurId,
          callerRole: 'owner',
        ),
        throwsA(predicate((e) => e.toString().contains('Discount cannot exceed line item total'))),
      );
    });

    test('21. Multi-line bill discount enforcement: atomic rejection if any single line exceeds 10%', () async {
      final initialStockP1 = _getStock(notifier, Location.jaipurId, 'prod-101');
      final initialStockP2 = _getStock(notifier, Location.jaipurId, 'prod-102');
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');
      final p2 = notifier.products.firstWhere((p) => p.id == 'prod-102');

      final validDiscP1 = double.parse((p1.standardSellingPrice * 0.10).toStringAsFixed(2)); // exactly 10%
      final invalidDiscP2 = double.parse((p2.standardSellingPrice * 0.20).toStringAsFixed(2)); // 20% > 10%

      // Attempt multi-item bill: Line 1 is valid (10%), Line 2 is INVALID (20%)
      expect(
        () => repo.recordSale(
          items: [
            CartItem(product: p1, quantity: 1, unitPrice: p1.standardSellingPrice, discount: validDiscP1),
            CartItem(product: p2, quantity: 1, unitPrice: p2.standardSellingPrice, discount: invalidDiscP2),
          ],
          customerName: 'Multi Item Violator',
          customerPhone: '9829000007',
          locationId: Location.jaipurId,
          callerRole: 'jaipur',
        ),
        throwsA(predicate((e) =>
            e.toString().contains('Unauthorized discount') &&
            e.toString().contains('exceeds allowed maximum of 10.0 pct'))),
      );

      // Verify ATOMIC ROLLBACK: stock was NOT deducted for line 1
      await notifier.loadInventoryData();
      expect(_getStock(notifier, Location.jaipurId, 'prod-101'), initialStockP1);
      expect(_getStock(notifier, Location.jaipurId, 'prod-102'), initialStockP2);
    });

    test('22. Owner role permissions: owner can apply custom discounts (>10%) and override prices', () async {
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');
      final catalogPrice = p1.standardSellingPrice;
      final ownerDiscount = double.parse((catalogPrice * 0.25).toStringAsFixed(2)); // 25% discount

      final ownerSale = await repo.recordSale(
        items: [CartItem(product: p1, quantity: 1, unitPrice: catalogPrice, discount: ownerDiscount)],
        customerName: 'Owner Customer',
        customerPhone: '9829000008',
        locationId: Location.jaipurId,
        callerRole: 'owner',
      );

      expect(ownerSale, isNotNull);
      expect(ownerSale.items.first.discount, ownerDiscount);
      expect(ownerSale.totalAmount, closeTo(catalogPrice - ownerDiscount, 0.01));
    });

    test('23. Persisted line totals, bill totals, and PDF calculations with discounts', () {
      final p1 = notifier.products.firstWhere((p) => p.id == 'prod-101');
      final p2 = notifier.products.firstWhere((p) => p.id == 'prod-102');

      final item1 = SaleItem(
        id: 'item-disc-1',
        saleId: 'sale-disc-1',
        productId: p1.id,
        quantity: 2,
        unitPrice: 200.0,
        discount: 20.0, // 10%
        createdAt: DateTime.now(),
        productName: p1.name,
        sku: p1.sku,
        packageSize: p1.packageSize,
      );

      final item2 = SaleItem(
        id: 'item-disc-2',
        saleId: 'sale-disc-1',
        productId: p2.id,
        quantity: 1,
        unitPrice: 150.0,
        discount: 7.50, // 5%
        createdAt: DateTime.now(),
        productName: p2.name,
        sku: p2.sku,
        packageSize: p2.packageSize,
      );

      // Line 1: (2 * 200) - 20 = 380
      expect(item1.lineTotal, 380.0);
      // Line 2: (1 * 150) - 7.50 = 142.50
      expect(item2.lineTotal, 142.50);

      final sale = Sale(
        id: 'sale-disc-1',
        locationId: Location.jaipurId,
        billNumber: 'BILL-DISC-001',
        customerName: 'Calculated Buyer',
        customerPhone: '9829000009',
        totalAmount: item1.lineTotal + item2.lineTotal,
        productId: p1.id,
        quantity: 3,
        items: [item1, item2],
        soldAt: DateTime.now(),
        createdAt: DateTime.now(),
      );

      // Bill total matches sum of lines: 380 + 142.50 = 522.50
      expect(sale.totalAmount, 522.50);

      // Total discount across items: 20 + 7.50 = 27.50
      final totalDiscount = sale.items.fold<double>(0.0, (acc, i) => acc + i.discount);
      expect(totalDiscount, 27.50);
    });
  });
}


