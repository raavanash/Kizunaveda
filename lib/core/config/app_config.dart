/// Application configuration loaded from compile-time environment variables.
abstract final class AppConfig {
  /// Supabase project URL provided via compile-time environment variable
  /// (`--dart-define=SUPABASE_URL=...` or `--dart-define=BASE_URL=...`).
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: String.fromEnvironment('BASE_URL'),
  );

  /// Supabase publishable key provided via compile-time environment variable
  /// (`--dart-define=SUPABASE_PUBLISHABLE_KEY=...`).
  static const String supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Explicit flag to enable GST billing mode. Defaults to false.
  /// Must be explicitly passed via `--dart-define=ENABLE_GST_BILLING=true`.
  static const bool enableGstBilling = bool.fromEnvironment(
    'ENABLE_GST_BILLING',
    defaultValue: false,
  );

  /// Configured Company GSTIN (GST Identification Number).
  /// Must be explicitly supplied via `--dart-define=GSTIN=...`. No dummy fallback allowed.
  static const String gstin = String.fromEnvironment('GSTIN');

  /// Configured Legal Business Name.
  static const String businessName = String.fromEnvironment(
    'BUSINESS_NAME',
    defaultValue: 'Kizuna Veda Ayurvedic Enterprise',
  );

  /// Configured Business Address.
  static const String businessAddress = String.fromEnvironment(
    'BUSINESS_ADDRESS',
    defaultValue: 'RIICO Industrial Area, Neemrana & Jaipur, Rajasthan',
  );

  /// Default GST tax rate percentage for packaged goods
  static const double defaultGstRate = 18.0;

  /// Returns true ONLY if GST billing is explicitly enabled AND valid GSTIN and business name details are provided.
  static bool get isGstConfigured =>
      enableGstBilling && gstin.trim().isNotEmpty && businessName.trim().isNotEmpty;

  /// Validates that all required compile-time environment variables are provided.
  /// Throws a descriptive [StateError] if any required variable is missing or empty.
  static void validate() {
    final missingVars = <String>[];
    if (supabaseUrl.trim().isEmpty) {
      missingVars.add('SUPABASE_URL (or BASE_URL)');
    }
    if (supabasePublishableKey.trim().isEmpty) {
      missingVars.add('SUPABASE_PUBLISHABLE_KEY');
    }

    if (missingVars.isNotEmpty) {
      throw StateError(
        'Missing required compile-time environment variable(s): ${missingVars.join(', ')}.\n'
        'Please pass them using --dart-define or --dart-define-from-file when running or building the app.\n'
        'Example:\n'
        '  flutter run --dart-define-from-file=supabase.local.json',
      );
    }
  }
}
