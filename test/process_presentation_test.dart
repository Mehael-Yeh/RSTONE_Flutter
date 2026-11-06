import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/widgets/product_detail/structured_formula_card.dart';
import 'package:rst_flutter/widgets/product_detail/formula_presentation.dart';
import 'package:rst_flutter/widgets/product_detail/formula_png_renderer.dart';
import 'package:rst_flutter/widgets/product_detail/process_presentation.dart';
import 'formula_display_contract_test.dart' show synthetic;

void main() {
  test(
      'ambiguous, duplicate, short, numbered and ragged process blocks stay verbatim',
      () {
    for (final steps in [
      ['字段  字段', '合成900001  一', '合成900002  二'],
      ['字段  说明', '合成900001  一'],
      ['字段  说明', '字段  说明', '合成900002  二'],
      ['1. 工序  条件', '2. 合成900001  一', '3. 合成900002  二'],
      ['字段  说明  条件', '合成900001  一  完整', '合成900002  缺格'],
      ['字段  说明', '合成900001  一  多格', '合成900002  二'],
      ['说明，保', '温度：独立标题', '说明，保', '2. 温2 小时另工序'],
      ['说明', '下一段不自动拼接', '保', '温2 小时无确认上下文'],
    ]) {
      expect(presentFormulaProcess(steps), steps);
    }
  });
  for (final schema in ['rstone-recipe/1', 'rstone-recipe/2']) {
    testWidgets(
        '$schema conservative process reflow and rectangular fields agree in screen and PNG',
        (tester) async {
      final raw = synthetic(length: 1).toJson()..['schema'] = schema;
      final steps = [
        '1. 下线后执行70±2℃，保',
        '温2 小时的后处理，保留原条件。',
        '2. 下一道工序，保',
        '3. 温度另列，不能合并。',
        '工段      波段      能量      说明',
        '灯段900001      UVV      600~3000mJ/cm²      适配395nm光源',
        '灯段900002      UVC      150~450mJ/cm²      适配254nm光源',
        '灯段900003      UVA      500~1200mJ/cm²      光强80~150mw',
        '4. 表后步骤',
        '项目      数量      条件',
        '合成900004      1      完整',
        '合成900005      缺格',
        '保',
        '温度：单独标题不能合并',
      ];
      raw['content'] = [
        {'kind': 'process', 'label': '合成工艺900000：', 'steps': steps}
      ];
      final d = FormulaDocument.fromJson(raw);
      final expected = [
        '1. 下线后执行70±2℃，保温2 小时的后处理，保留原条件。',
        '2. 下一道工序，保',
        '3. 温度另列，不能合并。',
        '工段：灯段900001\n波段：UVV\n能量：600~3000mJ/cm²\n说明：适配395nm光源',
        '工段：灯段900002\n波段：UVC\n能量：150~450mJ/cm²\n说明：适配254nm光源',
        '工段：灯段900003\n波段：UVA\n能量：500~1200mJ/cm²\n说明：光强80~150mw',
        ...steps.skip(8),
      ];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: StructuredFormulaCard(document: d)))));
      await tester.pumpAndSettle();
      for (final text in expected) {
        expect(find.text(text), findsOneWidget);
      }
      final plan = FormulaPngRenderer.layout(FormulaDisplayView(d));
      expect(plan.text.map((n) => n.text).skip(12).toList(), expected);
      final png = await tester
          .runAsync(() => FormulaPngRenderer.render(FormulaDisplayView(d)));
      expect(png!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(d.toJson(), raw);
      expect((d.content.single as FormulaProcess).steps, steps);
      expect(tester.takeException(), isNull);
    });
  }
}
