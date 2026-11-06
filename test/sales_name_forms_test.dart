// Synthetic sales workflow fixtures only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/pages/product_applications_page.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';

Future<void> pull(WidgetTester tester) async {
  final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
  OverscrollNotification(metrics: state.position, context: state.context, overscroll: -80).dispatch(state.context);
  ScrollEndNotification(metrics: state.position, context: state.context).dispatch(state.context);
  await tester.pumpAndSettle();
}

void main() {
  for (final isProduct in [true, false]) {
    testWidgets('${isProduct ? "product" : "application"} name-only create cancel reload and collision', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService();
      await tester.runAsync(prefs.initialize);
      final f = SignedFixture();
      await tester.runAsync(f.initialize);
      final s = (await tester.runAsync(f.memoryStorage))!;
      final app = (await tester.runAsync(() => f.app(s)))!;
      await tester.runAsync(() async {
        for (var i = 0; i < 12; i++) {
          if (isProduct) {
            await app.addProductMarkdown(code: 'SyntheticSales7200$i', markdown: '---\ntags: []\n---');
          } else {
            await app.addApplicationMarkdown(name: 'SyntheticSales7200$i', markdown: '---\ntags: []\n---');
          }
        }
      });
      await tester.pumpWidget(MaterialApp(home: isProduct
          ? ProductListPage(dataService: app, preferencesService: prefs)
          : ProductApplicationsPage(dataService: app, preferencesService: prefs)));
      await tester.pumpAndSettle();
      Future<void> open() async {
        await pull(tester);
        await tester.tap(find.text(isProduct ? '新增产品信息' : '新增产品应用'));
        await tester.pumpAndSettle();
        expect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).hitTestable(), findsOneWidget);
      }
      final path = 'user/${isProduct ? "产品列表" : "产品应用"}/SyntheticSales710999.md';
      await open();
      await tester.enterText(find.byType(TextField).first, 'SyntheticSales710999');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => s.readText(path)), isNull);
      await open();
      await tester.enterText(find.byType(TextField).first, 'SyntheticSales710999');
      await tester.tap(find.text('保存'));
      await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 100)); });
      await tester.pumpAndSettle();
      final saved = await tester.runAsync(() => s.readText(path));
      expect(saved, isNotNull);
      await tester.runAsync(app.reloadUserItems);
      final items = isProduct ? app.products : app.applications;
      final item = items.singleWhere((p) => p.fileName == 'SyntheticSales710999');
      expect(item.tags, isEmpty);
      expect(item.engineer ?? '', isEmpty);
      expect(item.primer ?? '', isEmpty);
      expect(find.text('SyntheticSales710999'), findsWidgets);
      await open();
      await tester.enterText(find.byType(TextField).first, 'SyntheticSales710999');
      await tester.tap(find.text('保存'));
      await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 100)); });
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => s.readText(path)), saved);
      app.dispose();
      await tester.runAsync(s.close);
    });
  }
}
