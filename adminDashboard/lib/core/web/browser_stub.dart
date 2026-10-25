/// What would have been opened (inspected by tests on the Dart VM).
final openedUrls = <String>[];
final openedDocuments = <String>[];

/// Files that would have been downloaded: (filename, text).
final downloadedFiles = <(String, String)>[];

void openInNewTab(String url) => openedUrls.add(url);

void openHtmlInNewTab(String html) => openedDocuments.add(html);

void downloadText(String filename, String text, {String mimeType = 'text/csv'}) =>
    downloadedFiles.add((filename, text));
