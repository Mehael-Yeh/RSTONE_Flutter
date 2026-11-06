import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';

void main() {
  final cases = <String>[
    'measurements: {1: low, 2: high}\ndeep: [{true: yesValue, null: nilValue}]',
    '1: numeric\ntrue: boolean\nnull: nil\n"1": stringNumeric',
    'numbers: [.inf, -.inf, .nan]',
    'complex:\n  ? [1, x]\n  : listKey\n  ? {a: 1}\n  : mapKey\n? [root, 1]\n: rootList\n? {root: true}\n: rootMap',
  ];
  for (var c = 0; c < cases.length; c++) {
    testWidgets('personal edit preserves YAML metadata types case $c', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService(); await tester.runAsync(prefs.initialize);
      final extra = cases[c];
      final setup = await tester.runAsync(() async {
        final f = SignedFixture(); await f.initialize();
        final storage = await f.memoryStorage(); final app = await f.app(storage);
        await app.addProductMarkdown(code: 'TypedMetadata', markdown: '---\ntags: [custom]\n工程师: before\n$extra\n---\nbody stays');
        return (storage, app);
      });
      final (storage, app) = setup!;
      await tester.pumpWidget(MaterialApp(home: ProductListPage(dataService: app, preferencesService: prefs)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('编辑产品信息')); await tester.pumpAndSettle();
      final engineer = find.byType(TextField).at(2);
      await tester.ensureVisible(engineer); await tester.enterText(engineer, 'after');
      await tester.tap(find.text('保存')); await tester.pumpAndSettle();
      expect(app.products.single.engineer, 'after', reason: 'saving an unrelated field must succeed');
      final raw = (await tester.runAsync(() => storage.readText('user/产品列表/TypedMetadata.md')))!;
      final metadata = loadYaml(RegExp(r'^---\n([\s\S]*?)\n---').firstMatch(raw)!.group(1)!) as YamlMap;
      if (c == 0) {
        expect(metadata['measurements'], {1: 'low', 2: 'high'});
        expect(metadata['deep'], [{true: 'yesValue', null: 'nilValue'}]);
      } else if (c == 1) {
        expect(metadata[1], 'numeric'); expect(metadata[true], 'boolean');
        expect(metadata[null], 'nil'); expect(metadata['1'], 'stringNumeric');
      } else if (c == 2) {
        final numbers = metadata['numbers'] as YamlList;
        expect(numbers[0], double.infinity); expect(numbers[1], double.negativeInfinity);
        expect((numbers[2] as double).isNaN, isTrue);
      } else {
        final complex = metadata['complex'] as YamlMap;
        expect(complex.length, 2);
        expect(complex.entries.singleWhere((e) => e.key is YamlList).key, [1, 'x']);
        expect(complex.entries.singleWhere((e) => e.key is YamlList).value, 'listKey');
        expect(complex.entries.singleWhere((e) => e.key is YamlMap).key, {'a': 1});
        expect(complex.entries.singleWhere((e) => e.key is YamlMap).value, 'mapKey');
        expect(metadata.entries.singleWhere((e) => e.key is YamlList).key, ['root', 1]);
        expect(metadata.entries.singleWhere((e) => e.key is YamlList).value, 'rootList');
        expect(metadata.entries.singleWhere((e) => e.key is YamlMap).key, {'root': true});
        expect(metadata.entries.singleWhere((e) => e.key is YamlMap).value, 'rootMap');
      }
      expect(metadata['tags'], ['custom']); expect(raw, contains('body stays'));
      expect(tester.takeException(), isNull);
    });
  }
}
