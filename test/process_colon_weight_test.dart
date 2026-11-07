import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/widgets/product_detail/structured_formula_card.dart';

/// 工艺条款里的分隔符（中文冒号/英文冒号/等号）一律不加粗：只有版式，没有字重变化。
FormulaDocument _doc() => FormulaDocument.fromJson({
      'schema': 'rstone-recipe/2',
      'recipeId': 'SYNTH-COLON-1',
      'title': '测试配方',
      'classification': 'main',
      'ownerProduct': 'RS900900',
      'associatedProducts': ['RS900900'],
      'columns': ['原料编号', '投入数', '百分比(%)', '供应商', '备注'],
      'rows': [
        ['[[RS900900]]', '100', '100.000%', '锐石', '主树脂'],
      ],
      'preTable': <String>[],
      'content': [
        {
          'kind': 'process',
          'label': '配制与施工',
          'steps': [
            '固化剂 : N3300',
            '施工比例：配方 : 13-75P（新拓普固化剂） : H2O = 100 : 25 : 5-15',
            '直接说明文字',
          ],
        },
      ],
    });

bool _hasBold(InlineSpan span) {
  if (span is! TextSpan) return false;
  if (span.style?.fontWeight == FontWeight.bold) return true;
  return span.children?.any(_hasBold) ?? false;
}

void main() {
  testWidgets('process step never bolds a separator', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: StructuredFormulaCard(document: _doc())))));
    final step = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((w) => w.text.toPlainText() == '固化剂 : N3300');
    expect(step.text.toPlainText(), '固化剂 : N3300');
    expect(_hasBold(step.text), isFalse, reason: 'no bold inside a step line');
  });

  testWidgets('ratio line keeps a chinese label colon and spaced english colons',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: StructuredFormulaCard(document: _doc())))));
    const line = '施工比例：配方 : 13-75P（新拓普固化剂） : H2O = 100 : 25 : 5-15';
    final ratio = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((w) => w.text.toPlainText() == line);
    expect(ratio.text.toPlainText(), line);
    expect(_hasBold(ratio.text), isFalse, reason: 'separators stay regular');
  });
}
