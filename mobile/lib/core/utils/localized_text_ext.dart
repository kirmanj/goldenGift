import 'package:flutter/widgets.dart';

import '../../models/localized_text.dart';

extension LocalizedTextX on LocalizedText {
  /// The text in the app's current language (falls back to English).
  String of(BuildContext context) =>
      resolve(Localizations.localeOf(context).languageCode);
}
