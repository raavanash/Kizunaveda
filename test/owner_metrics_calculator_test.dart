import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/core/constants/app_constants.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/product.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/sale.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/store_inventory.dart';
import 'package:kizuna_veda/features/owner/domain/entities/owner_dashboard_filter.dart';
import 'package:kizuna_veda/features/owner/domain/services/owner_metrics_calculator.dart';

void main() {
  group('OwnerMetricsCalculator Unit Tests', () {
    final productA = Product(
      id: 'prod-001',
      name: 'Triphala Churna 250g',
      packageSize: '250g',
      sku: 'KV-TRI-250',
      active: true,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
    );

    final productB = Product(
      id: 'prod-002',
      name: 'Ashwagandha Powder 100g',
      packageSize: '100g',
      sku: 'KV-ASH-100',
      active: true,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
    );

    final productC = Product(
      id: 'prod-003',
      name: 'Brahmi Vati 60 tabs',
      packageSize: '60 tabs',
      sku: 'KV-BRA-60',
      active: true,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
    );

    final testProducts = [productA, productB, productC];

    test('Empty data returns zero metrics safely without errors', () {
      final metrics = OwnerMetricsCalculator.compute(
        sales: [],
        products: [],
        storeInventories: [],
      );

      expect(metrics.totalRevenue, 0.0);
      expect(metrics.completedBillsCount, 0);
      expect(metrics.voidedBillsCount, 0);
      expect(metrics.totalPacketsSold, 0);
      expect(metrics.cashTotal, 0.0);
      expect(metrics.upiTotal, 0.0);
      expect(metrics.combinedCurrentStock, 0);
      expect(metrics.hasReliableCostData, false);
      expect(metrics.totalCogs, isNull);
      expect(metrics.totalGrossProfit, isNull);
      expect(metrics.grossMarginPercent, isNull);
      expect(metrics.allProducts, isEmpty);
      expect(metrics.soldProducts, isEmpty);
      expect(metrics.unsoldProducts, isEmpty);
    });

    test('Calculates canonical store inventory and combined stock dynamically', () {
      final storeInventories = [
        StoreInventory(
          id: 'inv-1',
          locationId: LocationConstants.neemranaId,
          productId: productA.id,
          currentQuantity: 15,
          updatedAt: DateTime.now(),
        ),
        StoreInventory(
          id: 'inv-2',
          locationId: LocationConstants.jaipurId,
          productId: productA.id,
          currentQuantity: 25,
          updatedAt: DateTime.now(),
        ),
        StoreInventory(
          id: 'inv-3',
          locationId: LocationConstants.neemranaId,
          productId: productB.id,
          currentQuantity: 10,
          updatedAt: DateTime.now(),
        ),
        StoreInventory(
          id: 'inv-4',
          locationId: LocationConstants.jaipurId,
          productId: productB.id,
          currentQuantity: 5,
          updatedAt: DateTime.now(),
        ),
        StoreInventory(
          id: 'inv-5',
          locationId: LocationConstants.neemranaId,
          productId: productC.id,
          currentQuantity: 0,
          updatedAt: DateTime.now(),
        ),
        StoreInventory(
          id: 'inv-6',
          locationId: LocationConstants.jaipurId,
          productId: productC.id,
          currentQuantity: 0,
          updatedAt: DateTime.now(),
        ),
      ];

      final metrics = OwnerMetricsCalculator.compute(
        sales: [],
        products: testProducts,
        storeInventories: storeInventories,
      );

      expect(metrics.neemranaCurrentStock, 25); // 15 + 10 + 0
      expect(metrics.jaipurCurrentStock, 30); // 25 + 5 + 0
      expect(metrics.combinedCurrentStock, 55); // 25 + 30
    });

    test('Aggregates sales revenue, cash, UPI, and total packets sold correctly', () {
      final now = DateTime.now();

      final sale1 = Sale(
        id: 'sale-1',
        locationId: LocationConstants.jaipurId,
        billNumber: 'BILL-010001',
        paymentMethod: 'CASH',
        totalAmount: 500.0,
        status: 'COMPLETED',
        productId: productA.id,
        quantity: 2,
        items: [
          SaleItem(
            id: 'item-1',
            saleId: 'sale-1',
            productId: productA.id,
            quantity: 2,
            unitPrice: 250.0,
            createdAt: now,
          ),
        ],
        soldAt: now,
        createdAt: now,
      );

      final sale2 = Sale(
        id: 'sale-2',
        locationId: LocationConstants.neemranaId,
        billNumber: 'BILL-010002',
        paymentMethod: 'UPI',
        totalAmount: 300.0,
        status: 'COMPLETED',
        productId: productB.id,
        quantity: 1,
        items: [
          SaleItem(
            id: 'item-2',
            saleId: 'sale-2',
            productId: productB.id,
            quantity: 1,
            unitPrice: 300.0,
            createdAt: now,
          ),
        ],
        soldAt: now,
        createdAt: now,
      );

      final metrics = OwnerMetricsCalculator.compute(
        sales: [sale1, sale2],
        products: testProducts,
        storeInventories: [],
      );

      expect(metrics.totalRevenue, 800.0);
      expect(metrics.completedBillsCount, 2);
      expect(metrics.voidedBillsCount, 0);
      expect(metrics.cashTotal, 500.0);
      expect(metrics.upiTotal, 300.0);
      expect(metrics.totalPacketsSold, 3);
      expect(metrics.jaipurRevenue, 500.0);
      expect(metrics.neemranaRevenue, 300.0);
      expect(metrics.jaipurPacketsSold, 2);
      expect(metrics.neemranaPacketsSold, 1);
    });

    test('Strictly excludes voided sales from revenue and packet counts while counting voided bills', () {
      final now = DateTime.now();

      final completedSale = Sale(
        id: 'sale-1',
        locationId: LocationConstants.jaipurId,
        billNumber: 'BILL-010001',
        paymentMethod: 'CASH',
        totalAmount: 400.0,
        status: 'COMPLETED',
        productId: productA.id,
        quantity: 2,
        soldAt: now,
        createdAt: now,
      );

      final voidedSale = Sale(
        id: 'sale-2',
        locationId: LocationConstants.jaipurId,
        billNumber: 'BILL-010002',
        paymentMethod: 'CASH',
        totalAmount: 1000.0,
        status: 'VOIDED',
        productId: productA.id,
        quantity: 5,
        soldAt: now,
        createdAt: now,
      );

      final metrics = OwnerMetricsCalculator.compute(
        sales: [completedSale, voidedSale],
        products: testProducts,
        storeInventories: [],
      );

      expect(metrics.totalRevenue, 400.0);
      expect(metrics.completedBillsCount, 1);
      expect(metrics.voidedBillsCount, 1);
      expect(metrics.totalPacketsSold, 2);
      expect(metrics.cashTotal, 400.0);
    });

    test('Applies Outlet Filter correctly', () {
      final now = DateTime.now();

      final jaipurSale = Sale(
        id: 'sale-j',
        locationId: LocationConstants.jaipurId,
        billNumber: 'BILL-J1',
        paymentMethod: 'CASH',
        totalAmount: 500.0,
        status: 'COMPLETED',
        productId: productA.id,
        quantity: 2,
        soldAt: now,
        createdAt: now,
      );

      final neemranaSale = Sale(
        id: 'sale-n',
        locationId: LocationConstants.neemranaId,
        billNumber: 'BILL-N1',
        paymentMethod: 'UPI',
        totalAmount: 300.0,
        status: 'COMPLETED',
        productId: productB.id,
        quantity: 1,
        soldAt: now,
        createdAt: now,
      );

      final allSales = [jaipurSale, neemranaSale];

      // 1. Filter by Jaipur
      final jaipurMetrics = OwnerMetricsCalculator.compute(
        sales: allSales,
        products: testProducts,
        storeInventories: [],
        outletFilter: OutletFilter.jaipur,
      );
      expect(jaipurMetrics.totalRevenue, 500.0);
      expect(jaipurMetrics.completedBillsCount, 1);
      expect(jaipurMetrics.cashTotal, 500.0);
      expect(jaipurMetrics.upiTotal, 0.0);
      expect(jaipurMetrics.totalPacketsSold, 2);

      // 2. Filter by Neemrana
      final neemranaMetrics = OwnerMetricsCalculator.compute(
        sales: allSales,
        products: testProducts,
        storeInventories: [],
        outletFilter: OutletFilter.neemrana,
      );
      expect(neemranaMetrics.totalRevenue, 300.0);
      expect(neemranaMetrics.completedBillsCount, 1);
      expect(neemranaMetrics.cashTotal, 0.0);
      expect(neemranaMetrics.upiTotal, 300.0);
      expect(neemranaMetrics.totalPacketsSold, 1);
    });

    test('Identifies sold vs. unsold products in the period correctly', () {
      final now = DateTime.now();

      final sale = Sale(
        id: 'sale-1',
        locationId: LocationConstants.jaipurId,
        billNumber: 'BILL-01',
        paymentMethod: 'CASH',
        totalAmount: 250.0,
        status: 'COMPLETED',
        productId: productA.id,
        quantity: 1,
        soldAt: now,
        createdAt: now,
      );

      final metrics = OwnerMetricsCalculator.compute(
        sales: [sale],
        products: testProducts,
        storeInventories: [],
      );

      expect(metrics.allProducts.length, 3);
      expect(metrics.soldProducts.length, 1);
      expect(metrics.soldProducts.first.productId, productA.id);
      expect(metrics.soldProducts.first.packetsSold, 1);

      expect(metrics.unsoldProducts.length, 2);
      final unsoldIds = metrics.unsoldProducts.map((p) => p.productId).toSet();
      expect(unsoldIds.contains(productB.id), isTrue);
      expect(unsoldIds.contains(productC.id), isTrue);
    });

    test('Cost accounting: calculates COGS, gross profit, and margin when cost data exists', () {
      final now = DateTime.now();

      final saleA = Sale(
        id: 'sale-1',
        locationId: LocationConstants.jaipurId,
        billNumber: 'BILL-01',
        paymentMethod: 'CASH',
        totalAmount: 500.0,
        status: 'COMPLETED',
        productId: productA.id,
        quantity: 2, // 2 units @ 250 selling price
        items: [
          SaleItem(
            id: 'item-1',
            saleId: 'sale-1',
            productId: productA.id,
            quantity: 2,
            unitPrice: 250.0,
            createdAt: now,
          ),
        ],
        soldAt: now,
        createdAt: now,
      );

      // Known cost per packet: productA costs 150.0 to produce
      final knownCosts = {
        productA.id: 150.0,
      };

      final metrics = OwnerMetricsCalculator.compute(
        sales: [saleA],
        products: testProducts,
        storeInventories: [],
        productUnitCosts: knownCosts,
      );

      expect(metrics.hasReliableCostData, true);
      expect(metrics.totalRevenue, 500.0);
      expect(metrics.totalCogs, 300.0); // 2 * 150.0
      expect(metrics.totalGrossProfit, 200.0); // 500.0 - 300.0
      expect(metrics.grossMarginPercent, 40.0); // (200 / 500) * 100 = 40%

      final prodAMetric = metrics.soldProducts.first;
      expect(prodAMetric.unitCost, 150.0);
      expect(prodAMetric.cogs, 300.0);
      expect(prodAMetric.grossProfit, 200.0);
      expect(prodAMetric.grossMarginPercent, 40.0);
    });

    test('Cost accounting: cleanly marks figures as unavailable when cost data does not exist (never fabricates)', () {
      final now = DateTime.now();

      final saleA = Sale(
        id: 'sale-1',
        locationId: LocationConstants.jaipurId,
        billNumber: 'BILL-01',
        paymentMethod: 'CASH',
        totalAmount: 500.0,
        status: 'COMPLETED',
        productId: productA.id,
        quantity: 2,
        soldAt: now,
        createdAt: now,
      );

      // No cost map provided
      final metrics = OwnerMetricsCalculator.compute(
        sales: [saleA],
        products: testProducts,
        storeInventories: [],
        productUnitCosts: null,
      );

      expect(metrics.hasReliableCostData, false);
      expect(metrics.totalCogs, isNull);
      expect(metrics.totalGrossProfit, isNull);
      expect(metrics.grossMarginPercent, isNull);

      final prodAMetric = metrics.soldProducts.first;
      expect(prodAMetric.unitCost, isNull);
      expect(prodAMetric.cogs, isNull);
      expect(prodAMetric.grossProfit, isNull);
      expect(prodAMetric.grossMarginPercent, isNull);
      expect(prodAMetric.hasReliableCost, false);
    });

    test('Verified production sample: BILL-010012 to BILL-010016 and Jaipur tulsi inventory (99 pkts)', () {
      final now = DateTime.now();

      final tulsiProduct = Product(
        id: 'prod-tulsi-uuid',
        name: 'Tulsi Ark 50ml',
        packageSize: '50ml',
        sku: 'KV-TUL-050',
        active: true,
        createdAt: now.subtract(const Duration(days: 30)),
      );

      final secondProduct = Product(
        id: 'prod-triphala-uuid',
        name: 'Triphala Churna 250g',
        packageSize: '250g',
        sku: 'KV-TRI-250',
        active: true,
        createdAt: now.subtract(const Duration(days: 30)),
      );

      final products = [tulsiProduct, secondProduct];

      // Current inventory state: Jaipur tulsi at 99, other 3 rows at 0
      final storeInventories = [
        StoreInventory(
          id: 'inv-jaipur-tulsi',
          locationId: LocationConstants.jaipurId,
          productId: tulsiProduct.id,
          currentQuantity: 99,
          updatedAt: now,
        ),
        StoreInventory(
          id: 'inv-jaipur-second',
          locationId: LocationConstants.jaipurId,
          productId: secondProduct.id,
          currentQuantity: 0,
          updatedAt: now,
        ),
        StoreInventory(
          id: 'inv-neemrana-tulsi',
          locationId: LocationConstants.neemranaId,
          productId: tulsiProduct.id,
          currentQuantity: 0,
          updatedAt: now,
        ),
        StoreInventory(
          id: 'inv-neemrana-second',
          locationId: LocationConstants.neemranaId,
          productId: secondProduct.id,
          currentQuantity: 0,
          updatedAt: now,
        ),
      ];

      // Recent completed sales verified from production
      final sale10012 = Sale(
        id: 'sale-010012',
        locationId: LocationConstants.jaipurId,
        billNumber: 'BILL-010012',
        paymentMethod: 'UPI',
        totalAmount: 100.0,
        status: 'COMPLETED',
        productId: tulsiProduct.id,
        quantity: 1,
        items: [
          SaleItem(
            id: 'item-010012',
            saleId: 'sale-010012',
            productId: tulsiProduct.id,
            quantity: 1,
            unitPrice: 100.0,
            createdAt: now.subtract(const Duration(hours: 5)),
          ),
        ],
        soldAt: now.subtract(const Duration(hours: 5)),
        createdAt: now.subtract(const Duration(hours: 5)),
      );

      final sale10013 = Sale(
        id: 'sale-010013',
        locationId: LocationConstants.jaipurId,
        billNumber: 'BILL-010013',
        paymentMethod: 'UPI',
        totalAmount: 100.0,
        status: 'COMPLETED',
        productId: tulsiProduct.id,
        quantity: 1,
        items: [
          SaleItem(
            id: 'item-010013',
            saleId: 'sale-010013',
            productId: tulsiProduct.id,
            quantity: 1,
            unitPrice: 100.0,
            createdAt: now.subtract(const Duration(hours: 4)),
          ),
        ],
        soldAt: now.subtract(const Duration(hours: 4)),
        createdAt: now.subtract(const Duration(hours: 4)),
      );

      final sale10014 = Sale(
        id: 'sale-010014',
        locationId: LocationConstants.neemranaId,
        billNumber: 'BILL-010014',
        paymentMethod: 'UPI',
        totalAmount: 125.0,
        status: 'COMPLETED',
        productId: tulsiProduct.id,
        quantity: 1,
        items: [
          SaleItem(
            id: 'item-010014',
            saleId: 'sale-010014',
            productId: tulsiProduct.id,
            quantity: 1,
            unitPrice: 125.0,
            createdAt: now.subtract(const Duration(hours: 3)),
          ),
        ],
        soldAt: now.subtract(const Duration(hours: 3)),
        createdAt: now.subtract(const Duration(hours: 3)),
      );

      final sale10015 = Sale(
        id: 'sale-010015',
        locationId: LocationConstants.jaipurId,
        billNumber: 'BILL-010015',
        paymentMethod: 'UPI',
        totalAmount: 125.0,
        status: 'COMPLETED',
        productId: tulsiProduct.id,
        quantity: 1,
        items: [
          SaleItem(
            id: 'item-010015',
            saleId: 'sale-010015',
            productId: tulsiProduct.id,
            quantity: 1,
            unitPrice: 125.0,
            createdAt: now.subtract(const Duration(hours: 2)),
          ),
        ],
        soldAt: now.subtract(const Duration(hours: 2)),
        createdAt: now.subtract(const Duration(hours: 2)),
      );

      final sale10016 = Sale(
        id: 'sale-010016',
        locationId: LocationConstants.neemranaId,
        billNumber: 'BILL-010016',
        paymentMethod: 'UPI',
        totalAmount: 125.0,
        status: 'COMPLETED',
        productId: tulsiProduct.id,
        quantity: 1,
        items: [
          SaleItem(
            id: 'item-010016',
            saleId: 'sale-010016',
            productId: tulsiProduct.id,
            quantity: 1,
            unitPrice: 125.0,
            createdAt: now.subtract(const Duration(hours: 1)),
          ),
        ],
        soldAt: now.subtract(const Duration(hours: 1)),
        createdAt: now.subtract(const Duration(hours: 1)),
      );

      final fiveBills = [sale10012, sale10013, sale10014, sale10015, sale10016];

      // --- Combined / All Stores Aggregations ---
      final combinedMetrics = OwnerMetricsCalculator.compute(
        sales: fiveBills,
        products: products,
        storeInventories: storeInventories,
        outletFilter: OutletFilter.all,
      );

      expect(combinedMetrics.completedBillsCount, 5);
      expect(combinedMetrics.voidedBillsCount, 0);
      expect(combinedMetrics.totalPacketsSold, 5);
      expect(combinedMetrics.totalRevenue, 575.0);
      expect(combinedMetrics.cashTotal, 0.0);
      expect(combinedMetrics.upiTotal, 575.0);
      expect(combinedMetrics.jaipurRevenue, 325.0);
      expect(combinedMetrics.neemranaRevenue, 250.0);
      expect(combinedMetrics.jaipurPacketsSold, 3);
      expect(combinedMetrics.neemranaPacketsSold, 2);
      expect(combinedMetrics.jaipurCurrentStock, 99);
      expect(combinedMetrics.neemranaCurrentStock, 0);
      expect(combinedMetrics.combinedCurrentStock, 99);

      // --- Jaipur Outlet Filter ---
      final jaipurMetrics = OwnerMetricsCalculator.compute(
        sales: fiveBills,
        products: products,
        storeInventories: storeInventories,
        outletFilter: OutletFilter.jaipur,
      );

      expect(jaipurMetrics.completedBillsCount, 3);
      expect(jaipurMetrics.totalPacketsSold, 3);
      expect(jaipurMetrics.totalRevenue, 325.0);
      expect(jaipurMetrics.cashTotal, 0.0);
      expect(jaipurMetrics.upiTotal, 325.0);
      expect(jaipurMetrics.jaipurCurrentStock, 99);

      // --- Neemrana Outlet Filter ---
      final neemranaMetrics = OwnerMetricsCalculator.compute(
        sales: fiveBills,
        products: products,
        storeInventories: storeInventories,
        outletFilter: OutletFilter.neemrana,
      );

      expect(neemranaMetrics.completedBillsCount, 2);
      expect(neemranaMetrics.totalPacketsSold, 2);
      expect(neemranaMetrics.totalRevenue, 250.0);
      expect(neemranaMetrics.cashTotal, 0.0);
      expect(neemranaMetrics.upiTotal, 250.0);
      expect(neemranaMetrics.neemranaCurrentStock, 0);

      // --- Older rows exist check: Dynamic calculation handles prior sales without capping ---
      final olderSale = Sale(
        id: 'sale-older',
        locationId: LocationConstants.jaipurId,
        billNumber: 'BILL-010011',
        paymentMethod: 'CASH',
        totalAmount: 500.0,
        status: 'COMPLETED',
        productId: tulsiProduct.id,
        quantity: 2,
        items: [
          SaleItem(
            id: 'item-older',
            saleId: 'sale-older',
            productId: tulsiProduct.id,
            quantity: 2,
            unitPrice: 250.0,
            createdAt: now.subtract(const Duration(days: 2)),
          ),
        ],
        soldAt: now.subtract(const Duration(days: 2)),
        createdAt: now.subtract(const Duration(days: 2)),
      );

      final allSalesWithOlder = [...fiveBills, olderSale];
      final metricsWithOlder = OwnerMetricsCalculator.compute(
        sales: allSalesWithOlder,
        products: products,
        storeInventories: storeInventories,
        outletFilter: OutletFilter.all,
      );

      // Dynamically aggregates all-time total (575 + 500 = 1075, 5 + 2 = 7 pkts, 500 Cash + 575 UPI)
      expect(metricsWithOlder.completedBillsCount, 6);
      expect(metricsWithOlder.totalPacketsSold, 7);
      expect(metricsWithOlder.totalRevenue, 1075.0);
      expect(metricsWithOlder.cashTotal, 500.0);
      expect(metricsWithOlder.upiTotal, 575.0);
    });
  });
}

