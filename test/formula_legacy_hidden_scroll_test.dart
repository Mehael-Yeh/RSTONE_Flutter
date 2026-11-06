// Synthetic legacy fixture exercises the actual detail path, not a replacement table.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';
import 'package:rst_flutter/widgets/product_detail/formula_pinned_table.dart';
import 'support/horizontal_bar_scroll_behavior.dart';

void main() {
  for (final width in [360.0, 412.0, 1200.0]) {
    testWidgets(
        'legacy hidden horizontal bar preserves rightmost bottom fixed axes at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader('sans-serif')
            ..addFont(rootBundle.load('assets/fonts/MicrosoftYaHei.ttf')))
          .load();
      await (FontLoader('Roboto')
            ..addFont(rootBundle.load('assets/fonts/MicrosoftYaHei.ttf')))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
      final product = ProductItem.fromMdContent('产品列表/RS900001.md', '');
      String end(int r) =>
          'end900${r.toString().padLeft(3, '0')} ${'long cell ' * 12}'.trim();
      final markdown =
          '---\n关联产品: "[[RS900001]]"\n---\n| 编号900000 | header900001 | header900002 | header900003 | header900004 |\n| --- | --- | --- | --- | --- |\n${[
        for (var r = 1; r <= 60; r++)
          '| ID900$r | ${'11' * 60} | ${'22' * 60} | ${'33' * 60} | ${end(r)} |'
      ].join('\n')}';
      final formula = ProductItem.fromMdContent('产品配方/RS900001.md', markdown);
      await tester.pumpWidget(MaterialApp(
          scrollBehavior: const HorizontalBarScrollBehavior(),
          theme: ThemeData(
              platform: width == 1200
                  ? TargetPlatform.linux
                  : TargetPlatform.android),
          home: RepaintBoundary(
              key: const ValueKey('legacy-capture'),
              child: Scaffold(
                  body: ProductDetailSheet(
                      product: product,
                      productCatalog: [product],
                      formulas: [formula])))));
      await tester.pumpAndSettle();
      final table = find.byType(FormulaPinnedTable);
      expect(table, findsOneWidget);
      final heights = tester.widget<FormulaPinnedTable>(table).heights;
      final fullHeight = heights.fold<double>(0, (a, b) => a + b);
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
      var top = tester.getRect(table).top + heights.first;
      for (var r = 1; r <= 60; r++) {
        final cell = find
            .ancestor(
                of: find.text('ID900$r'), matching: find.byType(Container))
            .first;
        final rect = tester.getRect(cell);
        expect(rect.top, closeTo(top, .1));
        expect(rect.height, closeTo(heights[r], .1));
        top = rect.bottom;
      }
      expect(top, closeTo(tester.getRect(table).bottom, .1));
      final horizontal = find.descendant(
          of: table,
          matching: find.byWidgetPredicate((w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal));
      final x = tester.widget<SingleChildScrollView>(horizontal).controller!;
      expect(x.position.maxScrollExtent, greaterThan(0));
      expect(
          find.byWidgetPredicate((w) =>
              (w is RawScrollbar && w.controller == x) ||
              (w is Scrollbar && w.controller == x)),
          findsNothing);
      final first = find.text('ID9001'), corner = find.text('编号900000');
      final firstX = tester.getTopLeft(first).dx;
      final cornerRect = tester.getRect(corner);
      final viewport = tester.getRect(horizontal);
      await tester.dragFrom(Offset(viewport.right - 25, cornerRect.bottom + 25),
          const Offset(-10000, 0));
      await tester.pumpAndSettle();
      expect(x.offset, closeTo(x.position.maxScrollExtent, .1));
      expect(tester.getTopLeft(first).dx, firstX);
      expect(tester.getRect(find.text('header900004')).right,
          lessThanOrEqualTo(viewport.right));
      await tester.dragFrom(Offset(firstX + 10, cornerRect.bottom + 25),
          const Offset(0, -100000));
      await tester.pumpAndSettle();
      // The first gesture expands DraggableScrollableSheet; the next scrolls
      // its one outer ListView, never a nested table viewport.
      await tester.dragFrom(Offset(firstX + 10, 500), const Offset(0, -100000));
      await tester.pumpAndSettle();
      expect(outer.pixels, greaterThan(0));
      expect(tester.getRect(corner).top, lessThan(cornerRect.top));
      final last = find.text('ID90060'), lastEnd = find.text(end(60));
      expect(tester.getRect(last).center.dy,
          closeTo(tester.getRect(lastEnd).center.dy, .1));
      expect(tester.getRect(lastEnd).bottom, lessThanOrEqualTo(1000));
      expect(tester.getRect(lastEnd).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(lastEnd).bottom,
          lessThanOrEqualTo(tester.getRect(table).bottom));
      if (Platform.environment['RECIPE_TEST_OUT'] case final String out) {
        await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('legacy-capture')))
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/legacy-$width-right-bottom.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      if (width == 1200) {
        await tester.dragFrom(
            Offset(viewport.left + 25, 500), const Offset(10000, 0),
            kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(x.offset, 0);
        expect(tester.getRect(last).center.dy,
            closeTo(tester.getRect(lastEnd).center.dy, .1));
      }
      expect(formula.rawContent, markdown);
      expect(tester.takeException(), isNull);
    });
  }
}
