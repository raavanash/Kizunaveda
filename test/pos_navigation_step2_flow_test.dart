import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/app/providers/inventory_provider.dart';
import 'package:kizuna_veda/core/constants/app_constants.dart';
import 'package:kizuna_veda/core/services/pdf_invoice_service.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/sale.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/sales/presentation/screens/guided_new_sale_screen.dart';

class Step2TestInventoryRepo extends UnconnectedInventoryRepository {
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
  group('POS Step 2 Navigation & Validation Tests', () {
    late Step2TestInventoryRepo inventoryRepo;
    late InventoryNotifier inventoryNotifier;
    late List<Uri> launchedUris;

    setUp(() async {
      launchedUris = [];
      PdfInvoiceService.testTempDir = () async => Directory.systemTemp;
      PdfInvoiceService.testLauncher = (uri) async {
        launchedUris.add(uri);
        return true;
      };

      inventoryRepo = Step2TestInventoryRepo();
      inventoryNotifier = InventoryNotifier(repository: inventoryRepo);
      await inventoryNotifier.loadInventoryData();
    });

    tearDown(() {
      PdfInvoiceService.testLauncher = null;
      inventoryNotifier.dispose();
    });

    Widget buildTestApp({required Widget child}) {
      return MaterialApp(
        home: InventoryProvider(
          notifier: inventoryNotifier,
          child: child,
        ),
      );
    }

    testWidgets(
        '1. Step 1 has clearly visible Continue button to advance to Step 2',
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

      // Verify Step 1 is active
      expect(find.text('1. Items'), findsOneWidget);
      // Verify in-form continue button exists
      final continueButton =
          find.byKey(const Key('continue_to_customer_button'));
      expect(continueButton, findsOneWidget);
      expect(find.text('Continue to Customer & Payment'), findsOneWidget);

      // Enter valid quantity and tap continue
      await tester.enterText(
          find.byKey(const Key('guided_quantity_field')), '2');
      await tester.ensureVisible(continueButton);
      await tester.pumpAndSettle();
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      // Should land on Step 2
      expect(find.text('2. Customer & Pay'), findsOneWidget);
    });

    testWidgets(
        '2. Step 2 shows full-width Continue to Review Bill button above navigation area',
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

      // Advance from Step 1 to Step 2 using docked next button
      await tester.enterText(
          find.byKey(const Key('guided_quantity_field')), '1');
      await tester.tap(find.byKey(const Key('guided_next_button')));
      await tester.pumpAndSettle();

      // Check Step 2 elements
      expect(find.text('Customer Information'), findsOneWidget);
      expect(find.text('Payment Method'), findsOneWidget);

      // Verify the dedicated full-width Continue to Review Bill button exists
      final continueButton =
          find.byKey(const Key('continue_to_review_bill_button'));
      expect(continueButton, findsOneWidget);
      expect(find.text('Continue to Review Bill'), findsOneWidget);

      // Verify Back to Items button also exists
      expect(find.byKey(const Key('step2_back_to_items_button')), findsOneWidget);
    });

    testWidgets(
        '3. Step 2 validation failure: empty fields keep user on Step 2 and display inline error banner',
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

      // Advance to Step 2
      await tester.enterText(
          find.byKey(const Key('guided_quantity_field')), '1');
      await tester.tap(find.byKey(const Key('guided_next_button')));
      await tester.pumpAndSettle();

      // Attempt to proceed without entering customer name and phone
      final continueButton =
          find.byKey(const Key('continue_to_review_bill_button'));
      await tester.ensureVisible(continueButton);
      await tester.pumpAndSettle();
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      // Must remain on Step 2
      expect(find.text('2. Customer & Pay'), findsOneWidget);
      expect(find.text('Customer name is required'), findsOneWidget);
      expect(find.text('Customer phone is required'), findsOneWidget);
      expect(find.textContaining('Please enter customer name'), findsOneWidget);

      // Enter name but invalid (too short) phone
      await tester.enterText(
          find.byKey(const Key('guided_customer_name_field')), 'Sunil Sharma');
      await tester.enterText(
          find.byKey(const Key('guided_customer_phone_field')), '12345');
      await tester.ensureVisible(continueButton);
      await tester.pumpAndSettle();
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      // Still on Step 2 with phone validation error
      expect(find.text('2. Customer & Pay'), findsOneWidget);
      expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    });

    testWidgets(
        '4. Step 2 valid submission: advances to Step 3 with zero data loss',
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

      // Select 4 packets on Step 1
      await tester.enterText(
          find.byKey(const Key('guided_quantity_field')), '4');
      await tester.tap(find.byKey(const Key('guided_next_button')));
      await tester.pumpAndSettle();

      // Enter customer info and UPI payment mode on Step 2
      await tester.enterText(
          find.byKey(const Key('guided_customer_name_field')), 'Pooja Verma');
      await tester.enterText(
          find.byKey(const Key('guided_customer_phone_field')), '9876543210');
      await tester.tap(find.byKey(const Key('payment_option_UPI')));
      await tester.pumpAndSettle();

      // Tap full-width Continue to Review Bill button
      final continueButton =
          find.byKey(const Key('continue_to_review_bill_button'));
      await tester.ensureVisible(continueButton);
      await tester.pumpAndSettle();
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      // Land on Step 3: Review Bill
      expect(find.text('3. Review Bill'), findsOneWidget);
      expect(find.text('Bill Preview'), findsOneWidget);

      // Verify all entered data survived without data loss
      expect(find.text('Jaipur Store'), findsOneWidget);
      expect(find.text('Pooja Verma'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('UPI'), findsWidgets);
      expect(find.textContaining('4 pkts @ ₹120.00'), findsOneWidget);
      expect(find.text('₹480.00'), findsWidgets);
    });

    testWidgets(
        '5. Step 3 supports editing customer and items without data loss',
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

      // Step 1 -> Step 2 -> Step 3
      await tester.enterText(
          find.byKey(const Key('guided_quantity_field')), '3');
      await tester.tap(find.byKey(const Key('guided_next_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('guided_customer_name_field')), 'Karan Mehra');
      await tester.enterText(
          find.byKey(const Key('guided_customer_phone_field')), '9812345678');
      final continueButton =
          find.byKey(const Key('continue_to_review_bill_button'));
      await tester.ensureVisible(continueButton);
      await tester.pumpAndSettle();
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      // On Step 3: Tap Edit Customer
      final editCustomerBtn = find.byKey(const Key('edit_customer_button'));
      expect(editCustomerBtn, findsOneWidget);
      await tester.ensureVisible(editCustomerBtn);
      await tester.pumpAndSettle();
      await tester.tap(editCustomerBtn);
      await tester.pumpAndSettle();

      // Must land on Step 2 with preserved details
      expect(find.text('2. Customer & Pay'), findsOneWidget);
      final nameField = tester.widget<TextFormField>(
          find.byKey(const Key('guided_customer_name_field')));
      expect(nameField.controller?.text, 'Karan Mehra');

      // Tap Back to Items from Step 2
      final backToItemsBtn =
          find.byKey(const Key('step2_back_to_items_button'));
      await tester.ensureVisible(backToItemsBtn);
      await tester.pumpAndSettle();
      await tester.tap(backToItemsBtn);
      await tester.pumpAndSettle();

      // Must land on Step 1 with preserved quantity
      expect(find.text('1. Items'), findsOneWidget);
      final qtyField = tester.widget<TextFormField>(
          find.byKey(const Key('guided_quantity_field')));
      expect(qtyField.controller?.text, '3');
    });

    testWidgets(
        '6. Complete Sale & Send WhatsApp commits sale once and prevents duplicate submissions',
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

      // Navigate Step 1 -> Step 2 -> Step 3
      await tester.enterText(
          find.byKey(const Key('guided_quantity_field')), '2');
      await tester.tap(find.byKey(const Key('guided_next_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('guided_customer_name_field')), 'Deepak Joshi');
      await tester.enterText(
          find.byKey(const Key('guided_customer_phone_field')), '9876598765');
      final continueButton =
          find.byKey(const Key('continue_to_review_bill_button'));
      await tester.ensureVisible(continueButton);
      await tester.pumpAndSettle();
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      final completeBtn =
          find.byKey(const Key('complete_sale_send_whatsapp_button'));
      expect(completeBtn, findsOneWidget);

      // Tap twice rapidly
      await tester.tap(completeBtn);
      await tester.pump();
      await tester.tap(completeBtn);
      await tester.pump();

      // Complete in-flight network operation
      inventoryRepo.inFlightCompleter!.complete();
      await tester.pumpAndSettle();

      // Sale committed exactly once via secure RPC
      expect(inventoryRepo.recordSaleCallCount, 1);
      expect(find.text('Sale Completed!'), findsOneWidget);
      expect(launchedUris.isNotEmpty, isTrue);
      expect(launchedUris.first.toString(), contains('919876598765'));
    });

    testWidgets(
        '7. Step 3 displays prominent, full-width, fixed-bottom Complete Sale & Send WhatsApp button visible and actionable without scrolling',
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

      // Navigate Step 1 -> Step 2 -> Step 3 using docked next buttons
      await tester.enterText(
          find.byKey(const Key('guided_quantity_field')), '1');
      await tester.tap(find.byKey(const Key('guided_next_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('guided_customer_name_field')), 'Vikas Gupta');
      await tester.enterText(
          find.byKey(const Key('guided_customer_phone_field')), '9876543210');
      await tester.tap(find.byKey(const Key('guided_next_button')));
      await tester.pumpAndSettle();

      // On Step 3: Verify the button is fixed at bottom and immediately hittable WITHOUT scrolling
      final completeButton =
          find.byKey(const Key('complete_sale_send_whatsapp_button'));
      expect(completeButton, findsOneWidget);
      expect(find.text('Complete Sale & Send WhatsApp'), findsOneWidget);

      // Verify Back to Edit button also present in bottom area
      expect(find.byKey(const Key('guided_back_button')), findsOneWidget);

      // Verify hittable immediately in bottom bar without scrolling
      await tester.tap(completeButton);
      await tester.pump();
      await tester.pumpAndSettle();

      // Successfully processed
      expect(inventoryRepo.recordSaleCallCount, 1);
      expect(find.text('Sale Completed!'), findsOneWidget);
    });
  });
}
