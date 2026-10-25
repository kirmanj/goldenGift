import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../../core/providers/session_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';

/// Three slides — Personalize · Deliver · Earn credits — with Skip; shown once
/// per install (SRS §5.1), then Sign Up.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  static const _count = 3;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(onboardingDoneProvider.notifier).set(true);
    if (mounted) context.go(AppRoutes.signUp);
  }

  void _next() {
    if (_index == _count - 1) {
      _finish();
    } else {
      _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final slides = [
      (Icons.brush_rounded, l10n.onboardingTitle1, l10n.onboardingBody1),
      (Icons.local_shipping_rounded, l10n.onboardingTitle2, l10n.onboardingBody2),
      (Icons.stars_rounded, l10n.onboardingTitle3, l10n.onboardingBody3),
    ];
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm, top: AppSpacing.sm),
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted(context),
                    minimumSize: const Size(64, AppSpacing.minTapTarget),
                  ),
                  child: Text(l10n.skip),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _count,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _Slide(icon: slides[i].$1, title: slides[i].$2, body: slides[i].$3),
              ),
            ),
            // Decorative (8 px dots): Next / Skip are the accessible controls.
            ExcludeSemantics(
              child: SmoothPageIndicator(
                controller: _pages,
                count: _count,
                effect: ExpandingDotsEffect(
                  dotHeight: 8,
                  dotWidth: 8,
                  activeDotColor: AppColors.gold(context),
                  dotColor: AppColors.line(context),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenHorizontal, AppSpacing.lg, AppSpacing.screenHorizontal, AppSpacing.md),
              child: PrimaryButton(
                label: _index == _count - 1 ? l10n.getStarted : l10n.next,
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xl),
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
            child: Center(
              child: Container(
                width: 104,
                height: 104,
                decoration: const BoxDecoration(gradient: AppColors.goldShimmer, shape: BoxShape.circle),
                child: Icon(icon, size: 52, color: AppColors.textOnPrimary),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(title,
              textAlign: TextAlign.center, style: AppTextStyles.heading2.copyWith(color: AppColors.text(context))),
          const SizedBox(height: AppSpacing.md),
          Text(body,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted(context))),
        ],
      ),
    );
  }
}
