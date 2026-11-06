import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/pages/search_page.dart';
import 'package:rst_flutter/widgets/note_swipe_tile.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';

void main() {
  testWidgets(
      'own title edit prefills every add field; cancel does not persist; save renames',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await tester.runAsync(prefs.initialize);
    final setup = await tester.runAsync(() async {
      final f = SignedFixture();
      await f.initialize();
      final s = await f.memoryStorage();
      final app = await f.app(s);
      await f.publish(1, {'产品列表/RD900901.md': product('official')});
      await app.sync!.synchronize();
      return (s, app);
    });
    final (s, app) = setup!;
    const fields = [
      '工程师',
      '实验牌号',
      '固含',
      '羟值',
      '官能度',
      '硬度',
      '光泽(60°)',
      '水煮',
      '水接触角',
      '技术源',
      '对标',
      '粘度'
    ];
    final raw = '---\ntags: [personal]\n${[
      for (var i = 0; i < fields.length; i++) '${fields[i]}: value$i'
    ].join('\n')}\n额外字段: keep\n---\nbody stays';
    await tester
        .runAsync(() => app.addProductMarkdown(code: '自定义', markdown: raw));
    await tester.pumpWidget(MaterialApp(
        home: ProductListPage(dataService: app, preferencesService: prefs)));
    await tester.pumpAndSettle();
    final originalTile = find.ancestor(of: find.text('自定义').first,
        matching: find.byType(NoteSwipeTile));
    final writingOriginal = tester.widget<NoteSwipeTile>(originalTile.first).onNoteTap!();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'synthetic personal note');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    await writingOriginal;
    expect(find.byTooltip('编辑产品信息'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑产品信息'));
    await tester.pumpAndSettle();
    expect(find.text('编辑产品信息'), findsOneWidget);
    final values = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((w) => w.controller!.text)
        .toList();
    expect(
        values,
        containsAll([
          '自定义',
          'personal',
          for (var i = 0; i < fields.length; i++) 'value$i'
        ]));
    await tester.enterText(find.byType(TextField).first, 'Cancelled');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => s.readText('user/产品列表/自定义.md')), raw);
    expect(await tester.runAsync(() => s.readText('user/产品列表/Cancelled.md')),
        isNull);
    expect(prefs.getProductNote('自定义'), 'synthetic personal note');
    expect(prefs.getProductNote('Cancelled'), isEmpty);
    await tester.tap(find.byTooltip('编辑产品信息'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ABC');
    for (var i = 1; i < 14; i++) {
      final field = find.byType(TextField).at(i);
      await tester.ensureVisible(field);
      await tester.enterText(
          field,
          i == 1
              ? 'updated'
              : i == 2
                  ? 'quote " and \\ slash'
                  : 'changed$i');
    }
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(prefs.getProductNote('ABC'), 'synthetic personal note');
    expect(prefs.getProductNote('自定义'), isEmpty);
    expect(await tester.runAsync(() => s.readText('user/产品列表/自定义.md')), isNull);
    final saved = await tester.runAsync(() => s.readText('user/产品列表/ABC.md'));
    expect(saved, contains('body stays'));
    expect(saved, contains('keep'));
    final edited = app.products.firstWhere((p) => p.fileName == 'ABC');
    expect(edited.tags, ['updated']);
    expect([
      edited.engineer,
      edited.experimentalCode,
      edited.solidContent,
      edited.hydroxylValue,
      edited.functionality,
      edited.hardness,
      edited.gloss60,
      edited.boilResistance,
      edited.waterContactAngle,
      edited.technologySource,
      edited.benchmark,
      edited.viscosity
    ], [
      for (var i = 2; i < 14; i++) i == 2 ? 'quote " and \\ slash' : 'changed$i'
    ]);
    tester.view.physicalSize = const Size(2400, 844);
    await tester.pumpWidget(MaterialApp(
        home: ProductListPage(
            key: UniqueKey(), dataService: app, preferencesService: prefs)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('编辑产品信息'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑产品信息'));
    await tester.pumpAndSettle();
    expect(find.text('编辑产品信息'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    // Exercise the real table callback and editor, then the real search
    // callback/editor against the same service, not only a preferences getter.
    final tableTile = find.ancestor(of: find.text('ABC').first,
        matching: find.byType(NoteSwipeTile));
    tester.widget<NoteSwipeTile>(tableTile.first).onNoteTap!();
    await tester.pumpAndSettle();
    expect(tester.widget<NoteEditorDialog>(find.byType(NoteEditorDialog)).initialValue,
        'synthetic personal note');
    await tester.enterText(find.descendant(of: find.byType(NoteEditorDialog), matching: find.byType(TextField)), 'table updated note');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(home: SearchPage(
      dataService: app, preferencesService: prefs,
      onThemeModeChanged: (_) async {}, themeSeedColor: Colors.orange,
      onThemeSeedColorChanged: (_) async {}, themeMode: ThemeMode.system,
    )));
    await tester.enterText(find.byType(TextField), 'ABC');
    await tester.pumpAndSettle();
    tester.widget<NoteSwipeTile>(find.byType(NoteSwipeTile).first).onNoteTap!();
    await tester.pumpAndSettle();
    expect(tester.widget<NoteEditorDialog>(find.byType(NoteEditorDialog)).initialValue,
        'table updated note');
    await tester.enterText(find.descendant(of: find.byType(NoteEditorDialog), matching: find.byType(TextField)), 'search updated note');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    await tester.runAsync(app.reloadUserItems);
    expect(prefs.getProductNote('ABC'), 'search updated note');
    expect(prefs.getProductNote('自定义'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
