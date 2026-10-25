/// Kebab-case document ids for catalogue entries (categories, cities):
/// "Mother's Day" → `mothers-day`, "Skin & Body Care" → `skin-body-care`.
/// Apostrophes are dropped rather than split, matching the seeded ids.
String slugify(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r"['’`]"), '')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

final _slug = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

bool isValidSlug(String id) => _slug.hasMatch(id);

/// Field validator for a new id: format and uniqueness among [takenIds].
String? validateSlugId(String? value, {required Iterable<String> takenIds}) {
  final id = value?.trim() ?? '';
  if (id.isEmpty) return 'Required';
  if (id.length > 60) return 'At most 60 characters';
  if (!isValidSlug(id)) return 'Lowercase letters, digits and single dashes only';
  if (takenIds.contains(id)) return 'The id "$id" is already used';
  return null;
}
