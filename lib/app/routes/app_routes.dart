import 'package:flutter/material.dart';
import '../../features/jaipur/presentation/screens/ebill_history_screen.dart';
import '../../features/owner/presentation/screens/in_transit_stock_screen.dart';
import '../../features/owner/presentation/screens/jaipur_stock_screen.dart';
import '../../features/owner/presentation/screens/neemrana_stock_screen.dart';
import '../../features/owner/presentation/screens/user_management_screen.dart';

/// Centralized Application Routes and Typed Navigation Helpers.
abstract class AppRoutes {
  static const String ownerNeemranaStock = '/owner/neemrana-stock';
  static const String ownerJaipurStock = '/owner/jaipur-stock';
  static const String ownerInTransitStock = '/owner/in-transit-stock';
  static const String ownerUserManagement = '/owner/user-management';
  static const String ebillHistory = '/ebill-history';

  static Map<String, WidgetBuilder> get routes => {
        ownerNeemranaStock: (context) => const NeemranaStockScreen(),
        ownerJaipurStock: (context) => const JaipurStockScreen(),
        ownerInTransitStock: (context) => const InTransitStockScreen(),
        ownerUserManagement: (context) => const UserManagementScreen(),
        ebillHistory: (context) => const EBillHistoryScreen(),
      };

  static Future<void> navigateToNeemranaStock(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NeemranaStockScreen(),
        settings: const RouteSettings(name: ownerNeemranaStock),
      ),
    );
  }

  static Future<void> navigateToJaipurStock(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const JaipurStockScreen(),
        settings: const RouteSettings(name: ownerJaipurStock),
      ),
    );
  }

  static Future<void> navigateToInTransitStock(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const InTransitStockScreen(),
        settings: const RouteSettings(name: ownerInTransitStock),
      ),
    );
  }

  static Future<void> navigateToUserManagement(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const UserManagementScreen(),
        settings: const RouteSettings(name: ownerUserManagement),
      ),
    );
  }

  static Future<void> navigateToEBillHistory(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const EBillHistoryScreen(),
        settings: const RouteSettings(name: ebillHistory),
      ),
    );
  }
}
