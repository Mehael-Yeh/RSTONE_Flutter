// Synthetic sales workflow; no business catalogue data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/widgets/formula_editor_dialog.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'support/sync_fixture.dart';

void main() {
  testWidgets('name alone saves a personal pending recipe and reloads without a BOM', (tester) async {
    final f = SignedFixture();
    await tester.runAsync(f.initialize);
    final s = (await tester.runAsync(f.memoryStorage))!;
    final app = (await tester.runAsync(() => f.app(s)))!;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => showDialog<void>(context: context, builder: (_) => FormulaEditorDialog(dataService: app)), child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('recipe-title')), 'SyntheticSales710000');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(app.formulas, isEmpty);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final name in ['', '../SyntheticSales710000']) {
      await tester.enterText(find.byKey(const ValueKey('recipe-title')), name);
      await tester.tap(find.byKey(const ValueKey('recipe-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recipe-error')), findsOneWidget);
      expect(app.formulas, isEmpty);
    }
    await tester.enterText(find.byKey(const ValueKey('recipe-title')), 'SyntheticSales710001');
    // Inspecting an untouched optional section must not make name-only invalid.
    await tester.tap(find.text('填写完整配方（可选）'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('recipe-save')));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 100)); });
    await tester.pumpAndSettle();
    expect(app.formulas, hasLength(1));
    expect(app.formulas.single.origin, DataOrigin.user);
    expect(app.formulas.single.formulaDocument, isNull);
    expect(app.formulas.single.filePath, 'user/配方草稿/SyntheticSales710001.md');
    await tester.runAsync(app.reloadUserItems);
    expect(app.formulas.single.fileName, 'SyntheticSales710001');
    expect(app.quarantinedFormulas, isEmpty);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('recipe-title')), 'SyntheticSales710001');
    await tester.tap(find.byKey(const ValueKey('recipe-save')));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 100)); });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recipe-error')), findsOneWidget);
    expect(app.formulas, hasLength(1));
    await tester.enterText(find.byKey(const ValueKey('recipe-title')), 'SyntheticSales710002');
    await tester.tap(find.text('填写完整配方（可选）'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('recipe-owner')), 'SyntheticSales710003');
    await tester.tap(find.text('填写完整配方（可选）'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('recipe-save')));
    await tester.pumpAndSettle();
    // Collapsing incomplete details must not discard them or fabricate a BOM.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(app.formulas, hasLength(1));
    app.dispose();
    await tester.runAsync(s.close);
  });
}
