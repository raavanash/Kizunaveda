/// System-wide constants for Kizuna Veda Mobile Application.
class AppConstants {
  AppConstants._();

  static const String appName = 'Kizuna Veda';
  static const String appTagline = 'Private Mobile Enterprise Platform';
  static const String appVersion = '1.0.0 (Foundation)';
}

/// Physical Location Constants for Neemrana and Jaipur facilities.
abstract class LocationConstants {
  static const String neemranaId = '11111111-1111-1111-1111-111111111111';
  static const String jaipurId = '22222222-2222-2222-2222-222222222222';
}

/// Key User Roles for Kizuna Veda Operations.
enum UserRole {
  owner,
  neemrana,
  jaipur,
}

extension UserRoleExtension on UserRole {
  String get displayName {
    switch (this) {
      case UserRole.owner:
        return 'Owner / Admin';
      case UserRole.neemrana:
        return 'Neemrana Facility';
      case UserRole.jaipur:
        return 'Kizuna Veda Jaipur';
    }
  }

  String get description {
    switch (this) {
      case UserRole.owner:
        return 'Full oversight of inventory, transfers, sales, and analytics.';
      case UserRole.neemrana:
        return 'Raw material intake, batch processing, packaging & dispatch.';
      case UserRole.jaipur:
        return 'Shipment verification, stock reception, sales & PDF billing.';
    }
  }

  String get locationTag {
    switch (this) {
      case UserRole.owner:
        return 'HQ / Remote Operations';
      case UserRole.neemrana:
        return 'Manufacturing Unit • Neemrana';
      case UserRole.jaipur:
        return 'Retail Outlet • Jaipur';
    }
  }
}
