import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../l10n/l10n.dart';

/// Labels and icons of the gift types (SRS §5.8a), shared by the products
/// filter, Home "Shop for", Product Details and the Reels filter.
extension GiftAudienceUi on GiftAudience {
  String label(AppLocalizations l10n) => switch (this) {
        GiftAudience.men => l10n.giftForMen,
        GiftAudience.women => l10n.giftForWomen,
        GiftAudience.companies => l10n.giftForCompanies,
      };

  String tagline(AppLocalizations l10n) => switch (this) {
        GiftAudience.men => l10n.giftForMenTagline,
        GiftAudience.women => l10n.giftForWomenTagline,
        GiftAudience.companies => l10n.giftForCompaniesTagline,
      };

  IconData get icon => switch (this) {
        GiftAudience.men => Icons.man_rounded,
        GiftAudience.women => Icons.woman_rounded,
        GiftAudience.companies => Icons.business_center_rounded,
      };
}
