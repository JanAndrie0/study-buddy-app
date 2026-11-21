import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// What we learn from a PDF before sending it to Gemini (no network needed).
class PdfInfo {
  const PdfInfo({
    required this.pageCount,
    required this.textOpsPerPage,
    required this.sha256,
  });

  final int pageCount;

  /// Average number of "draw text" commands per page. Slides saved as
  /// images have none: Gemini can still read them, but they cost more and
  /// give weaker questions.
  final double textOpsPerPage;

  /// Hash of the file bytes, to spot re-uploads and key the dev cache.
  final String sha256;

  bool get looksScanned => textOpsPerPage < 1;
}

/// Thrown for files we can't read as a PDF (encrypted, damaged, not a PDF).
class PdfReadException implements Exception {
  const PdfReadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads page count and text. An interface so tests can use a fake.
abstract class PdfInspector {
  Future<PdfInfo> inspect(Uint8List bytes);
}

/// Pure-Dart PDF check: no native library, so it runs the same on the phone,
/// in tests and in CI. It only needs two facts, so it doesn't render anything:
///
/// - Page count: the root "/Type /Pages" object has "/Count N".
/// - Text layer: page content uses text operators (`Tj` / `TJ`) to draw text;
///   image-only pages don't.
///
/// Modern PDFs compress most objects (FlateDecode = zlib), so we inflate
/// every compressed stream and search inside it too.
class DartPdfInspector implements PdfInspector {
  static final _streamStart = RegExp(r'stream\r?\n');
  static final _pagesCount = RegExp(r'/Type\s*/Pages\b[^>]*?/Count\s+(\d+)|/Count\s+(\d+)[^>]*?/Type\s*/Pages\b');
  static final _pageObject = RegExp(r'/Type\s*/Page(?![a-zA-Z])');
  static final _textOperator = RegExp(r'(\)|>|\])\s*T[jJ]\b');

  @override
  Future<PdfInfo> inspect(Uint8List bytes) async {
    // latin1 maps each byte to one character, so offsets stay byte offsets.
    final raw = latin1.decode(bytes);
    if (!raw.startsWith('%PDF')) {
      throw const PdfReadException('Hindi PDF ang file na ito.');
    }
    // "Protected" PDFs (e.g. printing disabled) encrypt their streams, so we
    // can't look inside. We can still usually find the page count; we just
    // skip the text-layer check instead of refusing the file.
    final encrypted = raw.contains('/Encrypt');
    final parts = <String>[raw, if (!encrypted) ..._inflatedStreams(bytes, raw)];

    var pageCount = 0;
    var pageObjects = 0;
    var textOps = 0;
    for (final part in parts) {
      for (final match in _pagesCount.allMatches(part)) {
        final n = int.parse(match.group(1) ?? match.group(2)!);
        if (n > pageCount) pageCount = n; // the root /Pages has the biggest count
      }
      pageObjects += _pageObject.allMatches(part).length;
      textOps += _textOperator.allMatches(part).length;
    }
    if (pageCount == 0) pageCount = pageObjects;
    if (pageCount == 0) {
      throw PdfReadException(encrypted
          ? 'May password o protection ang PDF. Alisin muna, then try again.'
          : 'Hindi mabasa ang PDF. Baka sira ang file.');
    }

    return PdfInfo(
      pageCount: pageCount,
      // Unknown for protected files: don't wrongly call them "scanned".
      textOpsPerPage: encrypted ? double.infinity : textOps / pageCount,
      sha256: sha256.convert(bytes).toString(),
    );
  }

  /// Inflates every FlateDecode stream. Broken or non-zlib streams are skipped.
  Iterable<String> _inflatedStreams(Uint8List bytes, String raw) sync* {
    for (final match in _streamStart.allMatches(raw)) {
      final start = match.end;
      final end = raw.indexOf('endstream', start);
      if (end == -1) break;
      final dictStart = raw.lastIndexOf('<<', match.start);
      final dictionary = dictStart == -1 ? '' : raw.substring(dictStart, match.start);
      if (!dictionary.contains('FlateDecode')) continue;
      try {
        final inflated = ZLibDecoder().convert(bytes.sublist(start, end));
        yield latin1.decode(inflated);
      } catch (_) {
        // Not every stream inflates cleanly (e.g. trailing bytes); skip it.
      }
    }
  }
}
