import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/pages/search_page.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';
import 'support/sync_fixture.dart';

void main() {
  testWidgets('personal same-code detail never receives official TDS',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await tester.runAsync(prefs.initialize);
    final app = (await tester.runAsync(() async {
      final f = SignedFixture();
      await f.initialize();
      final s = await f.memoryStorage();
      final a = await f.app(s);
      await f.publish(1, {
        '产品列表/RD900501.md': product('official'),
        '产品TDS/RD900501.TDS.md': '# official TDS'
      });
      expect(await a.sync!.synchronize(), isTrue);
      expect(a.tdsForItem(a.products.single), '# official TDS');
      await a.addProductMarkdown(
          code: 'RD900501', markdown: product('personal'));
      return a;
    }))!;
    await tester.pumpWidget(MaterialApp(
        home: ProductListPage(dataService: app, preferencesService: prefs)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RD900501').last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ProductDetailSheet>(find.byType(ProductDetailSheet))
            .tdsContent,
        isNull);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(
        home: SearchPage(
            dataService: app,
            preferencesService: prefs,
            onThemeModeChanged: (_) async {},
            themeSeedColor: Colors.blue,
            onThemeSeedColorChanged: (_) async {},
            themeMode: ThemeMode.system)));
    await tester.enterText(find.byType(TextField), 'RD900501');
    await tester.pumpAndSettle();
    await tester.tap(find.text('RD900501').last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ProductDetailSheet>(find.byType(ProductDetailSheet))
            .tdsContent,
        isNull);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
