import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/app/providers/inventory_provider.dart';
import 'package:kizuna_veda/core/constants/app_constants.dart';
import 'package:kizuna_veda/core/services/pdf_invoice_service.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/sale.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/inventory/presentation/widgets/record_pos_sale_dialog.dart';
import 'package:kizuna_veda/features/jaipur/presentation/screens/ebill_history_screen.dart';

void main() {
  group('V1.2 Two-Store Billing & Stock Isolation', () {
    late UnconnectedInventoryRepository repository;
    late InventoryNotifier notifier;

    setUp(() async {
      repository = UnconnectedInventoryRepository();
      notifier = InventoryNotifier(repository: repository);
      await notifier.loadInventoryData();
    });

    tearDown(() {
      notifier.dispose();
    });

    test('Neemrana sales deduct only Neemrana stock', () async {
      final product = notifier.products.first;

      // Pack 100 at Neemrana
      await notifier.addPackingRecord(
        productId: product.id,
        packedQuantity: 100,
      );

      final initialSummary = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == product.id);
      final initialNeemranaStock = initialSummary.neemranaFinishedStock;

      // Create sale at Neemrana
      final sale = await notifier.recordSale(
        productId: product.id,
        quantity: 5,
        customerName: 'Neemrana Customer',
        customerPhone: '9876543210',
        targetLocationId: LocationConstants.neemranaId,
        invoiceType: 'NON_GST',
        totalAmount: 500.0,
      );

      expect(sale, isNotNull);
      expect(sale!.locationId, equals(LocationConstants.neemranaId));

      final updatedSummary = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == product.id);

      // Neemrana stock deducted by 5
      expect(updatedSummary.neemranaFinishedStock, equals(initialNeemranaStock - 5));
      // Jaipur stock unaffected
      expect(updatedSummary.jaipurFinishedStock, equals(initialSummary.jaipurFinishedStock));
    });

    test('Jaipur sales deduct only Jaipur stock', () async {
      final product = notifier.products.first;

      final initialSummary = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == product.id);
      final initialJaipurStock = initialSummary.jaipurFinishedStock;

      // Create sale at Jaipur
      final sale = await notifier.recordSale(
        productId: product.id,
        quantity: 2,
        customerName: 'Jaipur Customer',
        customerPhone: '9123456789',
        targetLocationId: LocationConstants.jaipurId,
        invoiceType: 'NON_GST',
        totalAmount: 200.0,
      );

      expect(sale, isNotNull);
      expect(sale!.locationId, equals(LocationConstants.jaipurId));

      final updatedSummary = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == product.id);

      // Jaipur stock deducted by 2
      expect(updatedSummary.jaipurFinishedStock, equals(initialJaipurStock - 2));
      // Neemrana stock unaffected
      expect(updatedSummary.neemranaFinishedStock, equals(initialSummary.neemranaFinishedStock));
    });

    test('Voided bills do not deduct stock', () async {
      final product = notifier.products.first;
      final summaryBefore = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == product.id);

      final sale = await notifier.recordSale(
        productId: product.id,
        quantity: 3,
        customerName: 'Temp Sale',
        customerPhone: '9999999999',
        targetLocationId: LocationConstants.jaipurId,
        totalAmount: 300.0,
      );

      expect(sale, isNotNull);

      // Void the sale
      final voided = await notifier.voidSale(saleId: sale!.id);
      expect(voided, isTrue);

      final summaryAfterVoid = notifier.inventorySummaries
          .firstWhere((s) => s.product.id == product.id);

      // Stock should be restored (matching initial summary)
      expect(summaryAfterVoid.jaipurFinishedStock, equals(summaryBefore.jaipurFinishedStock));
    });
  });

  group('V1.2 GST vs Without GST Invoice Modes', () {
    final nonGstSale = Sale(
      id: 'sale-nongst-1',
      locationId: LocationConstants.neemranaId,
      productId: 'prod-1',
      quantity: 2,
      billNumber: 'BILL-NG-001',
      customerName: 'Rohan Kumar',
      customerPhone: '9876543210',
      paymentMethod: 'CASH',
      invoiceType: 'NON_GST',
      gstRate: 0.0,
      taxableAmount: 200.0,
      cgstAmount: 0.0,
      sgstAmount: 0.0,
      igstAmount: 0.0,
      totalAmount: 200.0,
      soldAt: DateTime.now(),
      createdAt: DateTime.now(),
      status: 'COMPLETED',
      items: [],
    );

    final gstSale = Sale(
      id: 'sale-gst-1',
      locationId: LocationConstants.jaipurId,
      productId: 'prod-1',
      quantity: 2,
      billNumber: 'BILL-GST-001',
      customerName: 'Anita Roy',
      customerPhone: '9123456789',
      paymentMethod: 'UPI',
      invoiceType: 'GST',
      gstRate: 18.0,
      taxableAmount: 200.0,
      cgstAmount: 18.0,
      sgstAmount: 18.0,
      igstAmount: 0.0,
      totalAmount: 236.0,
      soldAt: DateTime.now(),
      createdAt: DateTime.now(),
      status: 'COMPLETED',
      items: [],
    );

    test('Non-GST sale getters and PDF generation', () async {
      expect(nonGstSale.isGst, isFalse);
      expect(nonGstSale.totalAmount, equals(200.0));

      final pdfBytes = await PdfInvoiceService.buildPdf(nonGstSale);
      expect(pdfBytes, isNotEmpty);
    });

    test('GST sale getters and PDF generation', () async {
      expect(gstSale.isGst, isTrue);
      expect(gstSale.totalAmount, equals(236.0));
      expect(gstSale.cgstAmount + gstSale.sgstAmount, equals(36.0));

      final pdfBytes = await PdfInvoiceService.buildPdf(gstSale);
      expect(pdfBytes, isNotEmpty);
    });
  });

  group('V1.2 POS Sale Dialog & History UI Tests', () {
    late UnconnectedInventoryRepository repository;
    late InventoryNotifier notifier;

    setUp(() async {
      repository = UnconnectedInventoryRepository();
      notifier = InventoryNotifier(repository: repository);
      await notifier.loadInventoryData();
    });

    tearDown(() {
      notifier.dispose();
    });

    testWidgets('RecordPosSaleDialog renders and validates Without GST mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryProvider(
            notifier: notifier,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => RecordPosSaleDialog.show(
                  context,
                  targetLocationId: LocationConstants.jaipurId,
                  locationName: 'Jaipur Store',
                  notifier: notifier,
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Create Bill (Jaipur Store)'), findsOneWidget);
      expect(find.text('Without GST'), findsOneWidget);
      expect(find.text('With GST'), findsOneWidget);
    });

    testWidgets('EBillHistoryScreen shows location and GST badges', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryProvider(
            notifier: notifier,
            child: const EBillHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Generated PDF E-Bills History'), findsOneWidget);
      expect(find.text('Active Bills (1)'), findsOneWidget);
    });
  });
}
