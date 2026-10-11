import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../auth/presentation/controllers/auth_notifier.dart';
import '../../../navigation/presentation/screens/main_navigation_shell.dart';

/// Authenticated Home Screen & Executive Dashboard for OWNER role:
/// Powered by the Vyapar-inspired Navigation Shell with one-tap access across
/// Dashboard, Sales, Inventory, and More with a prominent New Sale CTA.
class OwnerHomeScreen extends StatelessWidget {
  final AuthNotifier authNotifier;
  final bool autoShowOnboarding;

  const OwnerHomeScreen({
    super.key,
    required this.authNotifier,
    this.autoShowOnboarding = true,
  });

  @override
  Widget build(BuildContext context) {
    return MainNavigationShell(
      role: UserRole.owner,
      authNotifier: authNotifier,
      autoShowOnboarding: autoShowOnboarding,
    );
  }
}
