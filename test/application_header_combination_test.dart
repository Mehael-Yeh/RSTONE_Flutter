import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/platform_interface/share_plus_platform.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/utils/formula_table_clipboard_parser.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';
import 'package:rst_flutter/widgets/product_detail/formula_card_header.dart';
import 'package:rst_flutter/widgets/product_detail/formula_pinned_table.dart';
import 'package:rst_flutter/widgets/product_detail/formula_png_renderer.dart';
import 'package:rst_flutter/widgets/product_detail/formula_presentation.dart';
import 'formula_selection_payload_test.dart'
    show fixture, nameOf, CapturedShare;
import 'application_formula_links_test.dart' show tapMarkdownGlyph;
import 'support/sync_fixture.dart';

void main() {
  for (final width in [360.0, 412.0, 1200.0]) {
    for (final legacy in [false, true]) {
      testWidgets(
          'application link and header share one selection $legacy $width',
          (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final font in ['sans-serif', 'Roboto']) {
          await (FontLoader(font)
                ..addFont(rootBundle.load('assets/fonts/MicrosoftYaHei.ttf')))
              .load();
        }
        final fs = fixture(legacy)
            .map((f) => ProductItem(
                fileName: f.fileName,
                filePath: f.filePath,
                folder: f.folder,
                rawContent: f.rawContent,
                frontmatter: f.frontmatter,
                formulaDocument: f.formulaDocument,
                origin: DataOrigin.official))
            .toList();
        final a = nameOf(fs.first), b = nameOf(fs.last);
        final raw = '---\n底漆: "[[产品配方/$a]]"\n面漆: "[[产品配方/$b]]"\n'
            '${width == 1200 ? '基材: "[[产品配方/$a]] + [[产品配方/$b]]"\n' : ''}'
            '---\n${width == 412 ? '面层使用 [[产品配方/$b]]。' : ''}';
        final app = (await tester.runAsync(() async {
          final f = SignedFixture();
          await f.initialize();
          final store = await f.memoryStorage();
          final service = await f.app(store);
          addTearDown(() async {
            service.dispose();
            await store.close();
          });
          await service.addApplicationMarkdown(
              name: 'Combination900001', markdown: raw);
          return service.applications.single;
        }))!;
        expect(app.origin, DataOrigin.user);
        expect(app.filePath, startsWith('user/'));
        final capture = CapturedShare(), oldShare = SharePlatform.instance;
        SharePlatform.instance = capture;
        addTearDown(() => SharePlatform.instance = oldShare);
        String? copied;
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'];
          }
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null));
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: ProductDetailSheet(
                    product: app, productCatalog: const [], formulas: fs))));
        await tester.pumpAndSettle();
        final dropdown = find.byType(DropdownButton<String>);
        Finder link(String name) => find.byWidgetPredicate((w) =>
            w is Text &&
            w.data == name &&
            w.style?.decoration == TextDecoration.underline);
        String? selection() =>
            tester.widget<DropdownButton<String>>(dropdown).value;
        Future<Uint8List> share() async {
          capture.bytes = null;
          await tester.ensureVisible(find.byTooltip('分享配方图片'));
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await tester.tap(find.byTooltip('分享配方图片'));
            for (var n = 0; capture.bytes == null && n < 200; n++) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          expect(capture.bytes, isNotNull);
          await tester.pumpAndSettle();
          return Uint8List.fromList(capture.bytes!);
        }

        expect(selection(), a);
        expect(
            find.descendant(
                of: find.byType(FormulaCardHeader), matching: dropdown),
            findsOneWidget);
        expect(
            tester
                .widget<DropdownButton<String>>(dropdown)
                .items!
                .map((e) => e.value),
            [a, b]);
        final firstPng = await share();
        if (width == 360) {
          await tester.ensureVisible(link(b));
          await tester.pumpAndSettle();
          await tester.tap(link(b));
          await tester.pumpAndSettle();
        } else {
          final glyph = find.byWidgetPredicate((w) =>
              w is SelectableText &&
              (w.textSpan?.toPlainText() ?? w.data ?? '').contains(b));
          if (width == 412) {
            await tester.scrollUntilVisible(glyph, 500,
                scrollable: find.byType(Scrollable).first, maxScrolls: 100);
            await tester.pumpAndSettle();
          }
          await tapMarkdownGlyph(tester, b);
        }
        expect(selection(), b);
        final cs = Theme.of(tester.element(dropdown)).colorScheme;
        expect(tester.widget<Text>(link(b)).style!.color, cs.primary);
        expect(tester.widget<Text>(link(a)).style!.color, cs.secondary);
        await tester.ensureVisible(find.byTooltip('复制配方五列'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('复制配方五列'));
        await tester.pumpAndSettle();
        expect(
            FormulaTableClipboardParser.parse(copied!).rows,
            List.generate(
                60,
                (r) => [
                      'BOM900001-$r',
                      '2',
                      '50',
                      'Supplier900001',
                      'Note900001-$r'
                    ]));
        final secondPng = await share();
        expect(secondPng, isNot(orderedEquals(firstPng)));
        expect(capture.subject, contains(b));
        if (!legacy) {
          final expected = await tester.runAsync(() =>
              FormulaPngRenderer.render(
                  FormulaDisplayView(fs.last.formulaDocument!)));
          expect(secondPng, orderedEquals(expected!));
        }
        final table = find.byType(FormulaPinnedTable);
        final grid = tester.widget<FormulaPinnedTable>(table);
        expect(tester.getSize(table).height,
            closeTo(grid.heights.fold<double>(0, (a, b) => a + b), .1));
        expect(
            find.descendant(
                of: table,
                matching: find.byWidgetPredicate((w) =>
                    w is Scrollbar ||
                    w is RawScrollbar ||
                    (w is Scrollable &&
                        (w.axisDirection == AxisDirection.down ||
                            w.axisDirection == AxisDirection.up)))),
            findsNothing);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text(a).last);
        await tester.pumpAndSettle();
        expect(selection(), a);
        expect(tester.widget<Text>(link(a)).style!.color, cs.primary);
        expect(tester.widget<Text>(link(b)).style!.color, cs.secondary);
        await tester.tap(find.byTooltip('复制配方五列'));
        await tester.pumpAndSettle();
        expect(
            FormulaTableClipboardParser.parse(copied!).rows,
            List.generate(
                60,
                (r) => [
                      'BOM900000-$r',
                      '1',
                      '50',
                      'Supplier900000',
                      'Note900000-$r'
                    ]));
        expect(await share(), orderedEquals(firstPng));
        expect(app.rawContent, raw);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
