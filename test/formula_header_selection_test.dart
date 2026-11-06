import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';
import 'package:rst_flutter/widgets/product_detail/structured_formula_card.dart';
import 'formula_display_contract_test.dart' show synthetic;

List<ProductItem> recipes() => List.generate(2, (i) {
      final json = synthetic(length: 1, count: 3).toJson()
        ..['recipeId'] = 'SYNTH-90000$i'
        ..['title'] = 'Synthetic90000$i-${'long' * 18}'
        ..['rows'] = List.generate(
            3,
            (r) => [
                  'BOM90000$i-$r',
                  '$i',
                  '50',
                  'Supplier90000$i',
                  'Note90000$i'
                ]);
      final d = FormulaDocument.fromJson(json);
      return ProductItem(
          fileName: d.title,
          filePath: '产品配方/${d.title}.md',
          folder: '产品配方',
          rawContent: '',
          frontmatter: const {},
          formulaDocument: d);
    });

void main() {
  for (final width in [360.0, 412.0, 1200.0]) {
    testWidgets('selector is in header immediately after colon at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fs = recipes();
      final p = ProductItem.fromMdContent(
          '产品列表/${fs.first.formulaDocument!.ownerProduct}.md', '');
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ProductDetailSheet(
                  product: p, productCatalog: [p], formulas: fs))));
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownButton<int>);
      expect(dropdown, findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(StructuredFormulaCard), matching: dropdown),
          findsOneWidget);
      final colon = find.text('配方：');
      expect(colon, findsOneWidget);
      final a = tester.getRect(colon), b = tester.getRect(dropdown);
      expect((a.center.dy - b.center.dy).abs(), lessThan(1));
      expect(b.left - a.right, inInclusiveRange(0, 4));
      for (final tip in ['复制配方五列', '分享配方图片']) {
        final r = tester.getRect(find.byTooltip(tip));
        expect(r.width, greaterThanOrEqualTo(48));
        expect(r.height, greaterThanOrEqualTo(48));
        expect(r.left, greaterThanOrEqualTo(b.right));
        expect(r.right, lessThanOrEqualTo(width));
      }
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(fs.last.fileName).last);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<StructuredFormulaCard>(find.byType(StructuredFormulaCard))
              .view
              .document
              .recipeId,
          'SYNTH-900001');
      expect(find.text('BOM900001-0'), findsOneWidget);
      expect(find.text('BOM900000-0'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final legacy in [false, true]) {
    testWidgets(
        'application card owns selector for ${legacy ? 'legacy' : 'structured'}',
        (tester) async {
      final fs = legacy
          ? List.generate(
              2,
              (i) => ProductItem.fromMdContent('产品配方/Recipe90000$i.md',
                  '---\n关联产品: "[[RS900001]]"\n---\n| 原料编号 | 投入数 | 百分比(%) | 供应商 | 备注 |\n| --- | --- | --- | --- | --- |\n| BOM90000$i | 1 | 50 | Supplier90000$i | Note90000$i |'))
          : recipes();
      final app = ProductItem.fromMdContent('产品应用/App900001.md',
          '---\n底漆: ${fs.first.fileName.replaceAll('.md', '')}\n面漆: ${fs.last.fileName.replaceAll('.md', '')}\n---\n');
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ProductDetailSheet(
                  product: app, productCatalog: const [], formulas: fs))));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      expect(find.text('配方：'), findsOneWidget);
      expect(find.byTooltip('复制配方五列'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(fs.last.fileName.replaceAll('.md', '')).last);
      await tester.pumpAndSettle();
      expect(find.text(legacy ? 'BOM900001' : 'BOM900001-0'), findsOneWidget);
      expect(find.text(legacy ? 'BOM900000' : 'BOM900000-0'), findsNothing);
    });
  }
}
