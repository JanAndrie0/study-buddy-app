// PDF inspector tests (Phase 3): page count + text-layer check in pure Dart.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_buddy/services/pdf_inspector.dart';

/// Builds a tiny PDF with [pages] pages. Each page's content stream either
/// draws text (`BT ... Tj ET`) or only paints an image (`/Im1 Do`).
/// With [compress], content streams are zlib-compressed like real exports.
Uint8List makePdf({required int pages, required bool withText, bool compress = false, bool encrypt = false}) {
  final out = BytesBuilder();
  void write(String s) => out.add(latin1.encode(s));
  write('%PDF-1.7\n');
  write('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n');
  final kids = List.generate(pages, (i) => '${3 + i * 2} 0 R').join(' ');
  write('2 0 obj << /Type /Pages /Kids [$kids] /Count $pages >> endobj\n');
  for (var i = 0; i < pages; i++) {
    final pageId = 3 + i * 2;
    write('$pageId 0 obj << /Type /Page /Parent 2 0 R /Contents ${pageId + 1} 0 R >> endobj\n');
    final content = withText ? 'BT /F1 12 Tf 72 712 Td (Slide ${i + 1} text) Tj ET' : 'q 612 0 0 792 0 0 cm /Im1 Do Q';
    final data = compress ? ZLibEncoder().convert(latin1.encode(content)) : latin1.encode(content);
    write('${pageId + 1} 0 obj << /Length ${data.length}${compress ? ' /Filter /FlateDecode' : ''} >>\nstream\n');
    out.add(data);
    write('\nendstream endobj\n');
  }
  write('trailer << /Root 1 0 R${encrypt ? ' /Encrypt 99 0 R' : ''} >>\n%%EOF\n');
  return out.toBytes();
}

void main() {
  final inspector = DartPdfInspector();

  test('counts pages and sees text', () async {
    final info = await inspector.inspect(makePdf(pages: 7, withText: true));
    expect(info.pageCount, 7);
    expect(info.looksScanned, isFalse);
  });

  test('finds text inside compressed (FlateDecode) streams', () async {
    final info = await inspector.inspect(makePdf(pages: 3, withText: true, compress: true));
    expect(info.pageCount, 3);
    expect(info.looksScanned, isFalse);
  });

  test('image-only pages are flagged as scanned', () async {
    final info = await inspector.inspect(makePdf(pages: 24, withText: false, compress: true));
    expect(info.pageCount, 24);
    expect(info.looksScanned, isTrue);
  });

  test('protected PDFs still get a page count and are not called scanned', () async {
    final info = await inspector.inspect(makePdf(pages: 5, withText: false, encrypt: true));
    expect(info.pageCount, 5);
    expect(info.looksScanned, isFalse);
  });

  test('a file that is not a PDF is refused', () async {
    expect(
      () => inspector.inspect(Uint8List.fromList(utf8.encode('hello, not a pdf'))),
      throwsA(isA<PdfReadException>()),
    );
  });

  test('same bytes give the same hash, different bytes a different one', () async {
    final a = await inspector.inspect(makePdf(pages: 2, withText: true));
    final b = await inspector.inspect(makePdf(pages: 2, withText: true));
    final c = await inspector.inspect(makePdf(pages: 3, withText: true));
    expect(a.sha256, b.sha256);
    expect(a.sha256, isNot(c.sha256));
  });

  // Real lectures live only on my PC (gitignored), so CI skips this.
  // Expected page counts come from pypdf (Phase 1 inventory).
  final lectures = Directory('evals/lectures');
  test('matches pypdf page counts on my real lecture PDFs', () async {
    const expected = {
      '11_Anatomy of Typography.pdf': 31,
      'CIT4303_LECT3 Software Acquisition Strategies-1.pdf': 6,
      'CIT4303_LECT4 Software Quality Economics-1.pdf': 7,
      'CIT4303_LECT5 Technology Cost AnalysisPART1.pdf': 6,
      'M2. Lecture Presentation. Human Acts, and Ethical Theories and Reasoning.pdf': 39,
      'M3. Lecture Presentation. Intellectualism.pdf': 25,
      'M4. Lecture Presentation. Virtue Ethics.pdf': 22,
      'Module 1 - Introduction to Ethical Hacking.pdf': 9,
      'Module 2 - Network Scanning.pdf': 19,
    };
    for (final entry in expected.entries) {
      final file = File('${lectures.path}/${entry.key}');
      if (!file.existsSync()) continue;
      final info = await inspector.inspect(file.readAsBytesSync());
      expect(info.pageCount, entry.value, reason: entry.key);
      expect(info.looksScanned, isFalse, reason: '${entry.key} has a text layer');
    }
  }, skip: lectures.existsSync() ? false : 'lecture PDFs are not in this checkout');
}
