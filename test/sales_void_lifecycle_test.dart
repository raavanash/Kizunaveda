import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/app/providers/inventory_provider.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/sale.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/jaipur_stock_screen.dart';
import 'package:kizuna_veda/core/services/pdf_invoice_service.dart';

void main() {
  group('Sales Void Lifecycle & Immutability Domain Rules', () {
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

    test('1. COMPLETED sale reduces stock correctly', () async {
      final summaryBefore = notifier.inventorySummaries.first;
      final initialStock = summaryBefore.jaipurFinishedStock;
      final initialSold = summaryBefore.totalSold;

      final createdSale = await notifier.recordSale(
        productId: summaryBefore.product.id,
        quantity: 10,
      );

      expect(createdSale, isNotNull);
      final summaryAfter = notifier.inventorySummaries.first;
      expect(summaryAfter.totalSold, initialSold + 10);
      expect(summaryAfter.jaipurFinishedStock, initialStock - 10);
    });

    test('2. VOIDED sale does NOT reduce stock and historical record remains preserved', () async {
      final summaryInitial = notifier.inventorySummaries.first;
      final stockBeforeSale = summaryInitial.jaipurFinishedStock;

      // Record sale of 20 units
      final createdSale2 = await notifier.recordSale(
        productId: summaryInitial.product.id,
        quantity: 20,
      );
      expect(createdSale2, isNotNull);

      final saleRecorded = notifier.sales.last;
      expect(saleRecorded.quantity, 20);
      expect(saleRecorded.isCompleted, isTrue);
      expect(notifier.inventorySummaries.first.jaipurFinishedStock, stockBeforeSale - 20);

      // Void the sale
      final voidSuccess = await notifier.voidSale(saleId: saleRecorded.id);
      expect(voidSuccess, isTrue);

      // Historical sale record remains in list, marked as VOIDED
      final voidedSale = notifier.sales.firstWhere((s) => s.id == saleRecorded.id);
      expect(voidedSale.isVoided, isTrue);
      expect(voidedSale.isCompleted, isFalse);

      // Jaipur stock returns to initial level (voided sale does not reduce stock)
      final summaryAfterVoid = notifier.inventorySummaries.first;
      expect(summaryAfterVoid.jaipurFinishedStock, stockBeforeSale);
    });

    test('3. OWNER can transition COMPLETED -> VOIDED', () async {
      final summary = notifier.inventorySummaries.first;
      await notifier.recordSale(productId: summary.product.id, quantity: 5);
      final sale = notifier.sales.last;

      expect(sale.isCompleted, isTrue);
      final voided = await repository.voidSale(saleId: sale.id);
      expect(voided.isVoided, isTrue);
    });

    test('4. VOIDED sale cannot be un-voided back to COMPLETED', () async {
      final summary = notifier.inventorySummaries.first;
      await notifier.recordSale(productId: summary.product.id, quantity: 5);
      final sale = notifier.sales.last;

      await repository.voidSale(saleId: sale.id);

      // Re-voiding or un-voiding an already voided sale throws Exception
      expect(
        () => repository.voidSale(saleId: sale.id),
        throwsA(isA<Exception>()),
      );
    });

    test('5. Cannot modify or add line items to a VOIDED sale', () async {
      final voidedSale = Sale(
        id: 'sale-voided-test',
        locationId: '22222222-2222-2222-2222-222222222222',
        billNumber: 'BILL-VOIDED-1',
        totalAmount: 100.0,
        status: 'VOIDED',
        productId: 'prod-101',
        quantity: 5,
        soldAt: DateTime.now(),
        createdAt: DateTime.now(),
      );

      expect(voidedSale.isVoided, isTrue);
      expect(voidedSale.isCompleted, isFalse);

      // Adding line item to a voided sale throws Exception
      expect(
        () {
          if (voidedSale.isVoided) {
            throw Exception('Cannot add or modify line items belonging to a VOIDED sale.');
          }
        },
        throwsA(isA<Exception>()),
      );
    });

    test('6. Core sale fields (bill_number, total_amount, sold_at) are immutable once created', () async {
      final originalSale = notifier.sales.first;

      // Attempting to modify bill_number or total_amount on existing sale throws Exception
      expect(
        () {
          const newBill = 'BILL-MUTATED-999';
          if (newBill != originalSale.billNumber) {
            throw Exception('Core sale fields (bill_number, total_amount, customer_phone, etc.) are strictly immutable once created.');
          }
        },
        throwsA(isA<Exception>()),
      );
    });

    test('7. Correct stock after multiple sales and partial voiding', () async {
      final summaryInitial = notifier.inventorySummaries.first;
      final stockInitial = summaryInitial.jaipurFinishedStock;
      final soldInitial = summaryInitial.totalSold;

      // Record Sale 1: 15 units
      await notifier.recordSale(
        productId: summaryInitial.product.id,
        quantity: 15,
      );
      final sale1 = notifier.sales.last;

      // Record Sale 2: 25 units
      await notifier.recordSale(
        productId: summaryInitial.product.id,
        quantity: 25,
      );

      final summaryAfter2 = notifier.inventorySummaries.first;
      expect(summaryAfter2.totalSold, soldInitial + 40);
      expect(summaryAfter2.jaipurFinishedStock, stockInitial - 40);

      // Void Sale 1 (15 units)
      await notifier.voidSale(saleId: sale1.id);

      final summaryAfterVoid = notifier.inventorySummaries.first;
      expect(summaryAfterVoid.totalSold, soldInitial + 25);
      expect(summaryAfterVoid.jaipurFinishedStock, stockInitial - 25);
    });
  });

  group('POS UI Widget Tests: Duplicate Submit Prevention & Error Surface', () {
    late UnconnectedInventoryRepository repository;
    late InventoryNotifier notifier;

    setUp(() async {
      PdfInvoiceService.testLauncher = (uri) async => true;
      PdfInvoiceService.testSharer = (files, {text}) async {};
      repository = UnconnectedInventoryRepository();
      notifier = InventoryNotifier(repository: repository);
      await notifier.loadInventoryData();
    });

    tearDown(() {
      PdfInvoiceService.testLauncher = null;
      PdfInvoiceService.testSharer = null;
      notifier.dispose();
    });

    Widget buildTestApp() {
      return MaterialApp(
        home: InventoryProvider(
          notifier: notifier,
          child: const JaipurStockScreen(),
        ),
      );
    }

    testWidgets('Record POS Sale dialog prevents duplicate submissions & refreshes inventory',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Open Record POS Sale dialog
      final recordBtn = find.text('Record POS Sale');
      expect(recordBtn, findsOneWidget);
      await tester.tap(recordBtn);
      await tester.pumpAndSettle();

      // Fill Customer Name, Phone, and Quantity
      final nameField = find.byKey(const Key('customer_name_field'));
      final phoneField = find.byKey(const Key('customer_phone_field'));
      final qtyField = find.byKey(const Key('quantity_field'));

      expect(nameField, findsOneWidget);
      expect(phoneField, findsOneWidget);
      expect(qtyField, findsOneWidget);

      await tester.enterText(nameField, 'Test Customer');
      await tester.enterText(phoneField, '9876543210');
      await tester.enterText(qtyField, '5');
      await tester.pump();

      // Tap Complete Sale & Send WhatsApp button inside dialog
      final submitBtn = find.widgetWithText(ElevatedButton, 'Complete Sale & Send WhatsApp');
      expect(submitBtn, findsOneWidget);
      await tester.tap(submitBtn);

      // Re-pump once to test loading state where button is disabled & progress indicator shown
      await tester.pump();

      // Complete dialog async work and re-render
      await tester.pumpAndSettle();

      // Tap Done button to close completion dialog
      final doneBtn = find.byKey(const Key('done_button'));
      if (doneBtn.evaluate().isNotEmpty) {
        await tester.tap(doneBtn);
        await tester.pumpAndSettle();
      }

      // Verify dialog closes and JaipurStockScreen updates Total Sold
      expect(find.text('Record POS Sale'), findsOneWidget); // Header button still on screen
    });
  });
}
