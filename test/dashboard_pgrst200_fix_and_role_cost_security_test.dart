import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/app/providers/inventory_provider.dart';
import 'package:kizuna_veda/core/constants/app_constants.dart';
import 'package:kizuna_veda/features/dashboard/presentation/screens/vyapar_dashboard_view.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/sale.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';

class FallbackTestInventoryRepo extends UnconnectedInventoryRepository {
  bool getSalesCalled = false;
  bool returnSimulatedSales = true;

  @override
  Future<List<Sale>> getSales({
    int limit = 50,
    int offset = 0,
    String? locationId,
  }) async {
    getSalesCalled = true;
    if (!returnSimulatedSales) {
      throw Exception(
          "PGRST200: Could not find a relationship between 'sale_items' and 'sale_item_procurement_costs' in the schema cache");
    }
    // Return sales with legacy items (without procurement costs join)
    return [
      Sale(
        id: 'sale-test-1',
        billNumber: 'BILL-1001',
        productId: 'prod-101',
        quantity: 2,
        totalAmount: 200.0,
        paymentMethod: 'CASH',
        soldAt: DateTime.now(),
        createdAt: DateTime.now(),
        locationId: LocationConstants.neemranaId,
        items: [
          SaleItem(
            id: 'item-101',
            saleId: 'sale-test-1',
            productId: 'prod-101',
            quantity: 2,
            unitPrice: 100.0,
            discount: 0.0,
            unitCost: 45.0, // Historical unit cost from sale_items column
            createdAt: DateTime.now(),
          ),
        ],
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dashboard PGRST200 Fix & Role-Based Cost Confidentiality Tests', () {
    test('1. SaleItem parses correctly with or without sale_item_procurement_costs join', () {
      // With joined sale_item_procurement_costs
      final jsonWithProc = {
        'id': 'item-1',
        'sale_id': 'sale-1',
        'product_id': 'prod-1',
        'quantity': 2,
        'unit_price': 150.0,
        'sale_item_procurement_costs': {'unit_cost': 60.0},
      };
      final item1 = SaleItem.fromJson(jsonWithProc);
      expect(item1.unitCost, 60.0);

      // Without joined table (falling back to legacy unit_cost column on sale_items)
      final jsonWithoutProc = {
        'id': 'item-2',
        'sale_id': 'sale-2',
        'product_id': 'prod-2',
        'quantity': 1,
        'unit_price': 100.0,
        'unit_cost': 45.0,
      };
      final item2 = SaleItem.fromJson(jsonWithoutProc);
      expect(item2.unitCost, 45.0);

      // Without any cost information (zero/null)
      final jsonNoCost = {
        'id': 'item-3',
        'sale_id': 'sale-3',
        'product_id': 'prod-3',
        'quantity': 3,
        'unit_price': 80.0,
      };
      final item3 = SaleItem.fromJson(jsonNoCost);
      expect(item3.unitCost, isNull);
    });

    testWidgets('2. Dashboard loads cleanly without error when sales load via fallback',
        (tester) async {
      final repo = FallbackTestInventoryRepo();
      final notifier = InventoryNotifier(repository: repo);
      await notifier.loadInventoryData();

      expect(notifier.errorMessage, isNull);
      expect(notifier.sales.length, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: InventoryProvider(
            notifier: notifier,
            child: const VyaparDashboardView(role: UserRole.owner),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify dashboard loaded properly and does NOT display error state
      expect(find.text('Unable to Load Dashboard Data'), findsNothing);
      expect(find.text('Total Sales Revenue'), findsOneWidget);
      expect(find.text('₹200'), findsWidgets);
    });

    testWidgets('3. Financial Performance & COGS/Gross Profit is strictly hidden for Cashier (Neemrana)',
        (tester) async {
      final repo = FallbackTestInventoryRepo();
      final notifier = InventoryNotifier(repository: repo);
      await notifier.loadInventoryData();

      await tester.pumpWidget(
        MaterialApp(
          home: InventoryProvider(
            notifier: notifier,
            child: const VyaparDashboardView(role: UserRole.neemrana),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sales Revenue & Collections are visible
      expect(find.text('Total Sales Revenue'), findsOneWidget);
      expect(find.text('Cash Collected'), findsOneWidget);

      // Financial Performance (COGS and Gross Profit) MUST NOT be rendered for Neemrana cashier
      expect(find.text('Financial Performance'), findsNothing);
      expect(find.text('Cost of Goods (COGS)'), findsNothing);
      expect(find.text('Gross Profit'), findsNothing);
    });

    testWidgets('4. Financial Performance & COGS/Gross Profit is strictly hidden for Cashier (Jaipur)',
        (tester) async {
      final repo = FallbackTestInventoryRepo();
      final notifier = InventoryNotifier(repository: repo);
      await notifier.loadInventoryData();

      await tester.pumpWidget(
        MaterialApp(
          home: InventoryProvider(
            notifier: notifier,
            child: const VyaparDashboardView(role: UserRole.jaipur),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Financial Performance (COGS and Gross Profit) MUST NOT be rendered for Jaipur cashier
      expect(find.text('Financial Performance'), findsNothing);
      expect(find.text('Cost of Goods (COGS)'), findsNothing);
      expect(find.text('Gross Profit'), findsNothing);
    });

    testWidgets('5. Financial Performance is visible for Owner when completed bills exist',
        (tester) async {
      final repo = FallbackTestInventoryRepo();
      final notifier = InventoryNotifier(repository: repo);
      await notifier.loadInventoryData();

      await tester.pumpWidget(
        MaterialApp(
          home: InventoryProvider(
            notifier: notifier,
            child: const VyaparDashboardView(role: UserRole.owner),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Owner DOES see Financial Performance card
      expect(find.text('Financial Performance'), findsOneWidget);
      expect(find.text('Cost of Goods (COGS)'), findsOneWidget);
      expect(find.text('Gross Profit'), findsOneWidget);
    });
  });
}
