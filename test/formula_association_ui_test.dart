import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';
import 'package:rst_flutter/widgets/obsidian_table.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductItem _product(String grade, {String content = ''}) =>
    ProductItem.fromMdContent('产品列表/$grade.md', content);

ProductItem _formula(String name, {String content = ''}) =>
    ProductItem.fromMdContent('产品配方/$name.md', content);

Future<void> _pumpDetail(
  WidgetTester tester,
  ProductItem product,
  List<ProductItem> formulas,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
        body: ProductDetailSheet(product: product, formulas: formulas)),
  ));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _pumpTable(
  WidgetTester tester, {
  required bool isMobile,
  required List<ProductItem> items,
  required List<ProductItem> formulas,
}) async {
  tester.view.physicalSize =
      isMobile ? const Size(320, 800) : const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = PreferencesService();
  await prefs.initialize();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ObsidianTable(
        items: items,
        formulas: formulas,
        tdsByProduct: const {},
        defaultColumns: const ['牌号', '标签'],
        availableColumns: const ['牌号', '标签'],
        isMobile: isMobile,
        onColumnsChanged: (_) {},
        onSortChanged: (_) {},
        onSortDirectionChanged: (_) {},
        preferencesService: prefs,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('base grade does not display a suffixed variant formula',
      (tester) async {
    await _pumpDetail(tester, _product('RS7959'), [
      _formula('RS7959-2-哑', content: '''
| 原料编号 | 投入数(g) | 百分比(%) | 供应商 |
| --- | --- | --- | --- |
| [[RS7959-2]] | 70.00 | 71.283% | 锐石 |
'''),
    ]);

    expect(find.text('配方：RS7959-2-哑'), findsNothing);
  });

  testWidgets('experimental grade does not match an adjacent grade prefix',
      (tester) async {
    await _pumpDetail(
      tester,
      _product('RS1001', content: '---\n实验牌号: RD10\n---\n'),
      [_formula('RD100-亮')],
    );

    expect(find.text('配方：RD100-亮'), findsNothing);
  });

  testWidgets('experimental formula presence also removes duplicate wiki links',
      (tester) async {
    await _pumpDetail(
      tester,
      _product('RS1001', content: '---\n实验牌号: RD10\n---\n[[RD10-亮]]\n'),
      [_formula('RD10-亮')],
    );

    expect(find.text('配方：RD10-亮'), findsOneWidget);
    expect(find.text('RD10-亮', findRichText: true), findsNothing);
  });

  for (final isMobile in [true, false]) {
    testWidgets(
        '${isMobile ? 'mobile' : 'desktop'} blend badge opens the same formula as detail',
        (tester) async {
      await _pumpTable(tester, isMobile: isMobile, items: [
        _product('RS1002'),
        _product('RS1002-2B')
      ], formulas: [
        _formula('RS1001-亮', content: '''
| 原料编号 | 投入数(g) |
| --- | --- |
| [[RS1001]] | 60 |
| [[RS1002-2B]] | 40 |
'''),
      ]);

      final badge = find.byKey(const ValueKey('formula-badge:RS1002-2B'));
      expect(badge, findsOneWidget);
      expect(find.byKey(const ValueKey('formula-badge:RS1002')), findsNothing);
      expect(find.text('配方 1'), findsOneWidget);
      await tester.tap(badge);
      await tester.pumpAndSettle();
      expect(find.text('配方：RS1001-亮'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
      'explicit aliases share deduplicated counts and selectable formulas',
      (tester) async {
    final first =
        _formula('混拼方案A', content: '---\n关联产品: "[[RD910-22]]"\n---\n');
    final second = _formula('混拼方案B', content: '---\n关联产品: "[[RS7965]]"\n---\n');
    await _pumpTable(tester, isMobile: true, items: [
      _product('RS7965', content: '---\n实验牌号: RD910-22\n---\n'),
      _product('RS7966', content: '---\n实验牌号: RD910-2\n---\n'),
    ], formulas: [
      first,
      first,
      second
    ]);

    expect(find.text('配方 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('formula-badge:RS7966')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('formula-badge:RS7965')));
    await tester.pumpAndSettle();
    expect(find.text('配方：混拼方案A'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('混拼方案B').last);
    await tester.pumpAndSettle();
    expect(find.text('配方：混拼方案B'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
  });
}
