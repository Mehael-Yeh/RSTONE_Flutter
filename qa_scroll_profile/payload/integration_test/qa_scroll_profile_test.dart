// QA ONLY. Synthetic catalog; no app bootstrap, network sync, or production store.
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';
import 'package:rst_flutter/services/preferences_service.dart';

List<ProductItem> products(int n) => List.generate(n, (i) => ProductItem(
  fileName: 'RS${900000+i}', filePath: '产品列表/RS${900000+i}.md',
  folder: '产品列表', rawContent: '', frontmatter: const {},
  tags: const ['水性', 'PU', 'SYNTHETIC']));
List<ProductItem> formulas(List<ProductItem> ps) => List.generate(ps.length, (i) {
  final grade = ps[i].fileName;
  return ProductItem(fileName: 'SYNTHETIC-$i', filePath: '产品配方/SYNTHETIC-$i.md',
    folder: '产品配方', rawContent: '', frontmatter: const {},
    formulaDocument: FormulaDocument.fromJson({
      'schema': 'rstone-recipe/1', 'recipeId': 'SYNTHETIC-$i',
      'title': 'SYNTHETIC', 'classification': 'example',
      'ownerProduct': grade, 'associatedProducts': [grade],
      'columns': ['原料编号', '投入数(g)', '百分比(%)', '供应商', '备注'],
      'rows': [['SYNTHETIC', '100', '100', '', '']], 'preTable': [], 'content': [],
    }));
});

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('QA AOT profile real product list synthetic scroll', (tester) async {
    if (!kProfileMode) throw UnsupportedError('AOT profile required; no debug fallback');
    const source = String.fromEnvironment('QA_SOURCE_SHA');
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(source)) throw StateError('Exact source SHA required');
    final font = FontLoader('QA_YaHei')..addFont(rootBundle.load('assets/fonts/MicrosoftYaHei.ttf'));
    await font.load();
    final view = tester.view;
    final hz = view.display.refreshRate;
    if (!hz.isFinite || hz <= 0) throw UnsupportedError('Actual display refresh unavailable');
    if (view.physicalSize.width / view.devicePixelRatio >= 600) throw StateError('Mobile view required');
    final allTimings = <FrameTiming>[];
    void collect(List<FrameTiming> frames) => allTimings.addAll(frames);
    SchedulerBinding.instance.addTimingsCallback(collect);
    addTearDown(() => SchedulerBinding.instance.removeTimingsCallback(collect));
    final cases = <Map<String, dynamic>>[];
    for (final n in [244, 500]) {
      for (final sorted in [false, true]) {
        // Dart in-memory preferences only: do not initialize app/data sync.
        SharedPreferences.setMockInitialValues({});
        final prefs = PreferencesService(); await prefs.initialize();
        await prefs.saveProductListColumns(['牌号', '标签']);
        await prefs.saveProductListSort(sorted ? '牌号' : null);
        final ps = products(n);
        final service = ObsidianDataService()..setItemsForTesting(products: ps, formulas: formulas(ps));
        var ends = 0;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(fontFamily: 'QA_YaHei'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling), child: child!),
          home: NotificationListener<ScrollEndNotification>(
            onNotification: (_) { ends++; return false; },
            child: ProductListPage(dataService: service, preferencesService: prefs))));
        await tester.pumpAndSettle();
        expect(find.byType(ProductListPage), findsOneWidget);
        final list = find.byType(ListView).first;
        final scroll = find.descendant(of: list, matching: find.byType(Scrollable)).first;
        final position = tester.state<ScrollableState>(scroll).position;
        if (position.maxScrollExtent < 2000) throw StateError('Fixture did not produce enough real rows');
        Future<void> sequence() async {
          await tester.timedDrag(list, const Offset(0, -560), const Duration(milliseconds: 800), frequency: 60);
          await tester.pumpAndSettle();
          await tester.timedDrag(list, const Offset(0, 560), const Duration(milliseconds: 800), frequency: 60);
          await tester.pumpAndSettle();
        }
        // Each warmup and measured repetition starts at the same non-edge position.
        for (var i = 0; i < 2; i++) {
          position.jumpTo(1000); await tester.pumpAndSettle(); await sequence();
        }
        final samples = <Map<String, dynamic>>[];
        for (var repeat = 0; repeat < 3; repeat++) {
          position.jumpTo(1000); await tester.pumpAndSettle();
          // Real wall-clock waits only drain batched engine callbacks; never fake CPU work.
          await Future<void>.delayed(const Duration(milliseconds: 500));
          allTimings.clear(); ends = 0;
          final start = developer.Timeline.now;
          await sequence();
          final end = developer.Timeline.now;
          await Future<void>.delayed(const Duration(milliseconds: 500));
          final frames = allTimings.where((f) {
            final t = f.timestampInMicroseconds(FramePhase.buildStart);
            return t >= start && t <= end;
          }).map((f) => <String, dynamic>{
            'frame': f.frameNumber,
            'build_us': f.buildDuration.inMicroseconds,
            'raster_us': f.rasterDuration.inMicroseconds,
            'total_us': f.totalSpan.inMicroseconds,
            'build_start_us': f.timestampInMicroseconds(FramePhase.buildStart),
          }).toList();
          if (frames.isEmpty) throw UnsupportedError('No actual FrameTiming from AOT engine');
          if (ends < 2) throw StateError('ScrollEnd not observed twice');
          samples.add({'repeat': repeat, 'start_us': start, 'end_us': end,
            'scroll_ends': ends, 'frames': frames});
        }
        cases.add({'products': n, 'formulas': n, 'sorted': sorted, 'samples': samples});
        await tester.pumpWidget(const SizedBox.shrink()); await tester.pumpAndSettle();
        service.dispose();
        expect(tester.takeException(), isNull);
      }
    }
    binding.reportData = {'scroll_profile': {
      'schema': 1, 'mode': kProfileMode ? 'profile' : 'unsupported',
      'source_sha': source, 'edition': 'full', 'warmups': 2, 'repeats': 3,
      'view': {'physical_width': view.physicalSize.width, 'physical_height': view.physicalSize.height,
        'dpr': view.devicePixelRatio, 'refresh_hz': hz, 'text_scale': 1.0, 'font': 'QA_YaHei'},
      'budget_us': (1000000 / hz).round(),
      'gesture': {'dy': -560, 'duration_ms': 800, 'frequency_hz': 60, 'start_offset': 1000},
      'cases': cases,
    }};
  }, timeout: const Timeout(Duration(minutes: 8)));
}
