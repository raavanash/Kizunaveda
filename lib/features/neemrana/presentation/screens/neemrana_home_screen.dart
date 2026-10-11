import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../auth/presentation/controllers/auth_notifier.dart';
import '../../../navigation/presentation/screens/main_navigation_shell.dart';

/// Authenticated Home Screen for NEEMRANA role powered by the Vyapar-inspired Navigation Shell:
/// Provides one-tap access across Dashboard, Sales, Inventory, and More with a prominent New Sale CTA.
class NeemranaHomeScreen extends StatelessWidget {
  final AuthNotifier authNotifier;
  final bool autoShowOnboarding;

  const NeemranaHomeScreen({
    super.key,
    required this.authNotifier,
    this.autoShowOnboarding = true,
  });

  @override
  Widget build(BuildContext context) {
    return MainNavigationShell(
      role: UserRole.neemrana,
      authNotifier: authNotifier,
      autoShowOnboarding: autoShowOnboarding,
    );
  }
}
