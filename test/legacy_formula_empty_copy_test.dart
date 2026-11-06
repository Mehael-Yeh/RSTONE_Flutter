import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/utils/formula_table_clipboard_parser.dart';
import 'package:rst_flutter/widgets/product_detail/markdown_table_parser.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';

void main() {
  const header = '| 原料编号 | 投入数 | 百分比(%) | 供应商 | 备注 |\n| --- | --- | --- | --- | --- |\n';
  final rows = [
    '| [[RS900971]] | 10 | 100 | | |',
    '| [[RS900971]] | 10 | 100 | source | |',
    '| [[RS900971]] | 10 | 100 |',
  ];
  test('Markdown parsing retains empty actual first and last cells', () {
    final table = MarkdownTableParser.parseTable('$header| | 10 | 100 | source | |');
    expect(table.last, ['', '10', '100', 'source', '']);
  });
  for (var i = 0; i < rows.length; i++) {
    testWidgets('legacy copy retains five-column blank cells case $i', (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final product = ProductItem.fromMdContent('产品列表/RS900971.md', '---\ntags: [sample]\n---\n', origin: DataOrigin.official);
      final raw = '$header${rows[i]}';
      final formula = ProductItem.fromMdContent('产品配方/RS900971-银.md', raw, origin: DataOrigin.official);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProductDetailSheet(product: product, productCatalog: [product], formulas: [formula]))));
      await tester.pumpAndSettle();
      final copy = find.byTooltip('复制配方五列');
      expect(copy, findsOneWidget);
      await tester.ensureVisible(copy); await tester.tap(copy); await tester.pumpAndSettle();
      expect(copied, isNotNull);
      final parsed = FormulaTableClipboardParser.parse(copied!);
      expect(parsed.isValid, isTrue, reason: parsed.errorMessage);
      expect(parsed.rows.single, ['RS900971', '10', '100', i == 1 ? 'source' : '', '']);
      expect(formula.rawContent, raw);
      expect(tester.takeException(), isNull);
    });
  }
}
