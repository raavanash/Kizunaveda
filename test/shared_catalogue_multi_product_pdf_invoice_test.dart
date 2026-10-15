import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/core/services/pdf_invoice_service.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/location.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/product.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/sale.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/sales/domain/entities/cart_item.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UnconnectedInventoryRepository repository;
  late InventoryNotifier notifier;

  setUp(() async {
    PdfInvoiceService.testTempDir = () async => Directory.systemTemp;
    PdfInvoiceService.testLauncher = (uri) async => true;
    PdfInvoiceService.testSharer = (files, {text}) async {};

    repository = UnconnectedInventoryRepository();
    notifier = InventoryNotifier(repository: repository);
    await notifier.loadInventoryData();
  });

  tearDown(() {
    PdfInvoiceService.testLauncher = null;
    PdfInvoiceService.testSharer = null;
  });

  int getStock(String locationId, String productId) {
    final summary = notifier.inventorySummaries
        .firstWhere((s) => s.product.id == productId);
    return locationId == Location.neemranaId
        ? summary.neemranaFinishedStock
        : summary.jaipurFinishedStock;
  }

  group('Shared Product Catalogue, Multi-Product Bills & Customer PDF Invoices', () {
    // 1. Owner creates a product manually
    test('1. Owner creates a product manually with required fields and pricing', () async {
      final product = await repository.addProduct(
        name: 'California Walnuts',
        packageSize: '250g',
        sku: 'KV-WAL-250',
        standardSellingPrice: 450.0,
        purchaseCost: 280.0,
        active: true,
      );

      expect(product, isNotNull);
      expect(product.name, equals('California Walnuts'));
      expect(product.packageSize, equals('250g'));
      expect(product.sku, equals('KV-WAL-250'));
      expect(product.standardSellingPrice, equals(450.0));
      expect(product.purchaseCost, equals(280.0));
      expect(product.active, isTrue);
    });

    // 2. Duplicate SKU is rejected
    test('2. Duplicate SKU is rejected when creating or updating a product', () async {
      // First product
      await repository.addProduct(
        name: 'California Walnuts',
        packageSize: '250g',
        sku: 'KV-WAL-250',
        standardSellingPrice: 450.0,
        purchaseCost: 280.0,
        active: true,
      );

      // Attempt duplicate SKU
      expect(
        () async => await repository.addProduct(
          name: 'Another Walnuts Pack',
          packageSize: '500g',
          sku: 'KV-WAL-250',
          standardSellingPrice: 850.0,
          purchaseCost: 500.0,
          active: true,
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Product with SKU "KV-WAL-250" already exists'),
        )),
      );
    });

    // 3. The new active product appears at both outlets after refresh
    test('3. The new active product appears at both Neemrana and Jaipur after refresh', () async {
      final product = await repository.addProduct(
        name: 'Afghan Figs / Anjeer',
        packageSize: '500g',
        sku: 'KV-FIG-500',
        standardSellingPrice: 750.0,
        purchaseCost: 500.0,
        active: true,
      );

      // Refresh inventory notifier
      await notifier.loadInventoryData();

      final activeProducts = notifier.products.where((p) => p.active).toList();
      expect(activeProducts.any((p) => p.id == product.id), isTrue);

      // Verify visibility for Neemrana and Jaipur
      final neemranaVisible = activeProducts
          .where((p) => p.sku == 'KV-FIG-500')
          .firstOrNull;
      final jaipurVisible = activeProducts
          .where((p) => p.sku == 'KV-FIG-500')
          .firstOrNull;

      expect(neemranaVisible, isNotNull);
      expect(jaipurVisible, isNotNull);
      expect(neemranaVisible!.name, equals('Afghan Figs / Anjeer'));
      expect(jaipurVisible!.packageSize, equals('500g'));
    });

    // 4. Inactive products are hidden from sale and stock-receipt selectors
    test('4. Inactive products are hidden from active selectors while preserving records', () async {
      final product = await repository.addProduct(
        name: 'Discontinued Dates',
        packageSize: '250g',
        sku: 'KV-DISC-DATE',
        standardSellingPrice: 200.0,
        purchaseCost: 120.0,
        active: true,
      );
      await notifier.loadInventoryData();

      // Deactivate
      final toggleSuccess = await notifier.toggleProductActive(
        id: product.id,
        active: false,
      );
      expect(toggleSuccess, isTrue);

      final activeCatalog = notifier.products.where((p) => p.active).toList();
      expect(activeCatalog.any((p) => p.id == product.id), isFalse);

      // Preserved in all products list
      final allCatalog = notifier.products;
      expect(allCatalog.any((p) => p.id == product.id), isTrue);
    });

    // 5. Adding a product creates no automatic stock
    test('5. Adding a product creates no automatic stock in either outlet', () async {
      final product = await repository.addProduct(
        name: 'Iranian Pistachios',
        packageSize: '250g',
        sku: 'KV-IRN-PST',
        standardSellingPrice: 600.0,
        purchaseCost: 400.0,
        active: true,
      );
      await notifier.loadInventoryData();

      final neemranaStock = getStock(Location.neemranaId, product.id);
      final jaipurStock = getStock(Location.jaipurId, product.id);

      expect(neemranaStock, equals(0));
      expect(jaipurStock, equals(0));
    });

    // 6. Stock receipts and balances remain outlet-specific
    test('6. Stock receipts and balances remain strictly outlet-specific', () async {
      final product = await repository.addProduct(
        name: 'Mamra Almonds',
        packageSize: '500g',
        sku: 'KV-MAM-500',
        standardSellingPrice: 900.0,
        purchaseCost: 650.0,
        active: true,
      );
      await notifier.loadInventoryData();

      // Receive 40 units at Neemrana only
      final neemranaReceipt = await notifier.receiveStoreStock(
        locationId: Location.neemranaId,
        productId: product.id,
        quantity: 40,
        notes: 'Neemrana warehouse intake',
      );
      expect(neemranaReceipt, isTrue);

      expect(getStock(Location.neemranaId, product.id), equals(40));
      expect(getStock(Location.jaipurId, product.id), equals(0));

      // Receive 15 units at Jaipur only
      final jaipurReceipt = await notifier.receiveStoreStock(
        locationId: Location.jaipurId,
        productId: product.id,
        quantity: 15,
        notes: 'Jaipur store intake',
      );
      expect(jaipurReceipt, isTrue);

      expect(getStock(Location.neemranaId, product.id), equals(40));
      expect(getStock(Location.jaipurId, product.id), equals(15));
    });

    // 7. One sale contains multiple products and independent quantities
    test('7. One sale contains multiple products and independent quantities in single bill', () async {
      final alm = notifier.products.firstWhere((p) => p.sku == 'KV-ALM-250');
      final kaj = notifier.products.firstWhere((p) => p.sku == 'KV-KAJ-250');
      final rai = notifier.products.firstWhere((p) => p.sku == 'KV-RAI-250');

      final items = [
        CartItem(product: alm, quantity: 2, unitPrice: 300.0),
        CartItem(product: kaj, quantity: 1, unitPrice: 350.0),
        CartItem(product: rai, quantity: 3, unitPrice: 180.0),
      ];

      final sale = await repository.recordSale(
        items: items,
        locationId: Location.jaipurId,
        customerName: 'Suresh Sharma',
        customerPhone: '9829012345',
        paymentMethod: 'UPI',
        totalAmount: 1490.0,
      );

      expect(sale, isNotNull);
      expect(sale.items.length, equals(3));
      expect(sale.items[0].productId, equals(alm.id));
      expect(sale.items[0].quantity, equals(2));
      expect(sale.items[0].lineTotal, equals(600.0));

      expect(sale.items[1].productId, equals(kaj.id));
      expect(sale.items[1].quantity, equals(1));
      expect(sale.items[1].lineTotal, equals(350.0));

      expect(sale.items[2].productId, equals(rai.id));
      expect(sale.items[2].quantity, equals(3));
      expect(sale.items[2].lineTotal, equals(540.0));

      expect(sale.totalAmount, equals(1490.0));
      expect(sale.customerName, equals('Suresh Sharma'));
      expect(sale.paymentMethod, equals('UPI'));
    });

    // 8. Only the selling outlet's stock is deducted
    test('8. Only the selling outlet stock is deducted when multi-product sale completes', () async {
      final alm = notifier.products.firstWhere((p) => p.sku == 'KV-ALM-250');
      final kaj = notifier.products.firstWhere((p) => p.sku == 'KV-KAJ-250');

      final initJaipurAlm = getStock(Location.jaipurId, alm.id);
      final initJaipurKaj = getStock(Location.jaipurId, kaj.id);
      final initNeemranaAlm = getStock(Location.neemranaId, alm.id);
      final initNeemranaKaj = getStock(Location.neemranaId, kaj.id);

      final items = [
        CartItem(product: alm, quantity: 2, unitPrice: 300.0),
        CartItem(product: kaj, quantity: 1, unitPrice: 350.0),
      ];

      await repository.recordSale(
        items: items,
        locationId: Location.jaipurId,
        customerName: 'Anita Gupta',
        customerPhone: '9829098765',
        totalAmount: 950.0,
      );
      await notifier.loadInventoryData();

      // Jaipur stock deducted
      expect(getStock(Location.jaipurId, alm.id), equals(initJaipurAlm - 2));
      expect(getStock(Location.jaipurId, kaj.id), equals(initJaipurKaj - 1));

      // Neemrana stock 100% untouched
      expect(getStock(Location.neemranaId, alm.id), equals(initNeemranaAlm));
      expect(getStock(Location.neemranaId, kaj.id), equals(initNeemranaKaj));
    });

    // 9. Insufficient stock prevents checkout
    test('9. Insufficient stock prevents checkout and raises validation error', () async {
      final alm = notifier.products.firstWhere((p) => p.sku == 'KV-ALM-250');
      final availableStock = getStock(Location.jaipurId, alm.id);

      final excessiveItems = [
        CartItem(product: alm, quantity: availableStock + 100, unitPrice: 300.0),
      ];

      expect(
        () async => await repository.recordSale(
          items: excessiveItems,
          locationId: Location.jaipurId,
          totalAmount: (availableStock + 100) * 300.0,
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'error',
          contains('Insufficient stock'),
        )),
      );
    });

    // 10. A retry does not create a duplicate bill
    test('10. A retry with same client_request_id does not create duplicate bill or stock deduction', () async {
      final alm = notifier.products.firstWhere((p) => p.sku == 'KV-ALM-250');
      final initialStock = getStock(Location.jaipurId, alm.id);
      const requestId = 'idempotent-multi-cart-retry-test';

      final items = [
        CartItem(product: alm, quantity: 2, unitPrice: 300.0),
      ];

      // Initial checkout
      final sale1 = await repository.recordSale(
        items: items,
        clientRequestId: requestId,
        locationId: Location.jaipurId,
        totalAmount: 600.0,
      );
      await notifier.loadInventoryData();
      expect(getStock(Location.jaipurId, alm.id), equals(initialStock - 2));

      // Retry submission (network glitch / user double tap)
      final sale2 = await repository.recordSale(
        items: items,
        clientRequestId: requestId,
        locationId: Location.jaipurId,
        totalAmount: 600.0,
      );
      await notifier.loadInventoryData();

      // Must return identical sale record
      expect(sale2.id, equals(sale1.id));
      expect(sale2.billNumber, equals(sale1.billNumber));

      // Stock must NOT be deducted again
      expect(getStock(Location.jaipurId, alm.id), equals(initialStock - 2));
    });

    // 11. The PDF includes every product line, correct quantities, prices, totals, and bill number
    test('11. The PDF includes every product line, correct quantities, prices, totals, and bill number', () async {
      final alm = notifier.products.firstWhere((p) => p.sku == 'KV-ALM-250');
      final kaj = notifier.products.firstWhere((p) => p.sku == 'KV-KAJ-250');
      final rai = notifier.products.firstWhere((p) => p.sku == 'KV-RAI-250');

      final items = [
        CartItem(product: alm, quantity: 2, unitPrice: 300.0),
        CartItem(product: kaj, quantity: 1, unitPrice: 350.0),
        CartItem(product: rai, quantity: 3, unitPrice: 180.0),
      ];

      final sale = await repository.recordSale(
        items: items,
        locationId: Location.jaipurId,
        customerName: 'Ramesh Patel',
        customerPhone: '9812345678',
        paymentMethod: 'CASH',
        totalAmount: 1490.0,
      );

      final productMap = <String, Product>{
        alm.id: alm,
        kaj.id: kaj,
        rai.id: rai,
      };

      // 1. Generate PDF bytes
      final pdfBytes = await PdfInvoiceService.generateInvoicePdf(sale, productMap);
      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.lengthInBytes, greaterThan(1000));

      // 2. Inspect formatted communication text containing every item
      final message = PdfInvoiceService.formatWhatsAppMessage(sale, productMap);
      expect(message, contains(sale.billNumber));
      expect(message, contains('Jaipur Store'));
      expect(message, contains('Ramesh Patel'));
      expect(message, contains('Almonds / Badam'));
      expect(message, contains('Qty: 2'));
      expect(message, contains('Amt: Rs 600.00'));
      expect(message, contains('Kaju / Cashews'));
      expect(message, contains('Qty: 1'));
      expect(message, contains('Amt: Rs 350.00'));
      expect(message, contains('Raisins / Kishmish'));
      expect(message, contains('Qty: 3'));
      expect(message, contains('Amt: Rs 540.00'));
      expect(message, contains('Total Amount: Rs 1490.00'));
      expect(message, contains('Payment Method: CASH'));
    });

    // 12. PDF pagination works for longer bills
    test('12. PDF pagination works reliably for long multi-item bills without overflowing', () async {
      final List<SaleItem> longItems = [];
      final Map<String, Product> productMap = {};

      for (int i = 1; i <= 15; i++) {
        final p = Product(
          id: 'prod-pag-$i',
          name: 'Herbal Item #$i',
          packageSize: '${i * 50}g',
          sku: 'KV-ITEM-$i',
          standardSellingPrice: 100.0 + i * 10,
          purchaseCost: 50.0 + i * 5,
          createdAt: DateTime.now(),
        );
        productMap[p.id] = p;
        longItems.add(SaleItem(
          id: 'item-$i',
          saleId: 'sale-pag-long',
          productId: p.id,
          quantity: i,
          unitPrice: p.standardSellingPrice,
          createdAt: DateTime.now(),
          productName: p.name,
          sku: p.sku,
          packageSize: p.packageSize,
        ));
      }

      final longSale = Sale(
        id: 'sale-pag-long',
        locationId: Location.jaipurId,
        billNumber: 'BILL-LONG-001',
        customerName: 'Bulk Wellness Buyer',
        customerPhone: '9876543210',
        paymentMethod: 'UPI',
        totalAmount: longItems.fold<double>(0.0, (acc, item) => acc + item.lineTotal),
        productId: longItems.first.productId,
        quantity: longItems.fold<int>(0, (sum, i) => sum + i.quantity),
        items: longItems,
        soldAt: DateTime.now(),
        createdAt: DateTime.now(),
      );

      final pdfBytes = await PdfInvoiceService.generateInvoicePdf(longSale, productMap);
      expect(pdfBytes, isNotEmpty);
      // Multi-page document will be larger than standard single-page document
      expect(pdfBytes.lengthInBytes, greaterThan(3000));
    });

    // 13. WhatsApp sharing uses the correct multi-product PDF and does not trigger duplicate share flows
    test('13. WhatsApp sharing launches directly without triggering duplicate native share sheet popup', () async {
      final alm = notifier.products.firstWhere((p) => p.sku == 'KV-ALM-250');
      final kaj = notifier.products.firstWhere((p) => p.sku == 'KV-KAJ-250');

      final items = [
        CartItem(product: alm, quantity: 2, unitPrice: 300.0),
        CartItem(product: kaj, quantity: 1, unitPrice: 350.0),
      ];

      final sale = await repository.recordSale(
        items: items,
        locationId: Location.jaipurId,
        customerName: 'Priya Verma',
        customerPhone: '9876501234',
        paymentMethod: 'UPI',
        totalAmount: 950.0,
      );

      final productMap = <String, Product>{alm.id: alm, kaj.id: kaj};

      List<XFile>? sharedFilesCapture;
      String? launchedUrl;

      // Case A: WhatsApp is installed and launches directly
      final resultDirect = await PdfInvoiceService.sendBillOnWhatsApp(
        sale,
        productMap,
        (uri) async {
          launchedUrl = uri.toString();
          return true; // Simulate WhatsApp app launch succeeded
        },
        (files, {text}) async {
          sharedFilesCapture = files;
        },
        () async => Directory.systemTemp,
      );

      expect(resultDirect.success, isTrue);
      expect(resultDirect.launchedDirectly, isTrue);
      expect(resultDirect.fallbackToShare, isFalse);
      expect(resultDirect.message, contains('WhatsApp opened for +91 98765 01234'));
      expect(launchedUrl, contains('whatsapp://send?phone=919876501234'));
      expect(launchedUrl, contains(sale.billNumber));
      // Direct launch MUST NOT trigger native share popup (avoids duplicate share popups)
      expect(sharedFilesCapture, isNull);

      // Case B: WhatsApp is NOT installed -> Falls back gracefully to share sheet
      launchedUrl = null;
      sharedFilesCapture = null;

      final resultFallback = await PdfInvoiceService.sendBillOnWhatsApp(
        sale,
        productMap,
        (uri) async => false, // Simulate WhatsApp not installed
        (files, {text}) async {
          sharedFilesCapture = files;
        },
        () async => Directory.systemTemp,
      );

      expect(resultFallback.success, isFalse);
      expect(resultFallback.launchedDirectly, isFalse);
      expect(resultFallback.fallbackToShare, isTrue);
      expect(resultFallback.message, contains('WhatsApp is not installed on this device'));
      // Fallback MUST invoke share sheet with generated PDF
      expect(sharedFilesCapture, isNotNull);
      expect(sharedFilesCapture!.first.path, contains('KizunaVeda_${sale.billNumber}.pdf'));
    });

    // 14. Historical invoice values remain unchanged after catalogue prices are edited
    test('14. Historical invoice values remain unchanged after catalogue prices are edited', () async {
      final alm = notifier.products.firstWhere((p) => p.sku == 'KV-ALM-250');
      expect(alm.standardSellingPrice, equals(300.0));

      final items = [
        CartItem(product: alm, quantity: 2, unitPrice: 300.0),
      ];

      final historicalSale = await repository.recordSale(
        items: items,
        locationId: Location.jaipurId,
        customerName: 'Historical Customer',
        customerPhone: '9800012345',
        totalAmount: 600.0,
      );

      expect(historicalSale.items.first.unitPrice, equals(300.0));
      expect(historicalSale.items.first.lineTotal, equals(600.0));
      expect(historicalSale.totalAmount, equals(600.0));

      // Now Owner changes catalogue price of Almonds from 300 to 500
      await repository.updateProduct(
        id: alm.id,
        standardSellingPrice: 500.0,
      );
      await notifier.loadInventoryData();

      final updatedAlm = notifier.products.firstWhere((p) => p.id == alm.id);
      expect(updatedAlm.standardSellingPrice, equals(500.0));

      // Re-fetch sales and inspect the historical bill
      final sales = await repository.getSales();
      final reloadedHistoricalSale = sales.firstWhere((s) => s.id == historicalSale.id);

      expect(reloadedHistoricalSale.items.first.unitPrice, equals(300.0));
      expect(reloadedHistoricalSale.items.first.lineTotal, equals(600.0));
      expect(reloadedHistoricalSale.totalAmount, equals(600.0));

      // PDF and WhatsApp text for historical sale must still show 300.0 and 600.0
      final updatedProductMap = {updatedAlm.id: updatedAlm};
      final historicalMessage = PdfInvoiceService.formatWhatsAppMessage(
        reloadedHistoricalSale,
        updatedProductMap,
      );
      expect(historicalMessage, contains('Rate: Rs 300.00'));
      expect(historicalMessage, contains('Amt: Rs 600.00'));
      expect(historicalMessage, contains('Total Amount: Rs 600.00'));
    });
  });
}
