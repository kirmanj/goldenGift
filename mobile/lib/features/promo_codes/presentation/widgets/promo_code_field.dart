import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/promo_rules.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/promo_code_model.dart';
import '../../../product_details/presentation/widgets/option_formatting.dart' show errorTextColor;
import '../../../wallet/presentation/widgets/wallet_ui.dart';
import '../../data/promo_repository.dart';
import '../providers/cart_pricing.dart';

/// Localized reason a code can't be used (SRS §5.10 / §6.9). Also used by
/// checkout for `placeOrder`'s `failed-precondition` reasons.
String promoRejectionMessage(AppLocalizations l10n, PromoRejection rejection, {int? minOrder}) => switch (rejection) {
      PromoRejection.notFound => l10n.promoNotFound,
      PromoRejection.inactive => l10n.promoInactive,
      PromoRejection.expired => l10n.promoExpired,
      PromoRejection.minOrder => l10n.promoMinOrderNotMet(CurrencyFormatter.format(minOrder ?? 0)),
      PromoRejection.usageLimit => l10n.promoUsageLimit,
      PromoRejection.perUserLimit => l10n.promoPerUserLimit,
      PromoRejection.firstOrderOnly => l10n.promoFirstOrderOnlyError,
      PromoRejection.notApplicable => l10n.promoNotApplicable,
    };

/// Cart promo code (SRS §5.10): a pill input + Apply while no code is
/// applied; then the applied code with its result (saving or the reason it
/// can't be used) and Remove. The code stays applied (and re-evaluates) when
/// the cart changes; it is persisted in `cart_promo`.
class PromoCodeField extends ConsumerStatefulWidget {
  const PromoCodeField({super.key});

  @override
  ConsumerState<PromoCodeField> createState() => _PromoCodeFieldState();
}

class _PromoCodeFieldState extends ConsumerState<PromoCodeField> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final code = PromoCodeModel.normalize(_controller.text);
    if (code.isEmpty) return;
    ref.read(appliedPromoProvider.notifier).apply(code);
    _controller.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final applied = ref.watch(appliedPromoProvider);
    if (applied != null) return _AppliedPromo(code: applied);

    final canApply = PromoCodeModel.normalize(_controller.text).isNotEmpty;
    final input = GGInput(
      key: const ValueKey('promo-code-input'),
      controller: _controller,
      hint: l10n.promoCodeHint,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.deny(RegExp(r'\s')),
        LengthLimitingTextInputFormatter(32),
      ],
      prefix: Padding(
        padding: const EdgeInsetsDirectional.only(start: AppSpacing.md - AppSpacing.xs),
        child: Icon(Icons.local_offer_outlined, size: 20, color: AppColors.gold(context)),
      ),
      onSubmitted: (_) => _apply(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Input + Apply on one line unless the (localized, scaled) label
        // leaves the input too narrow — then Apply goes full width below.
        final label = TextPainter(
          text: TextSpan(
            text: l10n.apply,
            style: AppTextStyles.button.copyWith(
              fontFamily: AppTextStyles.fontFamily(Localizations.localeOf(context)),
            ),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final buttonWidth = label.width + AppSpacing.lg * 2 + AppSpacing.xs;
        label.dispose();
        final stacked = constraints.maxWidth - buttonWidth - AppSpacing.sm < 150;
        final button = OutlineButton(
          key: const ValueKey('promo-apply'),
          label: l10n.apply,
          expand: stacked,
          onPressed: canApply ? _apply : null,
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [input, const SizedBox(height: AppSpacing.sm), button],
          );
        }
        return Row(
          children: [
            Expanded(child: input),
            const SizedBox(width: AppSpacing.sm),
            button,
          ],
        );
      },
    );
  }
}

class _AppliedPromo extends ConsumerWidget {
  const _AppliedPromo({required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final eval = ref.watch(promoEvaluationProvider);
    final result = ref.watch(currentPromoResultProvider);
    final failed = result == null && eval.hasError && !eval.isLoading;
    final checking = result == null && !failed;
    final rejection = result?.$2.rejection;
    final valid = result != null && result.$2.isValid;

    final Color border;
    if (valid) {
      border = AppColors.success.withValues(alpha: 0.6);
    } else if (rejection != null || failed) {
      border = AppColors.error.withValues(alpha: 0.6);
    } else {
      border = AppColors.line(context);
    }

    String? message;
    Color? messageColor;
    if (valid) {
      message = l10n.promoSaved(CurrencyFormatter.format(result.$2.discount));
      messageColor = successTextColor(context);
    } else if (rejection != null) {
      message = promoRejectionMessage(l10n, rejection, minOrder: result?.$1?.minOrder);
      messageColor = errorTextColor(context);
    } else if (failed) {
      message = l10n.somethingWentWrong;
      messageColor = errorTextColor(context);
    }

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const ValueKey('promo-applied'),
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.soft(context),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(
              valid
                  ? Icons.check_circle_rounded
                  : (rejection != null || failed)
                      ? Icons.error_outline_rounded
                      : Icons.local_offer_rounded,
              size: 22,
              color: valid
                  ? successTextColor(context)
                  : (rejection != null || failed)
                      ? errorTextColor(context)
                      : AppColors.gold(context),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    code,
                    style: AppTextStyles.label.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: AppColors.text(context),
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      message,
                      key: const ValueKey('promo-message'),
                      style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: messageColor),
                    ),
                  ],
                ],
              ),
            ),
            if (checking)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold(context)),
                ),
              ),
            TextButton(
              key: const ValueKey('promo-remove'),
              onPressed: () => ref.read(appliedPromoProvider.notifier).remove(),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.goldText(context),
                minimumSize: const Size.square(AppSpacing.minTapTarget),
              ),
              child: Text(l10n.remove, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
