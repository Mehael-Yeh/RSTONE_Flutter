import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';

void main() {
  testWidgets(
      'legacy formula wraps long ingredients instead of fixed row clipping',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final text = 'Synthetic900001 ${'long ingredient ' * 20}'.trim();
    final product = ProductItem.fromMdContent('产品列表/RS900001.md', '');
    final formula = ProductItem.fromMdContent('产品配方/RS900001.md',
        '---\n关联产品: "[[RS900001]]"\n---\n| 原料编号 | 投入数 |\n| --- | --- |\n| [[RS900001]] | 1 |\n| $text | 2 |\n| 去离子水（DI water） | 3 |');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProductDetailSheet(
                product: product,
                productCatalog: [product],
                formulas: [formula]))));
    await tester.pumpAndSettle();
    final rich =
        find.descendant(of: find.text(text), matching: find.byType(RichText));
    final p = tester.renderObject<RenderParagraph>(rich);
    for (final box in p.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length))) {
      final actual = box.toRect().shift(p.localToGlobal(Offset.zero));
      final cell = p.parent! as RenderBox;
      final rect = cell.localToGlobal(Offset.zero) & cell.size;
      expect(actual.bottom, lessThanOrEqualTo(rect.bottom + .1));
      expect(actual.top, greaterThanOrEqualTo(rect.top - .1));
    }
    expect(find.text('去离子水'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
