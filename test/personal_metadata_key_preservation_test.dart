import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';

void main() {
  final cases = [
    <String>['#note'],
    <String>['custom: key', 'true', '[]', '? literal', 'key\nline', '工程师 '],
  ];
  for (var c = 0; c < cases.length; c++) {
    testWidgets('editing retains literal unknown metadata keys case $c', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService();
      await tester.runAsync(prefs.initialize);
      final keys = cases[c];
      final setup = await tester.runAsync(() async {
        final f = SignedFixture(); await f.initialize();
        final storage = await f.memoryStorage(); final app = await f.app(storage);
        final extra = [for (var i = 0; i < keys.length; i++) '${jsonEncode(keys[i])}: ${jsonEncode('keep$i')}'].join('\n');
        await app.addProductMarkdown(code: 'UnknownKeys', markdown: '---\ntags:\n  - custom\n工程师: before\n$extra\n---\nbody stays');
        return (storage, app);
      });
      final (storage, app) = setup!;
      await tester.pumpWidget(MaterialApp(home: ProductListPage(dataService: app, preferencesService: prefs)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('编辑产品信息')); await tester.pumpAndSettle();
      final engineer = find.byType(TextField).at(2);
      await tester.ensureVisible(engineer); await tester.enterText(engineer, 'after');
      await tester.tap(find.text('保存')); await tester.pumpAndSettle();
      expect(app.products.single.engineer, 'after');
      final raw = (await tester.runAsync(() => storage.readText('user/产品列表/UnknownKeys.md')))!;
      final front = RegExp(r'^---\n([\s\S]*?)\n---').firstMatch(raw)!.group(1)!;
      expect(() => loadYaml(front), returnsNormally);
      final metadata = loadYaml(front) as YamlMap;
      for (var i = 0; i < keys.length; i++) {
        expect(metadata.containsKey(keys[i]), isTrue, reason: keys[i]);
        expect(metadata[keys[i]], 'keep$i');
      }
      expect(raw, contains('body stays'));
      expect(metadata['工程师'], 'after');
      expect(metadata['tags'], ['custom']);
      expect(tester.takeException(), isNull);
    });
  }
}
