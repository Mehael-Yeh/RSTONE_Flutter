import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/services/tds_pdf_service.dart';

// Unit-only cache: use bundled non-covering font bytes for primary fonts, not
// downloaded font evidence. Real Noto glyph/render checks run separately.
class _BoundaryCache extends PdfMemoryCache {
  _BoundaryCache(this.primary, {this.offline = false});
  final Uint8List primary;
  final bool offline;
  final requests = <String>[];

  @override
  Future<Uint8List> resolve({
    required String name,
    required Uri uri,
    bool cache = true,
    Map<String, String>? headers,
  }) async {
    requests.add(name);
    if (name == 'NotoSans-Regular' && offline) {
      throw StateError('Synthetic offline font cache');
    }
    return primary;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PdfBaseCache previous;
  late Uint8List nonCoveringFont;
  setUp(() async {
    previous = PdfBaseCache.defaultCache;
    final data = await rootBundle.load('assets/fonts/MicrosoftYaHei.ttf');
    nonCoveringFont =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  });
  tearDown(() {
    PdfBaseCache.defaultCache = previous;
  });

  Future<Uint8List> export(String value) => TdsPdfService.generatePdfBytes(
        ProductItem.fromMdContent('产品列表/SYNTHETIC-FONT.md', ''),
        tdsMarkdown: '# SYNTHETIC-FONT\n\n合成材料\n\n## 合成正文\n$value\n',
      );

  test('ordinary text does not request the subscript fallback font', () async {
    final cache = _BoundaryCache(nonCoveringFont, offline: true);
    PdfBaseCache.defaultCache = cache;
    final bytes = await export('Original English words 42±2 mPa·s');
    expect(bytes.take(5), '%PDF-'.codeUnits);
    expect(cache.requests, isNot(contains('NotoSans-Regular')));
  });

  test('offline fallback fails explicitly instead of exporting missing U+2082',
      () async {
    final cache = _BoundaryCache(nonCoveringFont, offline: true);
    PdfBaseCache.defaultCache = cache;
    await expectLater(
      export('合成水 H₂O=3:7'),
      throwsA(isA<StateError>()
          .having((e) => e.message.toString(), 'message', contains('U+2082'))),
    );
    expect(cache.requests, contains('NotoSans-Regular'));
  });

  test('non-covering cached font fails explicitly for U+2082', () async {
    final cache = _BoundaryCache(nonCoveringFont);
    PdfBaseCache.defaultCache = cache;
    await expectLater(
      export('合成水 H₂O=3:7'),
      throwsA(isA<StateError>()
          .having((e) => e.message.toString(), 'message', contains('U+2082'))),
    );
  });
}
