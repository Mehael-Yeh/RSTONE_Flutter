// Synthetic display geometry and bar-free two-axis panning regression.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/widgets/product_detail/structured_formula_card.dart';
import 'package:rst_flutter/widgets/product_detail/formula_pinned_table.dart';
import 'support/horizontal_bar_scroll_behavior.dart';
import 'formula_display_contract_test.dart' show synthetic;

void main() {
  for (final width in [360.0, 412.0, 1200.0]) {
    testWidgets(
        'real font two-axis right/bottom without horizontal scrollbar at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = FontLoader('sans-serif')
        ..addFont(rootBundle.load('assets/fonts/MicrosoftYaHei.ttf'));
      await font.load();
      await (FontLoader('Roboto')
            ..addFont(rootBundle.load('assets/fonts/MicrosoftYaHei.ttf')))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
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
          scrollBehavior: const HorizontalBarScrollBehavior(),
          theme: ThemeData(
              platform: width == 1200
                  ? TargetPlatform.linux
                  : TargetPlatform.android),
          home: RepaintBoundary(
              key: const ValueKey('scroll-capture'),
              child: Scaffold(
                  body: SingleChildScrollView(
                      child: RepaintBoundary(
                          key: const ValueKey('full-formula-capture'),
                          child: ColoredBox(
                              color: ThemeData().colorScheme.surface,
                              child: StructuredFormulaCard(document: d))))))));
      await tester.pumpAndSettle();
      final table = find.byType(FormulaPinnedTable);
      final fullHeight = tester
          .widget<FormulaPinnedTable>(table)
          .heights
          .fold<double>(0, (a, b) => a + b);
      expect(tester.getSize(table).height, closeTo(fullHeight, .1));
      expect(
          find.descendant(
              of: table,
              matching: find.byWidgetPredicate((w) =>
                  w is Scrollable &&
                  axisDirectionToAxis(w.axisDirection) == Axis.vertical)),
          findsNothing);
      expect(
          find.descendant(
              of: table,
              matching: find.byWidgetPredicate(
                  (w) => w is Scrollbar || w is RawScrollbar)),
          findsNothing);
      final outer = tester
          .state<ScrollableState>(
              find.ancestor(of: table, matching: find.byType(Scrollable)).first)
          .position;
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
      await tester.dragFrom(Offset(firstX + 30, y), const Offset(0, -100000));
      await tester.pumpAndSettle();
      expect(outer.pixels, closeTo(outer.maxScrollExtent, .1));
      expect(tester.getRect(corner).top, lessThan(cornerRect.top));
      final lastFirst =
          find.byKey(const ValueKey('recipe-cell:SYNTH-900000:60:0'));
      final lastEnd =
          find.byKey(const ValueKey('recipe-cell:SYNTH-900000:60:4'));
      expect(tester.getRect(lastFirst).bottom,
          closeTo(tester.getRect(lastEnd).bottom, .1));
      final bottomBefore = tester.getRect(lastFirst).bottom;
      final outerBefore = outer.pixels;
      await tester.dragFrom(Offset(width - 40, 500), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(outer.pixels, lessThan(outerBefore));
      expect(tester.getRect(lastFirst).bottom, greaterThan(bottomBefore));
      expect(tester.getRect(lastFirst).bottom,
          closeTo(tester.getRect(lastEnd).bottom, .1));
      expect(tester.getTopLeft(lastFirst).dx, firstX);
      await tester.dragFrom(Offset(width - 40, 500), const Offset(0, -100000));
      await tester.pumpAndSettle();
      final xBar = find.byWidgetPredicate((w) =>
          (w is Scrollbar && w.controller == x) ||
          (w is RawScrollbar && w.controller == x));
      expect(xBar, findsNothing);
      expect(find.ancestor(of: xScroll, matching: find.byType(RawScrollbar)),
          findsNothing,
          reason: 'default desktop scrollbar injection is suppressed');
      final viewportRect = tester.getRect(xScroll);
      expect(tester.getRect(lastEnd).bottom, lessThanOrEqualTo(1000));
      expect(tester.getRect(lastEnd).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(lastEnd).bottom,
          lessThanOrEqualTo(viewportRect.bottom + .1));
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
          final fullImage = await tester
              .renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('full-formula-capture')))
              .toImage();
          final fullData =
              await fullImage.toByteData(format: ui.ImageByteFormat.png);
          File('$out/scroll-$width-all-rows.png')
              .writeAsBytesSync(fullData!.buffer.asUint8List());
          fullImage.dispose();
        });
      }
      if (width == 1200) {
        // The old visible-thumb drag contract is replaced by real panning.
        // Mouse content panning replaces the former draggable thumb.
        await tester.dragFrom(
            Offset(viewportRect.left + 25, 500), const Offset(10000, 0),
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
