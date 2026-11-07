import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/widgets/product_detail/structured_formula_card.dart';

/// 工艺条款里 “标签 : 值” 的分节冒号必须单独加粗，文字本身不加粗。
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
          'steps': ['固化剂 : N3300', '直接说明文字'],
        },
      ],
    });

void main() {
  testWidgets('process step bolds only the connector colon', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: StructuredFormulaCard(document: _doc())))));
    bool hasBoldColon(InlineSpan span) {
      if (span is! TextSpan) return false;
      if (span.text == ':' && span.style?.fontWeight == FontWeight.bold) {
        return true;
      }
      return span.children?.any(hasBoldColon) ?? false;
    }

    bool hasPlainColon(InlineSpan span) {
      if (span is! TextSpan) return false;
      if (span.text == ':' && span.style?.fontWeight != FontWeight.bold) {
        return true;
      }
      return span.children?.any(hasPlainColon) ?? false;
    }

    final processText = tester
        .widgetList<RichText>(find.byType(RichText))
        .where((w) => w.text.toPlainText().contains('固化剂'))
        .toList();
    expect(processText, isNotEmpty);
    expect(hasBoldColon(processText.first.text), isTrue);
    expect(hasPlainColon(processText.first.text), isFalse);
    expect(processText.first.text.toPlainText(), contains('固化剂 : N3300'));
    final label = processText.first.text;
    expect(label.toPlainText().startsWith('固化剂'), isTrue);
  });
}
