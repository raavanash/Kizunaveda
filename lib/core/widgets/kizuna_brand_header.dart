import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

class KizunaBrandHeader extends StatelessWidget {
  const KizunaBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: AppColors.accent, width: 2),
          ),
          child: const Center(
            child: Text(
              'KV',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'KIZUNA VEDA',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
                color: AppColors.primary,
              ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            'PRIVATE ENTERPRISE MOBILE PORTAL',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.accentDark,
            ),
          ),
        ),
      ],
    );
  }
}
