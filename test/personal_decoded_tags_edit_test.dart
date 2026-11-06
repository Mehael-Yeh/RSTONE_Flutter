import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';

void main() {
  for (final tags in ['  - "custom"\n  - "sample"', "  - 'custom'\n  - 'sample'"]) {
    testWidgets('personal edit decodes valid quoted tag sequence $tags', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService(); await tester.runAsync(prefs.initialize);
      final setup = await tester.runAsync(() async {
        final f = SignedFixture(); await f.initialize();
        final storage = await f.memoryStorage(); final app = await f.app(storage);
        await app.addProductMarkdown(code: 'QuotedTags', markdown: '---\ntags:\n$tags\n工程师: before\n---\nbody stays');
        return (storage, app);
      });
      final (storage, app) = setup!;
      await tester.pumpWidget(MaterialApp(home: ProductListPage(dataService: app, preferencesService: prefs)));
      await tester.pumpAndSettle(); await tester.tap(find.byTooltip('编辑产品信息')); await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text, 'custom sample');
      final engineer = find.byType(TextField).at(2);
      await tester.ensureVisible(engineer); await tester.enterText(engineer, 'after');
      await tester.tap(find.text('保存')); await tester.pumpAndSettle();
      expect(app.products.single.engineer, 'after');
      expect(app.products.single.tags, ['custom', 'sample']);
      final raw = await tester.runAsync(() => storage.readText('user/产品列表/QuotedTags.md'));
      expect(raw, contains('body stays')); expect(tester.takeException(), isNull);
    });
  }
}
