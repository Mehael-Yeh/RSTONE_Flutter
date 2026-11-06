import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'package:rst_flutter/widgets/note_swipe_tile.dart';
import 'support/sync_fixture.dart';

void main() {
  testWidgets('renaming personal product retains its actual list note editor content', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService(); await tester.runAsync(prefs.initialize);

    final app = (await tester.runAsync(() async {
      final f = SignedFixture(); await f.initialize();
      final app = await f.app(await f.memoryStorage());
      await app.addProductMarkdown(code: 'BeforeNote', markdown: '---\ntags: [custom]\n---\n');
      return app;
    }))!;
    await tester.pumpWidget(MaterialApp(home: ProductListPage(dataService: app, preferencesService: prefs)));
    await tester.pumpAndSettle();
    final initialTile = tester.widget<NoteSwipeTile>(find.byType(NoteSwipeTile).first);
    final initialEditing = initialTile.onNoteTap!(); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'synthetic private memo');
    await tester.tap(find.text('确认')); await tester.pumpAndSettle(); await initialEditing;
    await tester.tap(find.byTooltip('编辑产品信息')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'AfterNote');
    await tester.tap(find.text('保存')); await tester.pumpAndSettle();
    expect(app.products.single.fileName, 'AfterNote');
    final tile = tester.widget<NoteSwipeTile>(find.byType(NoteSwipeTile).first);
    final editing = tile.onNoteTap!(); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'synthetic private memo');
    Navigator.of(tester.element(find.byType(TextField).first)).pop();
    await tester.pumpAndSettle(); await editing;
  });
}
