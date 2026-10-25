import 'dart:convert';

/// A CSV problem that makes the whole file unreadable.
class CsvFormatException implements Exception {
  const CsvFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One record of a CSV file and the (1-based) line it starts on, so errors
/// can point at the spreadsheet row even when a quoted cell spans lines.
class CsvRecord {
  const CsvRecord(this.line, this.cells);
  final int line;
  final List<String> cells;

  bool get isBlank => cells.every((c) => c.trim().isEmpty);
}

/// UTF-8 bytes → text (a leading BOM is dropped). Anything else (Excel's
/// legacy "CSV (Comma delimited)" ANSI export) is rejected rather than
/// silently mangling Arabic / Kurdish text.
String decodeCsvBytes(List<int> bytes) {
  try {
    return _stripBom(utf8.decode(bytes));
  } on FormatException {
    throw const CsvFormatException(
        'The file is not UTF-8 text. In Excel use “Save as → CSV UTF-8 (Comma delimited)”; in Google Sheets '
        '“Download → Comma-separated values”.');
  }
}

String _stripBom(String text) => text.startsWith('\uFEFF') ? text.substring(1) : text;

/// RFC 4180 parser: comma separated, `"` quoted fields with `""` escapes,
/// commas and line breaks inside quotes, CRLF / LF / CR line endings, an
/// optional UTF-8 BOM. Lenient where spreadsheets are: a `"` inside an
/// unquoted field is kept literally, text after a closing quote is appended.
/// Line breaks inside quoted cells are normalised to `\n`.
List<CsvRecord> parseCsv(String input) {
  final text = _stripBom(input);
  final records = <CsvRecord>[];
  var cells = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var quoteLine = 0;
  var line = 1;
  var recordLine = 1;
  var hasContent = false; // anything read since the record started

  void endField() {
    cells.add(field.toString());
    field.clear();
  }

  void endRecord() {
    endField();
    records.add(CsvRecord(recordLine, cells));
    cells = <String>[];
    hasContent = false;
  }

  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
        } else {
          inQuotes = false;
          i++;
        }
        continue;
      }
      if (c == '\r' || c == '\n') {
        field.write('\n');
        line++;
        i += (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') ? 2 : 1;
        continue;
      }
      field.write(c);
      i++;
      continue;
    }
    switch (c) {
      case '"':
        hasContent = true;
        if (field.isEmpty) {
          inQuotes = true;
          quoteLine = line;
        } else {
          field.write(c);
        }
        i++;
      case ',':
        hasContent = true;
        endField();
        i++;
      case '\r' || '\n':
        endRecord();
        i += (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') ? 2 : 1;
        line++;
        recordLine = line;
      default:
        hasContent = true;
        field.write(c);
        i++;
    }
  }
  if (inQuotes) throw CsvFormatException('A quoted cell that starts on line $quoteLine is never closed (missing ").');
  if (hasContent || field.isNotEmpty || cells.isNotEmpty) endRecord();
  return records;
}

/// One CSV line: cells with a comma, quote, line break or edge spaces are
/// quoted (quotes doubled).
String encodeCsvRow(List<String> cells) => cells.map(_encodeCell).join(',');

String _encodeCell(String cell) {
  final needsQuotes = cell.contains(RegExp(r'[",\r\n]')) || cell != cell.trim();
  return needsQuotes ? '"${cell.replaceAll('"', '""')}"' : cell;
}

/// A whole file with RFC 4180 CRLF line endings.
String encodeCsv(List<List<String>> rows) => '${rows.map(encodeCsvRow).join('\r\n')}\r\n';
