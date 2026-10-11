import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/app/providers/inventory_provider.dart';
import 'package:kizuna_veda/core/constants/app_constants.dart';
import 'package:kizuna_veda/core/services/pdf_invoice_service.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/product.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/sale.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/inventory/presentation/widgets/edit_product_pricing_dialog.dart';
import 'package:kizuna_veda/features/owner/domain/services/owner_metrics_calculator.dart';
import 'package:kizuna_veda/features/sales/presentation/screens/guided_new_sale_screen.dart';

void main() {
  group('1. POS — Editable Selling Price & Subtotal Tests', () {
    test('Product entity provides standard pricing, cost, and SKU fallbacks', () {
      final tulsi = Product(
        id: 'p1',
        name: 'Tulsi Green',
        packageSize: '100g',
        sku: 'KV-TULSI-100',
        createdAt: DateTime.now(),
      );
      expect(tulsi.standardSellingPrice, equals(100.0));
      expect(tulsi.purchaseCost, equals(0.0));

      // Intelligent default helper
      expect(Product.defaultPriceForSku('KV-TRI-250'), equals(120.0));
      expect(Product.defaultPriceForSku('KV-ASHWA-100'), equals(150.0));
      expect(Product.defaultCostForSku('KV-TULSI-100'), equals(45.0));
      expect(Product.defaultCostForSku('KV-TRI-250'), equals(55.0));
      expect(Product.defaultCostForSku('KV-ASHWA-100'), equals(70.0));

      // Serialization test
      final json = tulsi.toJson();
      expect(json['standard_selling_price'], equals(100.0));
      expect(json['purchase_cost'], equals(0.0));

      final deserialized = Product.fromJson({
        'id': 'p2',
        'name': 'Triphala Premium',
        'sku': 'KV-TRI-250',
        'standard_selling_price': 135.0,
        'purchase_cost': 60.0,
      });
      expect(deserialized.standardSellingPrice, equals(135.0));
      expect(deserialized.purchaseCost, equals(60.0));
    });

    test('SaleItem calculates lineTotal accurately with unitPrice and discount', () {
      final item = SaleItem(
        id: 'si-1',
        saleId: 'sale-1',
        productId: 'prod-1',
        quantity: 3,
        unitPrice: 125.0,
        discount: 25.0,
        unitCost: 50.0,
        createdAt: DateTime.now(),
      );

      // (3 * 125) - 25 = 375 - 25 = 350
      expect(item.lineTotal, equals(350.0));
      expect(item.discount, equals(25.0));
      expect(item.unitCost, equals(50.0));

      final json = item.toJson();
      expect(json['unit_price'], equals(125.0));
      expect(json['discount_amount'], equals(25.0));
      expect(json['unit_cost'], equals(50.0));

      final fromJson = SaleItem.fromJson(json);
      expect(fromJson.lineTotal, equals(350.0));
      expect(fromJson.unitCost, equals(50.0));
      expect(fromJson.discount, equals(25.0));
    });

    testWidgets('GuidedNewSaleScreen prefills standard price and recalculates subtotal on edit',
        (tester) async {
      tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repository = UnconnectedInventoryRepository();
      final notifier = InventoryNotifier(repository: repository);
      await notifier.loadInventoryData();

      // Ensure stock is available at Jaipur for the first product
      final firstProduct = notifier.products.first;
      await repository.adjustStoreStock(
        locationId: LocationConstants.jaipurId,
        productId: firstProduct.id,
        newQuantity: 50,
        reason: 'INITIAL_STOCK',
      );
      await notifier.loadInventoryData();

      await tester.pumpWidget(
        MaterialApp(
          home: InventoryProvider(
            notifier: notifier,
            child: const GuidedNewSaleScreen(
              initialLocationId: LocationConstants.jaipurId,
              role: UserRole.owner,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify standard selling price is prefilled
      final priceField = find.byKey(const Key('guided_selling_price_field'));
      expect(priceField, findsOneWidget);
      final priceCtrl = tester.widget<TextFormField>(priceField).controller!;
      expect(priceCtrl.text, equals(firstProduct.standardSellingPrice.toStringAsFixed(2)));

      // 2. Default subtotal with quantity 1 and no discount
      expect(find.text('Subtotal: ₹${firstProduct.standardSellingPrice.toStringAsFixed(2)}'), findsOneWidget);

      // 3. Edit Quantity to 3
      final qtyField = find.byKey(const Key('guided_quantity_field'));
      await tester.enterText(qtyField, '3');
      await tester.pumpAndSettle();
      final expectedGross = 3 * firstProduct.standardSellingPrice;
      expect(find.text('Subtotal: ₹${expectedGross.toStringAsFixed(2)}'), findsOneWidget);

      // 4. Edit Selling Price from standard to ₹140.00
      await tester.enterText(priceField, '140');
      await tester.pumpAndSettle();
      // 3 * 140 = 420
      expect(find.text('Subtotal: ₹420.00'), findsOneWidget);
      expect(find.textContaining('Authorized Price Override'), findsOneWidget);

      // 5. Add Discount of ₹20.00
      final discountField = find.byKey(const Key('guided_discount_field'));
      expect(discountField, findsOneWidget);
      await tester.enterText(discountField, '20');
      await tester.pumpAndSettle();
      // (3 * 140) - 20 = 400
      expect(find.text('Subtotal: ₹400.00'), findsOneWidget);

      // 6. Navigate to Step 2 (Customer & Payment)
      final continueToCustomerBtn = find.byKey(const Key('continue_to_customer_button'));
      await tester.tap(continueToCustomerBtn);
      await tester.pumpAndSettle();

      // 7. Fill required Customer fields on Step 2
      await tester.enterText(find.byKey(const Key('guided_customer_name_field')), 'Vikas Sharma');
      await tester.enterText(find.byKey(const Key('guided_customer_phone_field')), '9876543210');
      await tester.pumpAndSettle();

      // 8. Continue to Step 3 (Review Bill)
      final continueToReviewBtn = find.byKey(const Key('continue_to_review_bill_button'));
      await tester.tap(continueToReviewBtn);
      await tester.pumpAndSettle();

      // 9. Verify entered price, discount, and total are PRESERVED and displayed on Step 3
      expect(find.text('Bill Preview'), findsOneWidget);
      expect(find.textContaining('3 pkts @ ₹140.00 (Disc: -₹20.00)'), findsOneWidget);
      expect(find.text('₹400.00'), findsWidgets); // Line total and Grand Total
      expect(find.textContaining('Price override from standard'), findsOneWidget);

      // 10. Navigate back to Step 1 and verify entered price & discount are still intact
      final editItemsBtn = find.byKey(const Key('edit_items_button'));
      await tester.tap(editItemsBtn);
      await tester.pumpAndSettle();

      expect(tester.widget<TextFormField>(priceField).controller!.text, equals('140'));
      expect(tester.widget<TextFormField>(discountField).controller!.text, equals('20'));
      expect(tester.widget<TextFormField>(qtyField).controller!.text, equals('3'));
    });

    testWidgets('GuidedNewSaleScreen blocks invalid/negative price and excess discount',
        (tester) async {
      tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repository = UnconnectedInventoryRepository();
      final notifier = InventoryNotifier(repository: repository);
      await notifier.loadInventoryData();

      await tester.pumpWidget(
        MaterialApp(
          home: InventoryProvider(
            notifier: notifier,
            child: const GuidedNewSaleScreen(
              initialLocationId: LocationConstants.jaipurId,
              role: UserRole.owner,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final priceField = find.byKey(const Key('guided_selling_price_field'));
      final continueBtn = find.byKey(const Key('continue_to_customer_button'));

      // Negative price
      await tester.enterText(priceField, '-50');
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('positive selling price'), findsOneWidget);

      // Zero price
      await tester.enterText(priceField, '0');
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('positive selling price'), findsOneWidget);

      // Reset to valid price
      await tester.enterText(priceField, '100');
      await tester.pumpAndSettle();

      // Excess discount > line subtotal
      final discountField = find.byKey(const Key('guided_discount_field'));
      await tester.enterText(discountField, '500'); // qty 1 * 100 = 100, discount 500
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('Discount cannot exceed'), findsOneWidget);
    });
  });

  group('2. Product Management — Standard Prices & Costs Tests', () {
    test('Owner can update standard selling price and purchase cost via repository', () async {
      final repo = UnconnectedInventoryRepository();
      final products = await repo.getProducts();
      final targetProduct = products.first;

      final updated = await repo.updateProductPricing(
        productId: targetProduct.id,
        standardSellingPrice: 175.0,
        purchaseCost: 80.0,
      );

      expect(updated.standardSellingPrice, equals(175.0));
      expect(updated.purchaseCost, equals(80.0));

      final fetched = (await repo.getProducts()).firstWhere((p) => p.id == targetProduct.id);
      expect(fetched.standardSellingPrice, equals(175.0));
      expect(fetched.purchaseCost, equals(80.0));
    });

    test('Negative price or cost updates are rejected with error', () async {
      final repo = UnconnectedInventoryRepository();
      final products = await repo.getProducts();
      final target = products.first;

      expect(
        () => repo.updateProductPricing(
          productId: target.id,
          standardSellingPrice: -10.0,
          purchaseCost: 50.0,
        ),
        throwsA(isA<Exception>()),
      );

      expect(
        () => repo.updateProductPricing(
          productId: target.id,
          standardSellingPrice: 100.0,
          purchaseCost: -20.0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    testWidgets('EditProductPricingDialog validates inputs and saves pricing', (tester) async {
      final repo = UnconnectedInventoryRepository();
      final notifier = InventoryNotifier(repository: repo);
      await notifier.loadInventoryData();
      final product = notifier.products.first;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => EditProductPricingDialog.show(
                  ctx,
                  product: product,
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

      expect(find.text('Manage Product Pricing'), findsOneWidget);
      final priceField = find.byKey(const Key('edit_selling_price_field'));
      final costField = find.byKey(const Key('edit_purchase_cost_field'));

      // Validate non-negative validation
      await tester.enterText(priceField, '-10');
      await tester.tap(find.byKey(const Key('save_product_pricing_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('must be non-negative'), findsOneWidget);

      // Enter valid prices and costs
      await tester.enterText(priceField, '160.00');
      await tester.enterText(costField, '65.00');
      await tester.tap(find.byKey(const Key('save_product_pricing_button')));
      await tester.pumpAndSettle();

      // Dialog closed on success
      expect(find.text('Manage Product Pricing'), findsNothing);
      expect(notifier.products.first.standardSellingPrice, equals(160.0));
      expect(notifier.products.first.purchaseCost, equals(65.0));
    });
  });

  group('3. Historical Sales & Profit Preservation Tests', () {
    test('Updating standard price/cost does NOT recalculate historical sales or past profits',
        () async {
      final repo = UnconnectedInventoryRepository();
      final products = await repo.getProducts();
      final prod = products.first; // Triphala: price 120, cost 55

      // Add inventory to Jaipur
      await repo.adjustStoreStock(
        locationId: LocationConstants.jaipurId,
        productId: prod.id,
        newQuantity: 100,
      );

      // 1. Record Sale #1 with standard price 120 and snapshot cost 55
      final sale1 = await repo.recordSale(
        productId: prod.id,
        quantity: 2,
        totalAmount: 240.0,
        unitPrice: 120.0,
        locationId: LocationConstants.jaipurId,
      );

      expect(sale1.items.first.unitPrice, equals(120.0));
      expect(sale1.items.first.unitCost, equals(55.0));

      // 2. Later, the owner changes the standard price to 160 and purchase cost to 80
      await repo.updateProductPricing(
        productId: prod.id,
        standardSellingPrice: 160.0,
        purchaseCost: 80.0,
      );

      // 3. Compute metrics on the sale created before price change
      final updatedProducts = await repo.getProducts();
      final storeInvs = await repo.getStoreInventories();

      final metrics = OwnerMetricsCalculator.compute(
        sales: [sale1],
        products: updatedProducts,
        storeInventories: storeInvs,
      );

      // Sale 1 historical COGS must remain (2 * 55) = 110, NOT (2 * 80) = 160!
      // Historical Gross Profit must remain (240 - 110) = 130!
      expect(metrics.totalRevenue, equals(240.0));
      expect(metrics.totalCogs, equals(110.0));
      expect(metrics.totalGrossProfit, equals(130.0));

      // Check product-specific metric
      final prodMetric = metrics.allProducts.firstWhere((p) => p.productId == prod.id);
      expect(prodMetric.cogs, equals(110.0));
      expect(prodMetric.grossProfit, equals(130.0));
    });

    test('Legacy sales with missing cost data honestly report Unavailable instead of inventing profit',
        () {
      // Legacy sale without unitCost and product without purchaseCost
      final legacyProduct = Product(
        id: 'legacy-p1',
        name: 'Legacy Powder',
        packageSize: '100g',
        sku: 'KV-LEG-100',
        standardSellingPrice: 100.0,
        purchaseCost: 0.0, // No cost recorded
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      );

      final legacySale = Sale(
        id: 'leg-sale-1',
        locationId: LocationConstants.jaipurId,
        billNumber: 'BILL-000001',
        productId: 'legacy-p1',
        quantity: 5,
        totalAmount: 500.0,
        soldAt: DateTime.now().subtract(const Duration(days: 10)),
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        items: [
          SaleItem(
            id: 'si-leg-1',
            saleId: 'leg-sale-1',
            productId: 'legacy-p1',
            quantity: 5,
            unitPrice: 100.0,
            unitCost: null, // Missing cost snapshot on legacy sale
            createdAt: DateTime.now().subtract(const Duration(days: 10)),
          ),
        ],
      );

      final metrics = OwnerMetricsCalculator.compute(
        sales: [legacySale],
        products: [legacyProduct],
        storeInventories: [],
      );

      // Revenue is accurately 500, but COGS and profit must NOT be fabricated!
      expect(metrics.totalRevenue, equals(500.0));
      expect(metrics.hasReliableCostData, isFalse);
      expect(metrics.totalCogs, isNull);
      expect(metrics.totalGrossProfit, isNull);
    });

    test('WhatsApp message and PDF format include unit price, discount, and line total', () {
      final sale = Sale(
        id: 'sale-format-1',
        locationId: LocationConstants.jaipurId,
        billNumber: 'BILL-010020',
        customerName: 'Aarav Patel',
        customerPhone: '9876543210',
        productId: 'prod-101',
        quantity: 2,
        totalAmount: 230.0,
        soldAt: DateTime.now(),
        createdAt: DateTime.now(),
        items: [
          SaleItem(
            id: 'si-f-1',
            saleId: 'sale-format-1',
            productId: 'prod-101',
            quantity: 2,
            unitPrice: 125.0,
            discount: 20.0, // (2 * 125) - 20 = 230
            createdAt: DateTime.now(),
          ),
        ],
      );

      final productMap = {
        'prod-101': Product(
          id: 'prod-101',
          name: 'Triphala Churna',
          packageSize: '250g',
          sku: 'KV-TRI-250',
          createdAt: DateTime.now(),
        ),
      };

      final message = PdfInvoiceService.formatWhatsAppMessage(sale, productMap);
      expect(message, contains('BILL-010020'));
      expect(message, contains('Rate: Rs 125.00'));
      expect(message, contains('Disc: -Rs 20.00'));
      expect(message, contains('Amt: Rs 230.00'));
      expect(message, contains('Total Amount: Rs 230.00'));
    });
  });
}
