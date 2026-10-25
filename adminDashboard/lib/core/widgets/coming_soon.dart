import 'package:flutter/material.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';

import 'admin_scaffold.dart';

/// A module that a later phase builds (SRS §10).
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.title, required this.route, required this.phase});
  final String title;
  final String route;
  final int phase;

  @override
  Widget build(BuildContext context) => AdminScaffold(
        title: title,
        selectedRoute: route,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text('$title arrives in Phase $phase (SRS §10).', style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
      );
}
