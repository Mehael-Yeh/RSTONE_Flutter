import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';

void main() {
  final openings = ['---\n', '\uFEFF\t---\t\r\n', 'intro\n  ---  \n'];
  final closings = ['---  \n', '\t---\t\r\n', '  ---  '];
  for (var c = 0; c < openings.length; c++) {
    testWidgets('personal edit retains whitespace-tolerant metadata delimiters case $c', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService(); await tester.runAsync(prefs.initialize);
      const body = 'body stays\r\n\nparagraph';
      final raw = '${openings[c]}tags: [custom]\n工程师: before\nunknown: {1: keep}\n${closings[c]}\n$body';
      final setup = await tester.runAsync(() async {
        final f = SignedFixture(); await f.initialize();
        final storage = await f.memoryStorage(); final app = await f.app(storage);
        await app.addProductMarkdown(code: 'SpacedHeader', markdown: raw);
        return (storage, app);
      });
      final (storage, app) = setup!;
      expect(app.products.single.engineer, 'before');
      await tester.pumpWidget(MaterialApp(home: ProductListPage(dataService: app, preferencesService: prefs)));
      await tester.pumpAndSettle(); await tester.tap(find.byTooltip('编辑产品信息')); await tester.pumpAndSettle();
      final benchmark = find.byType(TextField).at(12);
      await tester.ensureVisible(benchmark); await tester.enterText(benchmark, 'after');
      await tester.tap(find.text('保存')); await tester.pumpAndSettle();
      expect(app.products.single.benchmark, 'after');
      final saved = (await tester.runAsync(() => storage.readText('user/产品列表/SpacedHeader.md')))!;
      final lines = saved.split('\n');
      final start = lines.indexWhere((line) => line.trim() == '---');
      final end = lines.indexWhere((line) => line.trim() == '---', start + 1);
      final metadata = loadYaml(lines.sublist(start + 1, end).join('\n')) as YamlMap;
      expect(metadata['unknown'], {1: 'keep'});
      expect(metadata['工程师'], 'before');
      expect(lines.where((line) => line.trim() == '---').length, 2);
      expect(saved, endsWith(body));
      if (c == 2) expect(saved, startsWith('intro\n'));
      if (c == 1) {
        final bytes = (await tester.runAsync(() => storage.read('user/产品列表/SpacedHeader.md')))!;
        expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
