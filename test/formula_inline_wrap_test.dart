import 'dart:io';
import 'support/ingredient_tap.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/widgets/product_detail/structured_formula_card.dart';
import 'package:rst_flutter/widgets/product_detail/formula_presentation.dart';

FormulaDocument wrapDocument({String prefix = 'mix ', String? ingredient}) {
  final target = 'RS${'1' * 70}';
  return FormulaDocument.fromJson({
    'schema': 'rstone-recipe/2',
    'recipeId': 'SYNTH-WRAP',
    'title': 'Synthetic wrap',
    'classification': 'main',
    'ownerProduct': target,
    'associatedProducts': [target],
    'columns': ['原料编号', '投入数', '百分比(%)', '供应商', '备注'],
    'rows': [
      [ingredient ?? '$prefix[[$target]]', '1', '', '', ''],
      ['next row', '1', '', '', '']
    ],
    'preTable': <String>[],
    'content': <Object>[],
  });
}

void main() {
  testWidgets('long inline product fits the plain measured row inner bounds',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final document = wrapDocument();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RepaintBoundary(
                key: const ValueKey('capture'),
                child: StructuredFormulaCard(
                    document: document,
                    canOpenProduct: (_) => true,
                    onOpenProduct: (_) {})))));
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('recipe-cell:SYNTH-WRAP:1:0'));
    final rect = tester.getRect(cell);
    final inner = Rect.fromLTRB(
        rect.left + FormulaTableLayout.cellPadding,
        rect.top + 8,
        rect.right - FormulaTableLayout.cellPadding,
        rect.bottom - 8);
    final paragraphs =
        find.descendant(of: cell, matching: find.byType(RichText));
    final outside = <String>[];
    for (final element in paragraphs.evaluate()) {
      final p = element.renderObject! as RenderParagraph;
      final text = p.text.toPlainText();
      for (final box in p.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length))) {
        final actual = box.toRect().shift(p.localToGlobal(Offset.zero));
        if (actual.top < inner.top - 0.1 ||
            actual.bottom > inner.bottom + 0.1) {
          outside.add('$text: $actual outside $inner');
        }
      }
    }
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')));
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('../geometry-${outside.isEmpty ? 'green' : 'red'}.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(outside, isEmpty,
        reason: 'actual glyph bounds must fit the row: $outside');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'inline links update callbacks, revoke targets and dispose removed cells',
      (tester) async {
    final target = wrapDocument().ownerProduct;
    final calls = <String>[];
    final card = find.byType(StructuredFormulaCard);
    Future<void> pump(FormulaDocument document, String callback,
        {bool allow = true}) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: StructuredFormulaCard(
                  document: document,
                  canOpenProduct: (_) => allow,
                  onOpenProduct: (value) => calls.add('$callback:$value')))));
      await tester.pumpAndSettle();
    }

    final first =
        wrapDocument(ingredient: 'mix [[$target]][[$target]] + [[UNKNOWN]]');
    await pump(first, 'old');
    expect(ingredientLinks(tester, card).length, 2);
    await tapIngredientText(tester, card, '[[$target]]');
    expect(calls, ['old:$target']);
    await pump(first, 'new');
    await tapIngredientText(tester, card, '[[$target]]', occurrence: 1);
    expect(calls, ['old:$target', 'new:$target']);
    await tapIngredientText(tester, card, '[[UNKNOWN]]');
    expect(calls.length, 2);
    await pump(first, 'revoked', allow: false);
    expect(ingredientLinks(tester, card), isEmpty);
    await tapIngredientText(tester, card, '[[$target]]');
    expect(calls.length, 2);
    await pump(
        wrapDocument(ingredient: 'replacement with no link'), 'replacement');
    expect(ingredientLinks(tester, card), isEmpty);
    await pump(first, 'restored');
    await tapIngredientText(tester, card, '[[$target]]');
    expect(calls.last, 'restored:$target');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(calls.length, 3);
  });
}
