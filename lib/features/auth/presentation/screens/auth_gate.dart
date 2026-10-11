import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/kizuna_brand_header.dart';
import '../../../jaipur/presentation/screens/jaipur_home_screen.dart';
import '../../../neemrana/presentation/screens/neemrana_home_screen.dart';
import '../../../owner/presentation/screens/owner_home_screen.dart';
import '../controllers/auth_notifier.dart';
import 'login_screen.dart';

/// Role-aware routing gate that determines screen destination based on session & role.
class AuthGate extends StatelessWidget {
  final AuthNotifier authNotifier;

  const AuthGate({super.key, required this.authNotifier});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: authNotifier,
      builder: (context, _) {
        if (authNotifier.status == AuthStatus.loading &&
            !authNotifier.isAuthenticated) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  KizunaBrandHeader(),
                  SizedBox(height: 32),
                  CircularProgressIndicator(color: AppColors.primary),
                ],
              ),
            ),
          );
        }

        if (!authNotifier.isAuthenticated) {
          return LoginScreen(authNotifier: authNotifier);
        }

        // Authenticated Session: Route by Role
        final role = authNotifier.currentRole;
        switch (role) {
          case UserRole.owner:
            return OwnerHomeScreen(authNotifier: authNotifier);
          case UserRole.neemrana:
            return NeemranaHomeScreen(authNotifier: authNotifier);
          case UserRole.jaipur:
          case null:
            return JaipurHomeScreen(authNotifier: authNotifier);
        }
      },
    );
  }
}
