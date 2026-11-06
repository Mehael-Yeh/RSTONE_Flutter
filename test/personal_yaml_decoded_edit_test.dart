import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';

void main() {
  final cases = [
    '工程师: |+\n  First\n  Second\n\n固含: 40\n技术源: before',
    '工程师: "A\\nB"\n技术源: \'O\'\'Brien\'\n粘度: 12.5\n官能度: true',
    '工程师: |-\n  BOM Name\n技术源: bom source',
  ];
  for (var c = 0; c < cases.length; c++) {
    testWidgets('personal edit decodes YAML scalar fields and retains unchanged values case $c', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService(); await tester.runAsync(prefs.initialize);
      final extra = cases[c]; final before = loadYaml(extra) as YamlMap;
      final setup = await tester.runAsync(() async {
        final f = SignedFixture(); await f.initialize();
        final storage = await f.memoryStorage(); final app = await f.app(storage);
        final bom = c == 2 ? '\uFEFF' : '';
        await app.addProductMarkdown(code: 'DecodedFields', markdown: '$bom---\ntags: [custom]\n$extra\n---\nbody stays');
        return (storage, app);
      });
      final (storage, app) = setup!;
      await tester.pumpWidget(MaterialApp(home: ProductListPage(dataService: app, preferencesService: prefs)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('编辑产品信息')); await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text, before['工程师']);
      expect(tester.widget<TextField>(find.byType(TextField).at(11)).controller!.text, before['技术源']);
      final benchmark = find.byType(TextField).at(12);
      await tester.ensureVisible(benchmark); await tester.enterText(benchmark, 'new benchmark');
      await tester.tap(find.text('保存')); await tester.pumpAndSettle();
      expect(app.products.single.benchmark, 'new benchmark');
      expect(app.products.single.rawContent.startsWith('\uFEFF'), c == 2);
      if (c == 2) {
        final bytes = (await tester.runAsync(() => storage.read('user/产品列表/DecodedFields.md')))!;
        expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      }
      final raw = (await tester.runAsync(() => storage.readText('user/产品列表/DecodedFields.md')))!;
      final metadata = loadYaml(RegExp(r'^---\n([\s\S]*?)\n---').firstMatch(raw)!.group(1)!) as YamlMap;
      for (final entry in before.entries) {
        expect(metadata[entry.key], entry.value, reason: 'unrelated edit must retain ${entry.key}');
        expect(metadata[entry.key].runtimeType, entry.value.runtimeType);
      }
      expect(raw, contains('body stays')); expect(tester.takeException(), isNull);
    });
  }
}
