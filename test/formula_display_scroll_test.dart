// Synthetic display geometry and interactive desktop scrollbar regression.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/widgets/product_detail/structured_formula_card.dart';
import 'formula_display_contract_test.dart' show synthetic;

void main() {
  for (final width in [360.0, 412.0, 1200.0]) {
    testWidgets('real font two-axis right/bottom and mouse scrollbar at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = FontLoader('sans-serif')
        ..addFont(rootBundle.load('assets/fonts/MicrosoftYaHei.ttf'));
      await font.load();
      final raw = synthetic(length: 70, count: 60).toJson();
      raw['rows'] = [
        for (final row in raw['rows'])
          [
            row[0],
            '1' * 80,
            '0.${'1' * 80}%',
            'Synthetic supplier900003 ' * 10,
            row[4]
          ]
      ];
      final d = FormulaDocument.fromJson(raw);
      await tester.pumpWidget(MaterialApp(
          home: RepaintBoundary(
              key: const ValueKey('scroll-capture'),
              child: Scaffold(
                  body: SingleChildScrollView(
                      child: StructuredFormulaCard(document: d))))));
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('recipe-cell:SYNTH-900000:1:0'));
      final corner = find.byKey(const ValueKey('recipe-cell:SYNTH-900000:0:0'));
      final firstX = tester.getTopLeft(first).dx;
      final cornerRect = tester.getRect(corner);
      final y = tester.getTopLeft(first).dy + 15;
      final xScroll = find.byKey(const ValueKey('recipe-scroll:SYNTH-900000'));
      final x = tester.widget<SingleChildScrollView>(xScroll).controller!;
      expect(x.position.maxScrollExtent, greaterThan(0));
      await tester.dragFrom(Offset(width - 30, y), const Offset(-10000, 0));
      await tester.pumpAndSettle();
      expect(x.offset, closeTo(x.position.maxScrollExtent, .001));
      expect(tester.getTopLeft(first).dx, firstX);
      final headerEnd =
          find.byKey(const ValueKey('recipe-cell:SYNTH-900000:0:4'));
      final firstEnd =
          find.byKey(const ValueKey('recipe-cell:SYNTH-900000:1:4'));
      expect(tester.getRect(headerEnd).right,
          closeTo(tester.getRect(firstEnd).right, .1));
      await tester.dragFrom(Offset(firstX + 30, y), const Offset(0, -10000));
      await tester.pumpAndSettle();
      expect(tester.getRect(corner), cornerRect);
      final lastFirst =
          find.byKey(const ValueKey('recipe-cell:SYNTH-900000:60:0'));
      final lastEnd =
          find.byKey(const ValueKey('recipe-cell:SYNTH-900000:60:4'));
      expect(tester.getRect(lastFirst).bottom,
          closeTo(tester.getRect(lastEnd).bottom, .1));
      final bottomBefore = tester.getRect(lastFirst).bottom;
      await tester.dragFrom(
          Offset(width - 40, cornerRect.bottom + 80), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(tester.getRect(lastFirst).bottom, greaterThan(bottomBefore));
      expect(tester.getRect(lastFirst).bottom,
          closeTo(tester.getRect(lastEnd).bottom, .1));
      expect(tester.getRect(corner), cornerRect);
      await tester.dragFrom(
          Offset(width - 40, cornerRect.bottom + 80), const Offset(0, -10000));
      await tester.pumpAndSettle();
      final xBar =
          find.byWidgetPredicate((w) => w is Scrollbar && w.controller == x);
      final barRect = tester.getRect(xBar);
      expect(tester.getRect(lastEnd).bottom,
          lessThanOrEqualTo(barRect.bottom + .1));
      if (Platform.environment['RECIPE_TEST_OUT'] case final String out) {
        await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('scroll-capture')))
              .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/scroll-$width-right-bottom.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      if (width == 1200) {
        // Interactive desktop scrollbar remains visible at the table viewport,
        // not thousands of pixels below it at the end of the content.
        await tester.dragFrom(Offset(barRect.right - 25, barRect.bottom - 4),
            const Offset(-10000, 0),
            kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(x.offset, 0);
        expect(tester.getRect(headerEnd).right,
            closeTo(tester.getRect(firstEnd).right, .1));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
