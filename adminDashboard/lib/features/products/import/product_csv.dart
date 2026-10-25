import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/localized_text.dart';

import '../domain/product_draft.dart';
import 'csv_codec.dart';

/// The product CSV format (SRS §9 Products "bulk import CSV").
///
/// * One header row with any of [all] (case-insensitive, any order); other
///   columns are ignored and listed in the preview.
/// * List cells ([listColumns]) separate items with `|`.
/// * A row without an `id` always CREATES a product (id = the slug of the
///   English title, made unique like the editor does). A row whose `id`
///   exists UPDATES that product: only the non-empty cells change; `-` clears
///   an optional field ([clearable]). Sales / view counters, ratings and
///   option groups are never touched by an import.
class ProductCsv {
  ProductCsv._();

  static const id = 'id';
  static const title = 'title';
  static const titleAr = 'titleAr';
  static const titleKu = 'titleKu';
  static const description = 'description';
  static const descriptionAr = 'descriptionAr';
  static const descriptionKu = 'descriptionKu';
  static const price = 'price';
  static const compareAtPrice = 'compareAtPrice';
  static const categoryIds = 'categoryIds';
  static const giftFor = 'giftFor';
  static const storeId = 'storeId';
  static const availability = 'availability';
  static const preparationDays = 'preparationDays';
  static const availableCities = 'availableCities';
  static const stock = 'stock';
  static const isActive = 'isActive';
  static const isFeatured = 'isFeatured';
  static const tags = 'tags';
  static const images = 'images';

  /// The documented header, in template order.
  static const all = [
    id,
    title,
    titleAr,
    titleKu,
    description,
    descriptionAr,
    descriptionKu,
    price,
    compareAtPrice,
    categoryIds,
    giftFor,
    storeId,
    availability,
    preparationDays,
    availableCities,
    stock,
    isActive,
    isFeatured,
    tags,
    images,
  ];

  static const listSeparator = '|';

  /// In an update, a cell holding only this clears an optional field.
  static const clearToken = '-';

  static const listColumns = {categoryIds, giftFor, availableCities, tags, images};

  /// What an empty `giftFor` cell means (SRS §9 Products): a gift for him
  /// and her — the same default the Phase 11 backfill gives older products.
  static const defaultGiftFor = [GiftAudience.men, GiftAudience.women];

  /// Optional fields an update may clear with [clearToken].
  static const clearable = {
    titleAr,
    titleKu,
    description,
    descriptionAr,
    descriptionKu,
    compareAtPrice,
    categoryIds,
    preparationDays,
    availableCities,
    stock,
    tags,
    images,
  };

  /// What each column holds (shown on the import page).
  static const help = <String, String>{
    id: 'Product id. Empty = create a new product (id from the English title). An existing id updates that product.',
    title: 'English title — required for new products.',
    titleAr: 'Arabic title (optional).',
    titleKu: 'Kurdish (Sorani) title (optional).',
    description: 'English description (line breaks allowed inside quotes).',
    descriptionAr: 'Arabic description (optional).',
    descriptionKu: 'Kurdish description (optional).',
    price: 'Whole IQD, greater than 0 — required for new products.',
    compareAtPrice: 'Whole IQD, greater than the price; empty = no discount.',
    categoryIds: 'Category ids separated by |, e.g. mugs|birthday.',
    giftFor: 'Who it is a gift for: men, women and / or companies separated by |, e.g. men|companies. '
        'Empty = men|women (an update keeps the current value).',
    storeId: 'Store id — required for new products.',
    availability: 'sameDay, preparationDays or outOfStock (new products default to sameDay).',
    preparationDays: 'Whole days, at least 1 when availability is preparationDays.',
    availableCities: 'City ids separated by |; empty = every served city.',
    stock: 'Whole number; empty = unlimited.',
    isActive: 'true / false (new products default to true).',
    isFeatured: 'true / false (new products default to false).',
    tags: 'Search tags separated by |.',
    images: 'Image URLs (https://…) separated by |; the first is the main image.',
  };

  /// Ids that are dashboard routes (`/products/new`, `/products/import`).
  static const reservedIds = {'new', 'import'};

  /// Header + one example row. Pass real ids so the example imports as is.
  static String template({String? exampleCategory, String? exampleStore, String? exampleCity}) {
    final example = <String, String>{
      id: '',
      title: 'Engraved Walnut Frame',
      titleAr: 'إطار جوز محفور',
      titleKu: 'چوارچێوەی گوێزی هەڵکۆڵراو',
      description: 'Solid walnut frame, engraved with your names and date.\nFits a 15×20 cm photo.',
      descriptionAr: 'إطار من خشب الجوز محفور بأسمائكم والتاريخ.',
      descriptionKu: 'چوارچێوەی دار گوێز، ناو و بەرواری لەسەر هەڵدەکۆڵرێت.',
      price: '35000',
      compareAtPrice: '42000',
      categoryIds: exampleCategory ?? 'frames',
      giftFor: [GiftAudience.men.name, GiftAudience.women.name].join(listSeparator),
      storeId: exampleStore ?? 'golden-gift-home',
      availability: ProductAvailability.preparationDays.name,
      preparationDays: '2',
      availableCities: exampleCity ?? 'erbil',
      stock: '20',
      isActive: 'true',
      isFeatured: 'false',
      tags: 'wood|engraved|anniversary',
      images: 'https://example.com/frame-1.jpg|https://example.com/frame-2.jpg',
    };
    // BOM so Excel opens it as UTF-8 (Arabic / Kurdish stay readable).
    return '\uFEFF${encodeCsv([
          all,
          [for (final c in all) example[c]!]
        ])}';
  }

  static final _byLowerName = {for (final c in all) c.toLowerCase(): c};

  /// The documented column for a header cell, or null.
  static String? canonical(String header) => _byLowerName[header.trim().toLowerCase()];
}

/// A problem with one row, attached to its column when there is one.
class ImportIssue {
  const ImportIssue(this.column, this.message);

  /// A [ProductCsv] column, or null for the row as a whole.
  final String? column;
  final String message;

  @override
  String toString() => column == null ? message : '$column: $message';
}

/// The parsed file: recognised columns, ignored ones and the data rows.
class ProductCsvSheet {
  const ProductCsvSheet(
      {required this.columns, required this.ignoredColumns, required this.rows, this.rowIssues = const {}});

  /// Recognised columns (canonical names) in file order.
  final List<String> columns;
  final List<String> ignoredColumns;
  final List<ProductCsvRow> rows;

  /// row → structural problems (wrong cell count).
  final Map<int, List<ImportIssue>> rowIssues;
}

/// One data row: the cells of the recognised columns, trimmed.
class ProductCsvRow {
  const ProductCsvRow(this.row, this.cells);

  /// Spreadsheet row number (the header is row 1).
  final int row;
  final Map<String, String> cells;

  bool has(String column) => cells.containsKey(column);
  String cell(String column) => cells[column] ?? '';
}

/// Reads the header and rows of a product CSV. Throws [CsvFormatException]
/// for a file that can't be imported at all.
ProductCsvSheet parseProductSheet(String text) {
  // Spreadsheet row numbers (header = row 1), so a cell with a line break
  // doesn't shift the numbers the admin sees.
  final records = [
    for (final (i, r) in parseCsv(text).indexed)
      if (!r.isBlank) (i + 1, r.cells),
  ];
  if (records.isEmpty) throw const CsvFormatException('The file is empty.');
  final header = records.first.$2;
  final columns = <String>[];
  final positions = <String, int>{};
  final ignored = <String>[];
  for (var i = 0; i < header.length; i++) {
    final name = header[i].trim();
    final canonical = ProductCsv.canonical(name);
    if (canonical == null) {
      if (name.isNotEmpty) ignored.add(name);
      continue;
    }
    if (positions.containsKey(canonical)) {
      throw CsvFormatException('The column “$canonical” appears twice in the header.');
    }
    positions[canonical] = i;
    columns.add(canonical);
  }
  if (!positions.containsKey(ProductCsv.id) && !positions.containsKey(ProductCsv.title)) {
    throw CsvFormatException('The first row must be the header (${ProductCsv.all.join(',')}); it needs at least an '
        '“id” or a “title” column. Download the template to start.');
  }
  final rows = <ProductCsvRow>[];
  final issues = <int, List<ImportIssue>>{};
  for (final (row, cells) in records.skip(1)) {
    final extra = cells.length > header.length && cells.skip(header.length).any((c) => c.trim().isNotEmpty);
    if (cells.length < header.length || extra) {
      issues[row] = [
        ImportIssue(
            null,
            'Has ${cells.length} cells but the header has ${header.length} columns '
            '(check for an unquoted comma or a missing cell).'),
      ];
    }
    rows.add(ProductCsvRow(row, {
      for (final c in columns)
        if (positions[c]! < cells.length) c: cells[positions[c]!].trim(),
    }));
  }
  return ProductCsvSheet(columns: columns, ignoredColumns: ignored, rows: rows, rowIssues: issues);
}

// ── Cell parsers ────────────────────────────────────────────────────────────

/// Western digits for Arabic-Indic (٠-٩) and Extended Arabic-Indic (۰-۹) ones.
String westernDigits(String s) {
  final b = StringBuffer();
  for (final rune in s.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      b.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      b.writeCharCode(0x30 + rune - 0x06F0);
    } else {
      b.writeCharCode(rune);
    }
  }
  return b.toString();
}

/// Same ceiling as the editor's number fields (9 digits).
const maxImportInt = 999999999;

/// Whole number with optional thousands separators (`25,000`, `25 000`,
/// `٢٥٠٠٠`); `25000.00` is accepted, `25000.5` is not. Returns
/// (value, error).
(int?, String?) parseImportInt(String raw) {
  var s = westernDigits(raw.trim()).replaceAll(RegExp(r'[,\s\u00A0\u066C_]'), '');
  s = s.replaceAll('\u066B', '.'); // Arabic decimal separator
  final m = RegExp(r'^(-?\d+)(?:\.(\d+))?$').firstMatch(s);
  if (m == null) return (null, 'Not a whole number: “$raw”.');
  if (m.group(2) != null && RegExp(r'[^0]').hasMatch(m.group(2)!)) {
    return (null, 'Whole numbers only (IQD has no decimals): “$raw”.');
  }
  final v = int.tryParse(m.group(1)!);
  if (v == null || v.abs() > maxImportInt) return (null, 'Too large: “$raw”.');
  return (v, null);
}

(bool?, String?) parseImportBool(String raw) => switch (raw.trim().toLowerCase()) {
      'true' || 'yes' || 'y' || '1' => (true, null),
      'false' || 'no' || 'n' || '0' => (false, null),
      _ => (null, 'Use true or false: “$raw”.'),
    };

(ProductAvailability?, String?) parseImportAvailability(String raw) {
  final key = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  for (final a in ProductAvailability.values) {
    if (a.name.toLowerCase() == key) return (a, null);
  }
  return (null, 'Use ${ProductAvailability.values.map((a) => a.name).join(', ')}: “$raw”.');
}

/// `men|Women|companies` → the gift types in [GiftAudience] order
/// (case-insensitive, duplicates dropped). Any unknown value is an error.
(List<GiftAudience>?, String?) parseImportGiftFor(String raw) {
  final picked = <GiftAudience>{};
  final unknown = <String>[];
  for (final part in parseImportList(raw)) {
    final match = GiftAudience.values.where((a) => a.name.toLowerCase() == part.toLowerCase()).firstOrNull;
    match == null ? unknown.add(part) : picked.add(match);
  }
  if (unknown.isNotEmpty) {
    return (null, 'Use ${GiftAudience.values.map((a) => a.name).join(', ')} separated by |: “${unknown.join('|')}”.');
  }
  if (picked.isEmpty) return (null, 'Choose at least one of ${GiftAudience.values.map((a) => a.name).join(', ')}.');
  return (GiftAudience.values.where(picked.contains).toList(), null);
}

/// `a|b|c` → `[a, b, c]` (trimmed, empties and duplicates dropped; tags
/// compare case-insensitively, like the editor's tag field).
List<String> parseImportList(String raw, {bool caseInsensitive = false}) {
  final out = <String>[];
  final seen = <String>{};
  for (final part in raw.split(ProductCsv.listSeparator)) {
    final v = part.trim();
    if (v.isEmpty) continue;
    if (seen.add(caseInsensitive ? v.toLowerCase() : v)) out.add(v);
  }
  return out;
}

bool isHttpUrl(String s) {
  final u = Uri.tryParse(s);
  return u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.isNotEmpty;
}

/// A new product id typed in the file: letters, digits, `-`, `_`.
final importIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$');

// ── Applying a row to a draft ───────────────────────────────────────────────

/// What a row may reference (loaded once per import).
class ProductImportRefs {
  const ProductImportRefs({required this.categoryIds, required this.storeIds, required this.cityIds});
  final Set<String> categoryIds;
  final Set<String> storeIds;
  final Set<String> cityIds;
}

/// Applies the row's cells to [draft] (a new draft, or one made from the
/// existing product for an update). Returns the problems found while
/// reading cells, and fills [touched] with the columns that were applied.
///
/// Create: empty / `-` cells keep the draft's defaults. Update: empty cells
/// keep the current value; `-` clears a [ProductCsv.clearable] field.
/// `giftFor` (required, never cleared): empty or missing = [ProductCsv.defaultGiftFor]
/// for a new product and for an existing one that has no gift type yet.
List<ImportIssue> applyRowToDraft(
  ProductCsvRow row,
  ProductDraft draft, {
  required bool isUpdate,
  required ProductImportRefs refs,
  required Set<String> touched,
}) {
  final issues = <ImportIssue>[];
  for (final column in ProductCsv.all) {
    if (column == ProductCsv.id || !row.has(column)) continue;
    final raw = row.cell(column);
    if (raw.isEmpty) continue;
    final clear = raw == ProductCsv.clearToken;
    if (clear && !isUpdate) continue;
    if (clear && !ProductCsv.clearable.contains(column)) {
      issues.add(ImportIssue(column, 'Required — it can’t be cleared.'));
      continue;
    }
    final error = clear ? _clear(column, draft) : _set(column, raw, draft, refs);
    if (error != null) {
      issues.add(ImportIssue(column, error));
    } else {
      touched.add(column);
    }
  }
  if (draft.giftFor.isEmpty && !issues.any((i) => i.column == ProductCsv.giftFor)) {
    draft.giftFor.addAll(ProductCsv.defaultGiftFor);
    touched.add(ProductCsv.giftFor);
  }
  return issues;
}

String? _clear(String column, ProductDraft d) {
  switch (column) {
    case ProductCsv.titleAr:
      d.title = LocalizedText(d.title.en, ku: d.title.ku);
    case ProductCsv.titleKu:
      d.title = LocalizedText(d.title.en, ar: d.title.ar);
    case ProductCsv.description:
      d.description = LocalizedText('', ar: d.description.ar, ku: d.description.ku);
    case ProductCsv.descriptionAr:
      d.description = LocalizedText(d.description.en, ku: d.description.ku);
    case ProductCsv.descriptionKu:
      d.description = LocalizedText(d.description.en, ar: d.description.ar);
    case ProductCsv.compareAtPrice:
      d.compareAtPrice = null;
    case ProductCsv.categoryIds:
      d.categoryIds.clear();
    case ProductCsv.preparationDays:
      d.preparationDays = null;
    case ProductCsv.availableCities:
      d.availableCities.clear();
    case ProductCsv.stock:
      d.stock = null;
    case ProductCsv.tags:
      d.tags.clear();
    case ProductCsv.images:
      d.images.clear();
  }
  return null;
}

String? _set(String column, String raw, ProductDraft d, ProductImportRefs refs) {
  switch (column) {
    case ProductCsv.title:
      d.title = LocalizedText(raw, ar: d.title.ar, ku: d.title.ku);
    case ProductCsv.titleAr:
      d.title = LocalizedText(d.title.en, ar: raw, ku: d.title.ku);
    case ProductCsv.titleKu:
      d.title = LocalizedText(d.title.en, ar: d.title.ar, ku: raw);
    case ProductCsv.description:
      d.description = LocalizedText(raw, ar: d.description.ar, ku: d.description.ku);
    case ProductCsv.descriptionAr:
      d.description = LocalizedText(d.description.en, ar: raw, ku: d.description.ku);
    case ProductCsv.descriptionKu:
      d.description = LocalizedText(d.description.en, ar: d.description.ar, ku: raw);
    case ProductCsv.price || ProductCsv.compareAtPrice || ProductCsv.preparationDays || ProductCsv.stock:
      final (v, error) = parseImportInt(raw);
      if (error != null) return error;
      switch (column) {
        case ProductCsv.price:
          d.price = v;
        case ProductCsv.compareAtPrice:
          d.compareAtPrice = v;
        case ProductCsv.preparationDays:
          d.preparationDays = v;
        default:
          d.stock = v;
      }
    case ProductCsv.isActive || ProductCsv.isFeatured:
      final (v, error) = parseImportBool(raw);
      if (error != null) return error;
      if (column == ProductCsv.isActive) {
        d.isActive = v!;
      } else {
        d.isFeatured = v!;
      }
    case ProductCsv.availability:
      final (v, error) = parseImportAvailability(raw);
      if (error != null) return error;
      d.availability = v!;
    case ProductCsv.storeId:
      if (!refs.storeIds.contains(raw)) return 'Unknown store “$raw”.';
      d.storeId = raw;
    case ProductCsv.categoryIds:
      final ids = parseImportList(raw);
      final unknown = ids.where((c) => !refs.categoryIds.contains(c)).toList();
      if (unknown.isNotEmpty) return 'Unknown categor${unknown.length == 1 ? 'y' : 'ies'}: ${unknown.join(', ')}.';
      d.categoryIds
        ..clear()
        ..addAll(ids);
    case ProductCsv.giftFor:
      final (audiences, error) = parseImportGiftFor(raw);
      if (error != null) return error;
      d.giftFor
        ..clear()
        ..addAll(audiences!);
    case ProductCsv.availableCities:
      final ids = parseImportList(raw);
      final unknown = ids.where((c) => !refs.cityIds.contains(c)).toList();
      if (unknown.isNotEmpty) {
        return refs.cityIds.isEmpty
            ? 'No cities are set up yet (Settings → Cities).'
            : 'Unknown cit${unknown.length == 1 ? 'y' : 'ies'}: ${unknown.join(', ')}.';
      }
      d.availableCities
        ..clear()
        ..addAll(ids);
    case ProductCsv.tags:
      d.tags
        ..clear()
        ..addAll(parseImportList(raw, caseInsensitive: true));
    case ProductCsv.images:
      final urls = parseImportList(raw);
      final bad = urls.where((u) => !isHttpUrl(u)).toList();
      if (bad.isNotEmpty) return 'Not an http(s) URL: ${bad.join(', ')}.';
      d.images.clear();
      for (final u in urls) {
        d.addImageSlot(u);
      }
  }
  return null;
}

/// The editor's validation messages ([ProductDraft.validate]) placed on
/// their column; option-group problems (only possible on an update — an
/// import never edits groups) stay on the row.
ImportIssue draftIssue(String message) {
  String? column;
  var text = message;
  if (message.startsWith('English title')) {
    column = ProductCsv.title;
    text = 'Required for every product.';
  } else if (message.startsWith('Choose a store')) {
    column = ProductCsv.storeId;
    text = 'Required for every product.';
  } else if (message == giftForRequiredMessage) {
    column = ProductCsv.giftFor;
  } else if (message.startsWith('Price')) {
    column = ProductCsv.price;
  } else if (message.startsWith('Compare-at')) {
    column = ProductCsv.compareAtPrice;
  } else if (message.startsWith('Preparation days')) {
    column = ProductCsv.preparationDays;
  } else if (message.startsWith('Stock')) {
    column = ProductCsv.stock;
  } else {
    text = 'Existing option groups: $message Fix them in the product editor.';
  }
  return ImportIssue(column, text);
}
