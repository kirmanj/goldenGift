import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../models/banner_model.dart';
import '../../products/data/product_query.dart';

/// What tapping a banner does (SRS §5.4 item 2, §6.8).
Future<void> openBannerAction(BuildContext context, BannerModel banner) async {
  final value = banner.actionValue.trim();
  if (value.isEmpty) return;
  switch (banner.actionType) {
    case BannerActionType.category:
      context.push(AppRoutes.productsFor(ProductQuery(categoryId: value)));
    case BannerActionType.product:
      context.push(AppRoutes.product(value));
    case BannerActionType.url:
      final uri = Uri.tryParse(value);
      if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    case BannerActionType.route:
      // Only in-app paths; anything else is ignored rather than crashing.
      if (value.startsWith('/')) context.push(value);
  }
}
