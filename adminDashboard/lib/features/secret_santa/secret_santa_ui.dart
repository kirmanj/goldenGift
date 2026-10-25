import 'package:flutter/material.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/models/secret_santa_model.dart';

import '../stores/widgets/detail_widgets.dart';
import 'data/secret_santa_admin_repository.dart';

Color secretSantaStatusColor(SecretSantaStatus s) => switch (s) {
      SecretSantaStatus.open => AppColors.primaryDark,
      SecretSantaStatus.drawn => AppColors.success,
      SecretSantaStatus.closed => AppColors.textSecondary,
    };

class SecretSantaStatusPill extends StatelessWidget {
  const SecretSantaStatusPill(this.status, {super.key});
  final SecretSantaStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusPill(label: secretSantaStatusLabel(status), color: secretSantaStatusColor(status));
}

class SecretSantaTypePill extends StatelessWidget {
  const SecretSantaTypePill(this.type, {super.key});
  final SecretSantaType type;

  @override
  Widget build(BuildContext context) => StatusPill(label: secretSantaTypeLabel(type), color: AppColors.info);
}
