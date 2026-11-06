import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'package:rst_flutter/widgets/obsidian_table.dart';
import 'package:rst_flutter/widgets/product_detail/structured_formula_card.dart';
import 'package:rst_flutter/utils/formula_table_clipboard_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';
import 'formula_structured_test.dart' show specimen, document;

void main() {
  testWidgets(
      'application selection preserves the exact structured personal filename including internal .md',
      (tester) async {
    final m = specimen()..['title'] = '我的产品列表.md配方';
    final recipe =
        ProductItem.fromMdContent('user/产品配方/我的产品列表.md配方.md', document(m));
    final app = ProductItem.fromMdContent(
        'user/产品应用/synthetic.md', '---\n底漆: 我的产品列表.md配方\n---\n');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProductDetailSheet(
                product: app, productCatalog: const [], formulas: [recipe]))));
    await tester.pumpAndSettle();
    expect(find.byType(StructuredFormulaCard), findsOneWidget);
  });
  for (final mobile in [true, false]) {
    testWidgets(
        'typed multi-grade filtered ${mobile ? 'phone' : 'desktop'} badge opens the same card and clipboard view',
        (tester) async {
      tester.view.physicalSize =
          mobile ? const Size(390, 844) : const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService();
      await prefs.initialize();
      final owner = ProductItem.fromMdContent('产品列表/RS87654321-Q5.md', '');
      final extra = ProductItem.fromMdContent('产品列表/RS222-X.md', '');
      final m = specimen()
        ..['associatedProducts'] = ['RS87654321-Q5', 'RS222-X'];
      m['rows'][0][4] = '  a|b\nsecond  ';
      final f =
          ProductItem.fromMdContent('产品配方/RS87654321-Q5-底.md', document(m));
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'];
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ObsidianTable(
                  items: [extra],
                  productCatalog: [owner, extra],
                  formulas: [f],
                  tdsByProduct: const {},
                  defaultColumns: const ['牌号'],
                  availableColumns: const ['牌号'],
                  isMobile: mobile,
                  onColumnsChanged: (_) {},
                  onSortChanged: (_) {},
                  onSortDirectionChanged: (_) {},
                  preferencesService: prefs))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('formula-badge:RS222-X')));
      await tester.pumpAndSettle();
      expect(find.byType(StructuredFormulaCard), findsOneWidget);
      final card = tester
          .widget<StructuredFormulaCard>(find.byType(StructuredFormulaCard));
      expect(identical(card.view.document, f.formulaDocument), isTrue);
      await tester.tap(find.byTooltip('复制配方五列'));
      await tester.pumpAndSettle();
      expect(FormulaTableClipboardParser.parse(copied!).rows,
          f.formulaDocument!.rows);
      final scroll =
          find.byKey(ValueKey('recipe-scroll:${f.formulaDocument!.recipeId}'));
      await tester.drag(scroll, const Offset(-2000, 0));
      await tester.pumpAndSettle();
      final last = find
          .byKey(ValueKey('recipe-cell:${f.formulaDocument!.recipeId}:1:4'));
      expect(
          tester.getRect(last).right <= tester.view.physicalSize.width, isTrue);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
    });
  }
  testWidgets(
      'actual application selector uses exact recipe names, not product expansion, and changes typed cards',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final owner = ProductItem.fromMdContent('产品列表/RS87654321-Q5.md', '');
    final first =
        ProductItem.fromMdContent('产品配方/RS87654321-Q5-底.md', document());
    final m = specimen()
      ..['title'] = 'RS87654321-Q5-亮'
      ..['recipeId'] = 'SYNTH-SECOND';
    m['rows'][0][4] = 'SECOND CARD';
    final second =
        ProductItem.fromMdContent('产品配方/RS87654321-Q5-亮.md', document(m));
    final app = ProductItem.fromMdContent('产品应用/synthetic.md',
        '---\n底漆: RS87654321-Q5-底\n面漆: RS87654321-Q5-亮\n中漆: RS87654321-Q5\n---\n');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProductDetailSheet(
                product: app,
                productCatalog: [owner],
                formulas: [first, second]))));
    await tester.pumpAndSettle();
    expect(find.byType(StructuredFormulaCard), findsOneWidget);
    expect(
        tester
            .widget<StructuredFormulaCard>(find.byType(StructuredFormulaCard))
            .view
            .document
            .recipeId,
        first.formulaDocument!.recipeId);
    await tester.tap(find.text('RS87654321-Q5-亮'));
    await tester.pumpAndSettle();
    expect(find.text('SECOND CARD'), findsOneWidget);
    final productOnly = ProductItem.fromMdContent(
        '产品应用/only-product.md', '---\n底漆: RS87654321-Q5\n---\n');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProductDetailSheet(
                product: productOnly,
                productCatalog: [owner],
                formulas: [first, second]))));
    await tester.pumpAndSettle();
    expect(find.byType(StructuredFormulaCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'typed product detail displays five raw strings and ordered note/process without reparsing Markdown',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final product = ProductItem.fromMdContent('产品列表/RS87654321-Q5.md', '');
    final model = specimen();
    model['rows'][0][4] = '  keep|pipe\nsecond line  ';
    final f =
        ProductItem.fromMdContent('产品配方/RS87654321-Q5-底.md', document(model));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProductDetailSheet(
                product: product, productCatalog: [product], formulas: [f]))));
    await tester.pumpAndSettle();
    expect(find.text('合成厂商'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(StructuredFormulaCard),
            matching: find.text('RS87654321-Q5', findRichText: true)),
        findsOneWidget);
    expect(find.text('  keep|pipe\nsecond line  '), findsOneWidget);
    expect(find.text('配制与施工（工艺分支1）：'), findsOneWidget);
    expect(find.text('尾段原文，不得移动到工艺之前。'), findsOneWidget);
    expect(find.byTooltip('复制配方五列'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
