import 'support/ingredient_tap.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/widgets/product_detail/formula_presentation.dart';
import 'package:rst_flutter/widgets/product_detail/formula_png_renderer.dart';
import 'package:rst_flutter/widgets/product_detail/structured_formula_card.dart';

FormulaDocument synthetic({int length = 70, int count = 1}) {
  final target = 'RS900000${'1' * length}';
  return FormulaDocument.fromJson({
    'schema': 'rstone-recipe/2',
    'recipeId': 'SYNTH-900000',
    'title': 'Synthetic 900000',
    'classification': 'main',
    'ownerProduct': target,
    'associatedProducts': [target],
    'columns': ['原料编号', '投入数', '百分比(%)', '供应商', '备注'],
    'rows':
        List.generate(count, (i) => ['mix [[$target]]', '1', '', '', 'row $i']),
    'preTable': <String>[],
    'content': <Object>[],
  });
}

void main() {
  test(
      'display and share project valid links only, raw model and TSV stay lossless',
      () {
    final raw = synthetic(length: 1).toJson();
    final target = raw['ownerProduct'] as String;
    final input =
        '[[$target]] [[产品列表/$target]] [[UNKNOWN900001]] [ordinary] [[other/$target]]';
    raw['rows'] = [
      [input, '1', '', '', ''],
      ['去离子水（DI water）', '1', '', '', ''],
      ['去离子水 (DI Water)', '1', '', '', ''],
      ['TEGO900001 (50% in PM)', '1', '', '', ''],
      ['海明斯 900002 (50% in pm)', '1', '', '', ''],
      ['未知（unknown） 去离子水（hot water） 去离子水（DI water 50%）', '1', '', '', '']
    ];
    final d = FormulaDocument.fromJson(raw);
    final view = FormulaDisplayView(d);
    final projected =
        '$target $target [[UNKNOWN900001]] [ordinary] [[other/$target]]';
    expect(view.cells.skip(2).map((r) => r[0]).toList(), [
      '去离子水',
      '去离子水',
      'TEGO900001 (50% in PM)',
      '海明斯 900002 (50% in pm)',
      '未知（unknown） 去离子水（hot water） 去离子水（DI water 50%）'
    ]);
    expect(view.cells[1][0], projected);
    expect(FormulaPngRenderer.layout(view).text.map((n) => n.text),
        contains(projected));
    expect(view.tsv, contains(input));
    expect(d.toJson(), raw);
  });
  for (final schema in ['rstone-recipe/1', 'rstone-recipe/2']) {
    testWidgets(
        '$schema qualified and adjacent inline links display only exact target glyphs',
        (tester) async {
      final raw = synthetic(length: 1).toJson()..['schema'] = schema;
      final target = raw['ownerProduct'] as String;
      raw['rows'] = [
        ['[[$target]][[产品列表/$target]] + [[UNKNOWN900001]]', '1', '', '', '']
      ];
      final d = FormulaDocument.fromJson(raw);
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: StructuredFormulaCard(
                      document: d,
                      canOpenProduct: (_) => true,
                      onOpenProduct: calls.add)))));
      await tester.pumpAndSettle();
      final card = find.byType(StructuredFormulaCard);
      expect(ingredientLinks(tester, card).map((p) => p.text).toList(),
          [target, target]);
      expect(
          ingredientLinks(tester, card)
              .every((p) => p.style!.decoration == TextDecoration.underline),
          isTrue);
      await tapIngredientText(tester, card, target, occurrence: 1);
      expect(calls, [target]);
      await tapIngredientText(tester, card, '[[UNKNOWN900001]]');
      expect(calls, [target]);
      expect(d.toJson(), raw);
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [360.0, 412.0, 1200.0]) {
    testWidgets('pinned header and first column stay aligned at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final d = synthetic(length: 24, count: 40);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: StructuredFormulaCard(
                      document: d,
                      canOpenProduct: (_) => true,
                      onOpenProduct: (_) {})))));
      await tester.pumpAndSettle();
      final header = find.byKey(const ValueKey('recipe-cell:SYNTH-900000:0:0'));
      final first = find.byKey(const ValueKey('recipe-cell:SYNTH-900000:1:0'));
      final beforeHeader = tester.getTopLeft(header);
      final beforeFirst = tester.getTopLeft(first);
      final horizontal =
          find.byKey(const ValueKey('recipe-scroll:SYNTH-900000'));
      expect(horizontal, findsOneWidget);
      final xController =
          tester.widget<SingleChildScrollView>(horizontal).controller;
      final xBar = find.byWidgetPredicate(
          (w) => w is Scrollbar && w.controller == xController);
      expect(tester.getSize(xBar).height, lessThanOrEqualTo(420));
      expect(tester.getSize(xBar).width,
          closeTo(tester.getSize(horizontal).width, .1),
          reason:
              'scrollbar track must use the actual pannable viewport, not the frozen column');
      await tester.dragFrom(
          Offset(width - 40, beforeFirst.dy + 20), const Offset(-10000, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(first).dx, beforeFirst.dx);
      expect(tester.getTopLeft(header), beforeHeader);
      final vertical =
          find.byKey(const ValueKey('recipe-vertical:SYNTH-900000'));
      expect(vertical, findsOneWidget);
      await tester.dragFrom(
          beforeFirst + const Offset(30, 20), const Offset(0, -10000));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(header), beforeHeader);
      final bottom =
          find.byKey(const ValueKey('recipe-cell:SYNTH-900000:40:0'));
      final end = find.byKey(const ValueKey('recipe-cell:SYNTH-900000:40:4'));
      expect(tester.getRect(bottom).bottom, lessThanOrEqualTo(500));
      expect(tester.getRect(end).bottom,
          closeTo(tester.getRect(bottom).bottom, .1));
      expect(tester.getRect(end).right, lessThanOrEqualTo(width));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('actual inherited rich glyph bounds fit every cell inner bounds',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final outside = <String>[];
    final loader = FontLoader('sans-serif')
      ..addFont(rootBundle.load('assets/fonts/MicrosoftYaHei.ttf'));
    await loader.load();
    for (var length = 10; length <= 118; length++) {
      final d = synthetic(length: length);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: StructuredFormulaCard(
        document: d,
        canOpenProduct: (_) => true,
        onOpenProduct: (_) {},
      ))));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('recipe-cell:SYNTH-900000:1:0'));
      final rect = tester.getRect(cell);
      final inner = Rect.fromLTRB(rect.left + 10.5, rect.top + 8.5,
          rect.right - 10.5, rect.bottom - 8.5);
      final rich = find.descendant(of: cell, matching: find.byType(RichText));
      final p = tester.renderObject<RenderParagraph>(rich);
      for (final box in p.getBoxesForSelection(TextSelection(
          baseOffset: 0, extentOffset: p.text.toPlainText().length))) {
        final actual = box.toRect().shift(p.localToGlobal(Offset.zero));
        if (actual.top < inner.top - .1 ||
            actual.bottom > inner.bottom + .1 ||
            actual.left < inner.left - .1 ||
            actual.right > inner.right + .1) {
          outside.add(
              'length=$length glyph=$actual inner=$inner style=${p.text.style}');
        }
      }
    }
    expect(outside, isEmpty, reason: outside.join('\n'));
  });
}
