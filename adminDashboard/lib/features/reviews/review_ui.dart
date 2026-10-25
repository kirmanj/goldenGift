import 'package:flutter/material.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';

import '../orders/order_detail_panel.dart';
import '../stores/widgets/detail_widgets.dart';

/// 1–5 gold stars (outlined for the missing ones).
class ReviewStars extends StatelessWidget {
  const ReviewStars(this.rating, {super.key, this.size = 16});
  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$rating out of 5 stars',
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 1; i <= 5; i++)
            Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size, color: i <= rating ? AppColors.gold(context) : AppColors.textMuted(context)),
        ]),
      );
}

/// "Pending" (gold) / "Approved" (green) pill.
class ReviewApprovalPill extends StatelessWidget {
  const ReviewApprovalPill({super.key, required this.approved});
  final bool approved;

  @override
  Widget build(BuildContext context) =>
      StatusPill(label: approved ? 'Approved' : 'Pending', color: approved ? AppColors.success : AppColors.primaryDark);
}

/// Text that looks like a link (gold text, SRS §2.3) and runs [onTap].
class LinkText extends StatelessWidget {
  const LinkText(this.text, {super.key, required this.onTap, this.maxLines = 1});
  final String text;
  final VoidCallback onTap;
  final int maxLines;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.goldText(context),
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.goldText(context),
          ),
        ),
      );
}

/// The order a review belongs to, in a dialog (reuses the Orders detail panel).
Future<void> showOrderDialog(BuildContext context, String orderId) => showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: OrderDetailPanel(orderId: orderId, onClose: () => Navigator.pop(context)),
        ),
      ),
    );

/// First line of [text], at most [max] characters.
String reviewExcerpt(String text, {int max = 140}) {
  final line = text.trim().split('\n').first.trim();
  return line.length <= max ? line : '${line.substring(0, max).trimRight()}…';
}
