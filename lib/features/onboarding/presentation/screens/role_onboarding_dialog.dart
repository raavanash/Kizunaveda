import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/kizuna_brand_header.dart';
import '../../domain/entities/onboarding_step.dart';

/// Interactive First-Time User Guide dialog tailored to the authenticated user's role.
class RoleOnboardingDialog extends StatefulWidget {
  final UserRole role;
  final void Function(int tabIndex)? onNavigateToTab;
  final VoidCallback? onOpenNewSale;
  final VoidCallback? onOpenHelpGuide;
  final VoidCallback? onFinish;

  const RoleOnboardingDialog({
    super.key,
    required this.role,
    this.onNavigateToTab,
    this.onOpenNewSale,
    this.onOpenHelpGuide,
    this.onFinish,
  });

  /// Present the role-based onboarding walkthrough as a modal sheet/dialog.
  static Future<void> show(
    BuildContext context, {
    required UserRole role,
    void Function(int tabIndex)? onNavigateToTab,
    VoidCallback? onOpenNewSale,
    VoidCallback? onOpenHelpGuide,
    VoidCallback? onFinish,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RoleOnboardingDialog(
        role: role,
        onNavigateToTab: onNavigateToTab,
        onOpenNewSale: onOpenNewSale,
        onOpenHelpGuide: onOpenHelpGuide,
        onFinish: onFinish,
      ),
    );
  }

  @override
  State<RoleOnboardingDialog> createState() => _RoleOnboardingDialogState();
}

class _RoleOnboardingDialogState extends State<RoleOnboardingDialog> {
  int _currentStepIndex = 0;
  late final List<OnboardingStep> _steps;

  @override
  void initState() {
    super.initState();
    _steps = OnboardingStep.getStepsForRole(widget.role);
  }

  Color get _themeColor {
    switch (widget.role) {
      case UserRole.neemrana:
        return AppColors.roleNeemrana;
      case UserRole.jaipur:
        return AppColors.roleJaipur;
      case UserRole.owner:
        return AppColors.roleOwner;
    }
  }

  void _nextStep() {
    if (_currentStepIndex < _steps.length - 1) {
      setState(() => _currentStepIndex++);
    } else {
      _finishGuide();
    }
  }

  void _previousStep() {
    if (_currentStepIndex > 0) {
      setState(() => _currentStepIndex--);
    }
  }

  void _skipGuide() {
    widget.onFinish?.call();
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _finishGuide() {
    widget.onFinish?.call();
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _handleShortcut(OnboardingShortcutType type) {
    widget.onFinish?.call();
    Navigator.of(context, rootNavigator: true).pop();

    switch (type) {
      case OnboardingShortcutType.dashboard:
        widget.onNavigateToTab?.call(0);
        break;
      case OnboardingShortcutType.sales:
        widget.onNavigateToTab?.call(1);
        break;
      case OnboardingShortcutType.inventory:
        widget.onNavigateToTab?.call(2);
        break;
      case OnboardingShortcutType.pos:
        widget.onOpenNewSale?.call();
        break;
      case OnboardingShortcutType.help:
        widget.onOpenHelpGuide?.call();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_currentStepIndex];
    final totalSteps = _steps.length;
    final progress = (_currentStepIndex + 1) / totalSteps;

    return Dialog(
      key: const Key('onboarding_dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: _themeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _themeColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    widget.role.displayName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _themeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Guide',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                key: const Key('onboarding_skip_button'),
                onPressed: _skipGuide,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(6),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey.shade200,
                color: _themeColor,
                minHeight: 4,
              ),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Step Counter Pill
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Step ${_currentStepIndex + 1} of $totalSteps',
                        key: const Key('onboarding_step_indicator'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _themeColor,
                        ),
                      ),
                      Row(
                        children: List.generate(totalSteps, (index) {
                          final isCurrent = index == _currentStepIndex;
                          final isDone = index < _currentStepIndex;
                          return Container(
                            width: isCurrent ? 18 : 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              color: isCurrent
                                  ? _themeColor
                                  : (isDone
                                      ? _themeColor.withValues(alpha: 0.4)
                                      : Colors.grey.shade300),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),

                // Scrollable Step Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        // Branding Header on First Step
                        if (_currentStepIndex == 0) ...[
                          const KizunaBrandHeader(),
                          const SizedBox(height: 16),
                        ],

                        // Step Visual Icon Container
                        Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _themeColor.withValues(alpha: 0.12),
                            ),
                            child: Icon(
                              step.icon,
                              size: 32,
                              color: _themeColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Title & Subtitle
                        Text(
                          step.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          step.subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Bullet Points
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: step.bulletPoints.map((point) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      size: 16,
                                      color: _themeColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        point,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade800,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        // Optional Shortcut Action
                        if (step.shortcutLabel != null &&
                            step.shortcutType != null) ...[
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            key: const Key('onboarding_shortcut_button'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _themeColor,
                              side: BorderSide(color: _themeColor),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.arrow_outward_rounded,
                                size: 16),
                            label: Text(
                              step.shortcutLabel!,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () =>
                                _handleShortcut(step.shortcutType!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Bottom Action Controls
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      if (_currentStepIndex > 0)
                        OutlinedButton(
                          key: const Key('onboarding_back_button'),
                          onPressed: _previousStep,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          child: const Text('Back'),
                        )
                      else
                        const SizedBox.shrink(),
                      if (_currentStepIndex > 0) const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          key: _currentStepIndex == totalSteps - 1
                              ? const Key('onboarding_finish_button')
                              : const Key('onboarding_next_button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _themeColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: _nextStep,
                          child: Text(
                            _currentStepIndex == totalSteps - 1
                                ? 'Finish Guide'
                                : 'Continue',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
