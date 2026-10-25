import 'package:flutter/material.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/models/special_request_model.dart';

import '../stores/widgets/detail_widgets.dart';
import 'data/special_requests_admin_repository.dart';

Color specialRequestStatusColor(SpecialRequestStatus s) => switch (s) {
      SpecialRequestStatus.submitted => AppColors.info,
      SpecialRequestStatus.inReview => AppColors.warning,
      SpecialRequestStatus.quoted => AppColors.primaryDark,
      SpecialRequestStatus.accepted || SpecialRequestStatus.completed => AppColors.success,
      SpecialRequestStatus.rejected => AppColors.error,
    };

class SpecialRequestStatusChip extends StatelessWidget {
  const SpecialRequestStatusChip(this.status, {super.key});
  final SpecialRequestStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusPill(label: specialRequestStatusLabel(status), color: specialRequestStatusColor(status));
}

class SpecialRequestTypeChip extends StatelessWidget {
  const SpecialRequestTypeChip(this.type, {super.key});
  final SpecialRequestType type;

  @override
  Widget build(BuildContext context) => StatusPill(
        label: specialRequestTypeLabel(type),
        color: type == SpecialRequestType.gift ? AppColors.primaryDark : AppColors.info,
      );
}

/// The first line of the request (inbox preview).
String firstLine(String text) {
  final line = text.trim().split('\n').first.trim();
  return line.length > 140 ? '${line.substring(0, 140)}…' : line;
}
