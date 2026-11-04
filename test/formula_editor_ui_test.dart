import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/pages/product_applications_page.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';
import 'formula_structured_test.dart' show document;

void main() {
  testWidgets(
      'quarantined originals have a visible notice on the application page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final f = SignedFixture();
    await tester.runAsync(f.initialize);
    final store = (await tester.runAsync(f.memoryStorage))!;
    await tester.runAsync(() => store.writeText('user/产品配方/bad.md',
        document().replaceFirst('rstone-recipe/1', 'rstone-recipe/9')));
    final app = (await tester.runAsync(() => f.app(store)))!;
    final prefs = PreferencesService();
    await tester.runAsync(prefs.initialize);
    await tester.pumpWidget(MaterialApp(
        home: ProductApplicationsPage(
            dataService: app, preferencesService: prefs)));
    await tester.pumpAndSettle();
    expect(find.textContaining('个人配方已隔离'), findsOneWidget);
    expect(find.byTooltip('查看隔离详情'), findsOneWidget);
    await tester.tap(find.byTooltip('查看隔离详情'));
    await tester.pumpAndSettle();
    expect(find.textContaining('产品配方/bad.md'), findsOneWidget);
    expect(find.textContaining('原文保留'), findsWidgets);
    app.dispose();
    await store.close();
  });
  testWidgets(
      'empty applications page offers structured personal creation; form saves exact five cells + ordered process',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final f = SignedFixture();
    await tester.runAsync(f.initialize);
    final store = (await tester.runAsync(f.memoryStorage))!;
    final app = await tester.runAsync(() => f.app(store));
    await tester.runAsync(() async {
      await f.publish(1, {'产品列表/RS87654321-Q5.md': product('水性')});
      expect(await app!.sync!.synchronize(), isTrue);
    });
    final prefs = PreferencesService();
    await tester.runAsync(prefs.initialize);
    await tester.pumpWidget(MaterialApp(
        home: ProductApplicationsPage(
            dataService: app!, preferencesService: prefs)));
    await tester.pumpAndSettle();
    final add = find.byTooltip('新增产品配方');
    expect(add, findsOneWidget);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('recipe-title')), '个人合成配方');
    await tester.enterText(
        find.byKey(const ValueKey('recipe-owner')), 'RS87654321-Q5');
    await tester.enterText(
        find.byKey(const ValueKey('recipe-associations')), 'RS87654321-Q5');
    await tester.enterText(find.byKey(const ValueKey('recipe-input')),
        '原料编号\t投入数(g)\t百分比(%)\t供应商\t备注\nwater\t10-12\t\t\t" a|b\nnext "');
    await tester.enterText(find.byKey(const ValueKey('recipe-content')),
        '[{"kind":"note","text":"说明"},{"kind":"process","label":"分支甲","steps":["先加水","再混合"]}]');
    final save = find.byKey(const ValueKey('recipe-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(app.formulas, hasLength(1));
    final d = app.formulas.single.formulaDocument!;
    expect(d.rows, [
      ['water', '10-12', '', '', ' a|b\nnext ']
    ]);
    expect(d.content, hasLength(2));
    expect(d.classification, 'unverified');
    expect(d.recipeId, startsWith('personal-'));
    app.dispose();
    await store.close();
  });
}
