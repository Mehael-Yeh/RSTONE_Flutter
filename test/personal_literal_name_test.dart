import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';

void main() {
  test('personal filename stem removes only the terminal storage extension', () {
    for (final name in ['Sample.md', 'Sample.md.v1', 'Sample.md.md']) {
      for (final origin in [DataOrigin.user, DataOrigin.unknown]) {
        final item = ProductItem.fromMdContent(
            'user/产品列表/$name.md', '---\ntags: []\n---\n', origin: origin);
        expect(item.fileName, name);
      }
    }
  });
  testWidgets('unrelated personal edit preserves a literal md product name and path', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await tester.runAsync(prefs.initialize);
    final setup = await tester.runAsync(() async {
      final f = SignedFixture(); await f.initialize();
      final s = await f.memoryStorage(); final app = await f.app(s);
      await app.addProductMarkdown(code: 'Sample.md',
          markdown: app.buildProductMarkdownTemplate(tags: ['custom'], engineer: 'before'));
      return (s, app);
    });
    final (s, app) = setup!;
    await tester.pumpWidget(MaterialApp(home: ProductListPage(dataService: app, preferencesService: prefs)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑产品信息')); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'Sample.md');
    final engineer = find.byType(TextField).at(2);
    await tester.ensureVisible(engineer); await tester.enterText(engineer, 'after');
    await tester.tap(find.text('保存')); await tester.pumpAndSettle();
    expect(app.products.single.fileName, 'Sample.md');
    expect(app.products.single.engineer, 'after');
    expect(await tester.runAsync(() => s.readText('user/产品列表/Sample.md.md')), isNotNull);
    expect(await tester.runAsync(() => s.readText('user/产品列表/Sample.md')), isNull);
    expect(tester.takeException(), isNull);
  });
}
