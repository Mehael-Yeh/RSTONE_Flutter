import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/utils/formula_protocol_codec.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';
import 'formula_structured_test.dart' show specimen, document;
import 'support/ingredient_tap.dart';
import 'package:rst_flutter/widgets/product_detail/structured_formula_card.dart';

void main() {
  test('v2 preserves embedded associated tokens and strictly roundtrips', () {
    final m = specimen()..['schema'] = 'rstone-recipe/2';
    m['rows'][0][0] = 'mix [[RS87654321-Q5]] + [[RS87654321-Q5]]';
    final d = FormulaDocument.fromJson(m);
    final raw = FormulaProtocolCodec.encode(d);
    expect(utf8.decode(raw), contains('[[产品列表/RS87654321-Q5]]'));
    expect(FormulaProtocolCodec.decode(raw).toJson(), m);
    expect(
        () => FormulaProtocolCodec.decode(utf8.encode('${utf8.decode(raw)}x')),
        throwsFormatException);
  });
  for (final schema in ['rstone-recipe/1', 'rstone-recipe/2']) {
    testWidgets('formal detail $schema ingredient tap opens exact real product',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final m = specimen()..['schema'] = schema;
      m['associatedProducts'] = [
        'RS87654321-Q5',
        'RS222-X',
        'RD999999',
        'RS222'
      ];
      m['rows'][0][0] =
          'mix [[RS222-X]] + [[RD999999]] [[RS222]] [[rs222-x]] [[RS333]]';
      final owner = ProductItem.fromMdContent('产品列表/RS87654321-Q5.md', '');
      final target = ProductItem.fromMdContent(
          '产品列表/RS222-X.md', 'EXACT SYNTHETIC DESTINATION');
      final f =
          ProductItem.fromMdContent('产品配方/RS87654321-Q5-底.md', document(m));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ProductDetailSheet(
                  product: owner,
                  productCatalog: [owner, target],
                  formulas: [f]))));
      await tester.pumpAndSettle();
      final card = find.byType(StructuredFormulaCard);
      expect(
          ingredientLinks(tester, card).map((span) => span.text), ['RS222-X']);
      await tapIngredientText(tester, card, 'RS222-X');
      await tester.pumpAndSettle();
      expect(find.text('EXACT SYNTHETIC DESTINATION'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
    });
  }
}
