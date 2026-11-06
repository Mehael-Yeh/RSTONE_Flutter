import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
// Test boundary intercepts the real XFile; renderer and clipboard are not replaced.
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/platform_interface/share_plus_platform.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/utils/formula_table_clipboard_parser.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';
import 'package:rst_flutter/widgets/product_detail/formula_card_header.dart';
import 'package:rst_flutter/widgets/product_detail/formula_pinned_table.dart';
import 'package:rst_flutter/widgets/product_detail/formula_png_renderer.dart';
import 'package:rst_flutter/widgets/product_detail/formula_presentation.dart';
import 'formula_display_contract_test.dart' show synthetic;

class CapturedShare extends SharePlatform {
  Uint8List? bytes;
  String? subject;
  @override
  Future<ShareResult> shareXFiles(List<XFile> files,
      {String? subject,
      String? text,
      Rect? sharePositionOrigin,
      List<String>? fileNameOverrides}) async {
    bytes = await files.single.readAsBytes();
    this.subject = subject;
    expect(files.single.mimeType, 'image/png');
    return const ShareResult('test', ShareResultStatus.success);
  }
}

List<ProductItem> fixture(bool legacy) => List.generate(2, (i) {
      final rows = List.generate(
          60,
          (r) => [
                'BOM90000$i-$r',
                '${i + 1}',
                '50',
                'Supplier90000$i',
                'Note90000$i-$r'
              ]);
      final name = 'Recipe90000$i-${'long' * 12}';
      if (legacy) {
        return ProductItem.fromMdContent('产品配方/$name.md',
            '---\n关联产品: "[[RS9000001]]"\n---\nPRE90000$i\n\n| 原料编号 | 投入数 | 百分比(%) | 供应商 | 备注 |\n| --- | --- | --- | --- | --- |\n${rows.map((r) => '| ${r.join(' | ')} |').join('\n')}\n\nPOST90000$i');
      }
      final json = synthetic(length: 1).toJson()
        ..['recipeId'] = 'SYNTH-90000$i'
        ..['title'] = name
        ..['rows'] = rows
        ..['preTable'] = ['PRE90000$i']
        ..['content'] = [
          {'kind': 'note', 'text': 'POST90000$i'}
        ];
      return ProductItem(
          fileName: name,
          filePath: '产品配方/$name.md',
          folder: '产品配方',
          rawContent: '',
          frontmatter: const {},
          formulaDocument: FormulaDocument.fromJson(json));
    });
String nameOf(ProductItem p) =>
    p.formulaDocument == null ? p.fileName.replaceAll('.md', '') : p.fileName;

void main() {
  for (final width in [360.0, 412.0, 1200.0]) {
    for (final legacy in [false, true]) {
      for (final application in [false, true]) {
        testWidgets(
            'current payload and complete canvas ${legacy ? 'legacy' : 'structured'} ${application ? 'application' : 'product'} $width',
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
          final capture = CapturedShare();
          final old = SharePlatform.instance;
          SharePlatform.instance = capture;
          addTearDown(() => SharePlatform.instance = old);
          String? copied;
          tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
          addTearDown(() => tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null));
          final fs = fixture(legacy);
          final product = ProductItem.fromMdContent('产品列表/RS9000001.md', '');
          final app = ProductItem.fromMdContent('产品应用/App900001.md',
              '---\n底漆: ${nameOf(fs.first)}\n面漆: ${nameOf(fs.last)}\n---\n');
          Future<void> mount(
              List<ProductItem> formulas, ProductItem target) async {
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(MaterialApp(
                home: Scaffold(
                    body: ProductDetailSheet(
                        product: target,
                        productCatalog: [product],
                        formulas: formulas))));
            await tester.pumpAndSettle();
          }

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
            expect(capture.bytes, isNotNull,
                reason: 'real Canvas PNG must reach share boundary');
            await tester.pumpAndSettle();
            return Uint8List.fromList(capture.bytes!);
          }

          await mount(fs, application ? app : product);
          final dropdown = application
              ? find.byType(DropdownButton<String>)
              : find.byType(DropdownButton<int>);
          expect(dropdown, findsOneWidget);
          expect(
              find.descendant(
                  of: find.byType(FormulaCardHeader), matching: dropdown),
              findsOneWidget);
          final a = tester.getRect(find.text('配方：')),
              b = tester.getRect(dropdown);
          expect((a.center.dy - b.center.dy).abs(), lessThan(1));
          expect(b.left - a.right, inInclusiveRange(0, 4));
          for (final tip in ['复制配方五列', '分享配方图片']) {
            final rect = tester.getRect(find.byTooltip(tip));
            expect(rect.size, const Size(48, 48));
            expect(rect.left, greaterThanOrEqualTo(b.right));
            expect(rect.right, lessThanOrEqualTo(width));
          }
          final firstPng = await share();
          await tester.tap(dropdown);
          await tester.pumpAndSettle();
          await tester.tap(find.text(nameOf(fs.last)).last);
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('复制配方五列'));
          await tester.pumpAndSettle();
          final parsed = FormulaTableClipboardParser.parse(copied!);
          expect(parsed.isValid, isTrue);
          expect(parsed.rows.length, 60);
          expect(parsed.rows.first,
              ['BOM900001-0', '2', '50', 'Supplier900001', 'Note900001-0']);
          expect(parsed.rows.last.last, 'Note900001-59');
          expect(
              parsed.rows,
              List.generate(
                  60,
                  (r) => [
                        'BOM900001-$r',
                        '2',
                        '50',
                        'Supplier900001',
                        'Note900001-$r'
                      ]));
          expect(copied, isNot(contains('BOM900000')));
          final table = find.byType(FormulaPinnedTable);
          final heights = tester.widget<FormulaPinnedTable>(table).heights;
          expect(tester.getSize(table).height,
              closeTo(heights.fold<double>(0, (a, b) => a + b), .1));
          expect(find.descendant(of: table, matching: find.byType(Scrollbar)),
              findsNothing);
          final secondPng = await share();
          final imageOut = Platform.environment['FORMULA_SELECTION_IMAGES'];
          if (imageOut != null) {
            Directory(imageOut).createSync(recursive: true);
            File('$imageOut/${legacy ? 'legacy' : 'structured'}-${application ? 'application' : 'product'}-$width.png')
                .writeAsBytesSync(secondPng);
          }
          expect(secondPng, isNot(orderedEquals(firstPng)));
          expect(capture.subject, contains(nameOf(fs.last)));
          final codec =
              await tester.runAsync(() => ui.instantiateImageCodec(secondPng));
          final frame = await tester.runAsync(() => codec!.getNextFrame());
          expect(frame!.image.height, greaterThan(2000));
          frame.image.dispose();
          codec!.dispose();
          await tester.tap(dropdown);
          await tester.pumpAndSettle();
          await tester.tap(find.text(nameOf(fs.first)).last);
          await tester.pumpAndSettle();
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
          // A standalone render has neither selector nor action icons. Exact bytes
          // demonstrate that the selected-card share does not screenshot the UI.
          if (!legacy) {
            final expected = await tester.runAsync(() =>
                FormulaPngRenderer.render(
                    FormulaDisplayView(fs.last.formulaDocument!)));
            expect(secondPng, orderedEquals(expected!));
          } else {
            await mount([fs.last], product);
            expect(find.byType(DropdownButton<int>), findsNothing);
            expect(await share(), orderedEquals(secondPng));
          }
          if (!legacy) {
            await mount([fs.last], product);
            expect(find.byType(DropdownButton<int>), findsNothing);
            expect(find.text('配方：${nameOf(fs.last)}'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
