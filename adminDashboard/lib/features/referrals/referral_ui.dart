import 'package:flutter/material.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/referral_model.dart';
import 'package:golden_gift/models/user_model.dart';

import '../categories/categories_screen.dart' show InfoTag;

String referralStatusLabel(ReferralStatus s) => switch (s) {
      ReferralStatus.pending => 'Pending',
      ReferralStatus.completed => 'Completed',
      ReferralStatus.cancelled => 'Cancelled',
    };

Color referralStatusColor(ReferralStatus s) => switch (s) {
      ReferralStatus.pending => AppColors.info,
      ReferralStatus.completed => AppColors.success,
      ReferralStatus.cancelled => AppColors.error,
    };

class ReferralStatusChip extends StatelessWidget {
  const ReferralStatusChip(this.status, {super.key});
  final ReferralStatus status;

  @override
  Widget build(BuildContext context) => InfoTag(referralStatusLabel(status), color: referralStatusColor(status));
}

/// One abuse signal on a referral (SRS §5.19): stored by the functions in
/// `referrals.flags`, or worked out here from the two users' docs.
class ReferralFlag {
  const ReferralFlag(this.key, {this.computed = false});
  final String key;

  /// True when the dashboard detected it (not stored on the referral).
  final bool computed;

  String get label {
    final base = switch (key) {
      'sameDevice' => 'Same device',
      'monthlyCap' => 'Monthly cap reached',
      'selfReferral' => 'Self-referral',
      'blocked' => 'Blocked user',
      _ => key,
    };
    return computed ? '$base (detected)' : base;
  }

  @override
  bool operator ==(Object other) => other is ReferralFlag && other.key == key && other.computed == computed;

  @override
  int get hashCode => Object.hash(key, computed);
}

/// Stored flags, plus "same device" when both users carry the same `deviceId`
/// and the functions didn't already flag it, plus "blocked" when either user
/// is blocked now.
List<ReferralFlag> referralFlags(ReferralModel r, {UserModel? referrer, UserModel? referred}) {
  final flags = [for (final f in r.flags) ReferralFlag(f)];
  final a = referrer?.deviceId;
  final b = referred?.deviceId;
  if (!r.flags.contains('sameDevice') && a != null && a.isNotEmpty && a == b) {
    flags.add(const ReferralFlag('sameDevice', computed: true));
  }
  if (!r.flags.contains('blocked') && ((referrer?.isBlocked ?? false) || (referred?.isBlocked ?? false))) {
    flags.add(const ReferralFlag('blocked', computed: true));
  }
  if (!r.flags.contains('selfReferral') && r.referrerUid.isNotEmpty && r.referrerUid == r.referredUid) {
    flags.add(const ReferralFlag('selfReferral', computed: true));
  }
  return flags;
}

class ReferralFlagChips extends StatelessWidget {
  const ReferralFlagChips({super.key, required this.flags});
  final List<ReferralFlag> flags;

  @override
  Widget build(BuildContext context) => flags.isEmpty
      ? Text('—', style: TextStyle(color: AppColors.textMuted(context)))
      : Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
          for (final f in flags)
            Tooltip(
              message: f.computed
                  ? 'Detected by the dashboard from the users\' documents'
                  : 'Raised by the referral functions',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.warning_amber_rounded, size: 12, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.xxs),
                  Flexible(
                    child: Text(f.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ),
        ]);
}

/// ✓ / — for a paid bonus.
class PaidMark extends StatelessWidget {
  const PaidMark(this.paid, {super.key, required this.label});
  final bool paid;
  final String label;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: '$label ${paid ? 'paid' : 'not paid'}',
        child: Icon(paid ? Icons.check_circle : Icons.remove_circle_outline,
            size: 18, color: paid ? AppColors.success : AppColors.textMuted(context)),
      );
}
