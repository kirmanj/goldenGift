import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Opens [url] in a new tab (photo download, links).
void openInNewTab(String url) => web.window.open(url, '_blank');

/// Opens an HTML document (invoice) in a new tab.
void openHtmlInNewTab(String html) {
  final blob = web.Blob([html.toJS].toJS, web.BlobPropertyBag(type: 'text/html'));
  web.window.open(web.URL.createObjectURL(blob), '_blank');
}

/// Saves [text] as a file named [filename] (CSV template download).
void downloadText(String filename, String text, {String mimeType = 'text/csv'}) {
  final blob = web.Blob([text.toJS].toJS, web.BlobPropertyBag(type: '$mimeType;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // Revoking right away can cancel the download in some browsers.
  Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
}
