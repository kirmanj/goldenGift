import 'package:flutter/material.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/gift_card_model.dart';

import '../stores/widgets/detail_widgets.dart';
import 'data/gift_cards_admin_repository.dart';

Color giftCardStatusColor(GiftCardStatus s) => switch (s) {
      GiftCardStatus.pending => AppColors.info,
      GiftCardStatus.sent => AppColors.primaryDark,
      GiftCardStatus.redeemed => AppColors.success,
      GiftCardStatus.expired => AppColors.warning,
      GiftCardStatus.disabled => AppColors.error,
    };

class GiftCardStatusChip extends StatelessWidget {
  const GiftCardStatusChip(this.status, {super.key});
  final GiftCardStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusPill(label: giftCardStatusLabel(status), color: giftCardStatusColor(status));
}

/// The gradient of a template / card: its own colours, or the gold shimmer.
LinearGradient giftCardGradient(String? start, String? end) {
  final a = colorFromHex(start), b = colorFromHex(end);
  if (a == null || b == null) return AppColors.giftCardGradient;
  return LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight);
}

/// Text on the card: dark on light gradients (always on gold), white on dark ones.
Color giftCardTextColor(LinearGradient gradient) {
  final luminance = gradient.colors.map((c) => c.computeLuminance()).reduce((a, b) => a + b) / gradient.colors.length;
  return luminance > 0.35 ? AppColors.textOnPrimary : AppColors.white;
}

/// Live preview of a gift card (template editor, issued-card drawer).
class GiftCardPreview extends StatelessWidget {
  const GiftCardPreview({
    super.key,
    required this.name,
    this.amount,
    this.gradientStart,
    this.gradientEnd,
    this.artworkUrl,
    this.code,
    this.width = 300,
  });

  final String name;
  final int? amount;
  final String? gradientStart;
  final String? gradientEnd;
  final String? artworkUrl;
  final String? code;
  final double width;

  @override
  Widget build(BuildContext context) {
    final gradient = giftCardGradient(gradientStart, gradientEnd);
    final fg = giftCardTextColor(gradient);
    final art = artworkUrl;
    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: 1.6,
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: AppElevation.soft,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            if (art != null && art.isNotEmpty)
              PositionedDirectional(
                end: 0,
                top: 0,
                bottom: 0,
                width: width * 0.42,
                child: Opacity(
                  opacity: 0.9,
                  child: Image.network(art, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.card_giftcard, size: 16, color: fg),
                  const SizedBox(width: AppSpacing.xs),
                  Text('Golden Gift', style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
                const Spacer(),
                SizedBox(
                  width: width * (art == null || art.isEmpty ? 0.9 : 0.5),
                  child: Text(name.isEmpty ? 'Template name' : name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (amount != null)
                  Text(CurrencyFormatter.format(amount!),
                      style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w800)),
                if (code != null)
                  Text(code!, style: TextStyle(color: fg, fontSize: 12, letterSpacing: 1.5, fontFamily: 'monospace')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
