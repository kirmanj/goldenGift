import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/widgets.dart';
import '../providers/startup_decider.dart';

/// White (light) / black (dark) background with the gold logo while settings,
/// auth state and the profile load (SRS §5.1).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    final decision = await ref.read(startupDeciderProvider).decide();
    if (!mounted) return;
    switch (decision.destination) {
      case StartupDestination.maintenance:
        context.go(AppRoutes.maintenance);
      case StartupDestination.updateRequired:
        context.go(AppRoutes.updateRequired);
      case StartupDestination.onboarding:
        context.go(AppRoutes.onboarding);
      case StartupDestination.signUp:
        context.go(AppRoutes.signUp);
      case StartupDestination.signIn:
        context.go(AppRoutes.signIn);
      case StartupDestination.completeProfile:
        context.go(AppRoutes.completeProfile, extra: decision.prefill);
      case StartupDestination.main:
        context.go(AppRoutes.main);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.darkBackground : AppColors.white,
      body: const Center(child: GGLogo(size: 96)),
    );
  }
}
