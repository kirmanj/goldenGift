import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/gift_card_model.dart';

/// `#RRGGBB` / `RRGGBB` / `#AARRGGBB` → colour; null when missing or invalid.
Color? parseHexColor(String? hex) {
  final v = (hex ?? '').trim().replaceFirst('#', '');
  if (v.length != 6 && v.length != 8) return null;
  final n = int.tryParse(v, radix: 16);
  if (n == null) return null;
  return Color(v.length == 6 ? 0xFF000000 | n : n);
}

/// The template's two colours, or the gold shimmer (SRS §5.4 item 6, §6.10).
LinearGradient giftCardGradientFor(String? start, String? end) {
  final s = parseHexColor(start);
  final e = parseHexColor(end);
  if (s == null || e == null) return AppColors.giftCardGradient;
  return LinearGradient(colors: [s, e], begin: Alignment.topLeft, end: Alignment.bottomRight);
}

LinearGradient templateGradient(GiftCardTemplateModel t) => giftCardGradientFor(t.gradientStart, t.gradientEnd);

/// Text on gold is always dark (`textOnPrimary`); a template with dark custom
/// colours gets white text instead so it keeps its contrast.
Color giftCardForeground(Gradient gradient) {
  final colors = gradient.colors;
  final luminance = colors.fold<double>(0, (sum, c) => sum + c.computeLuminance()) / colors.length;
  return luminance > 0.3 ? AppColors.textOnPrimary : AppColors.white;
}

/// "15,000 IQD" when the template sells one amount, else "From 15,000 IQD".
String? templateAmountLabel(AppLocalizations l10n, GiftCardTemplateModel t) {
  final options = [...t.presetAmounts, if (t.allowsCustomAmount) t.minAmount]..sort();
  if (options.isEmpty) return null;
  if (t.presetAmounts.length == 1 && !t.allowsCustomAmount) return CurrencyFormatter.format(options.first);
  return l10n.giftCardFrom(CurrencyFormatter.format(options.first));
}

/// The gold-shimmer card (Home tiles, shop, Designer preview, My Gift Cards):
/// gift icon + "GIFT CARD", the template name and the amount; the Designer
/// adds the recipient, message and photo. Grows with large text; [compact]
/// tiles live in a fixed-height row (see [compactHeight]).
class GiftCardFace extends StatelessWidget {
  const GiftCardFace({
    super.key,
    required this.gradient,
    required this.title,
    this.amount,
    this.artworkUrl,
    this.photo,
    this.recipient,
    this.message,
    this.compact = false,
    this.aspectRatio = 1.6,
  });

  final LinearGradient gradient;
  final String title;

  /// Already formatted ("25,000 IQD", "From 15,000 IQD").
  final String? amount;
  final String? artworkUrl;

  /// The customer's photo (Designer preview).
  final ImageProvider? photo;
  final String? recipient;
  final String? message;
  final bool compact;

  /// Minimum width / height ratio (the card grows taller with large text).
  final double aspectRatio;

  static const double _compactPad = AppSpacing.sm + AppSpacing.xs;

  /// Height of a [compact] tile at the current text scale.
  static double compactHeight(BuildContext context) {
    final s = MediaQuery.textScalerOf(context);
    return _compactPad * 2 + s.scale(12) * 1.4 + AppSpacing.sm + s.scale(15) * 1.35 + s.scale(18) * 1.35 + AppSpacing.md;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fg = giftCardForeground(gradient);
    final pad = compact ? _compactPad : AppSpacing.md + AppSpacing.xs;
    final hasArtwork = artworkUrl != null && artworkUrl!.isNotEmpty;
    final thumb = compact ? 36.0 : 56.0;

    final header = Row(
      children: [
        Icon(Icons.card_giftcard_rounded, size: compact ? 18 : 22, color: fg),
        const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
        Expanded(
          child: Text(
            l10n.giftCardLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              height: 1.4,
              color: fg,
            ),
          ),
        ),
        if (photo != null)
          _Thumb(size: thumb, child: Image(image: photo!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _blank(fg)))
        else if (hasArtwork)
          _Thumb(size: thumb, child: GGNetworkImage(url: artworkUrl, fallbackColor: fg.withValues(alpha: 0.12))),
      ],
    );

    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, height: 1.35, color: fg),
        ),
        if (amount != null)
          Text(
            amount!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
            style: (compact ? AppTextStyles.heading3 : AppTextStyles.heading2).copyWith(height: 1.35, color: fg),
          ),
        if (!compact && (recipient ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.giftCardTo(recipient!.trim()),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700, color: fg),
          ),
        ],
        if (!compact && (message ?? '').trim().isNotEmpty)
          Text(
            message!.trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium.copyWith(fontStyle: FontStyle.italic, color: fg.withValues(alpha: 0.9)),
          ),
      ],
    );

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
      final minHeight = compact ? 0.0 : width / aspectRatio;
      return Container(
        constraints: BoxConstraints(minHeight: minHeight),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(compact ? AppRadius.md : AppRadius.lg),
          boxShadow: AppColors.isDark(context) ? null : AppElevation.soft,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Metallic sheen + a faint oversized gift icon on the end side.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: const [0.0, 0.45, 0.55, 1.0],
                      colors: [
                        AppColors.white.withValues(alpha: 0),
                        AppColors.white.withValues(alpha: 0),
                        AppColors.white.withValues(alpha: 0.18),
                        AppColors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              end: compact ? -14 : -18,
              bottom: compact ? -18 : -24,
              child: ExcludeSemantics(
                child: Icon(Icons.redeem_rounded, size: compact ? 76 : 120, color: fg.withValues(alpha: 0.08)),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(pad),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: compact ? 0 : (minHeight - pad * 2).clamp(0, double.infinity)),
                child: Column(
                  mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
                    details,
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _blank(Color fg) => ColoredBox(color: fg.withValues(alpha: 0.12));
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.size, required this.child});
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        margin: const EdgeInsetsDirectional.only(start: AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.white.withValues(alpha: 0.7), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}
