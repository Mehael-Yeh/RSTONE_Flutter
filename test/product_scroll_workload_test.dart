// Synthetic workload only; counts source reads, never frame-rate claims.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'product_scroll_regression_test.dart' as fixture;

void main() {
  testWidgets('seven synthetic full-page workload scenarios', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final results = <Map<String, dynamic>>[];
    for (final scenario in [
      (244, 0, false, false, true),
      (244, 244, false, false, true),
      (500, 0, false, false, true),
      (500, 500, false, false, true),
      (244, 244, false, true, true),
      (244, 244, true, false, true),
      (244, 244, false, false, false),
    ]) {
      final (n, f, legacy, sorted, mobile) = scenario;
      tester.view.physicalSize =
          mobile ? const Size(390, 844) : const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService();
      await prefs.initialize();
      if (!mobile) await prefs.saveProductListColumns(['牌号', '标签']);
      if (sorted) await prefs.saveProductListSort('牌号');
      final ps = List.generate(n, (i) => fixture.CountingProduct(i));
      final ds = fixture.Catalog();
      ds.setItemsForTesting(products: ps);
      ds.recipes =
          fixture.CountingList(fixture.formulas(f, ps, legacy: legacy));
      Map<String, int> take() {
        final c = {
          'formulaReads': ds.recipes.reads,
          'productGetterCalls': ds.productGets,
          'tableFieldExtractions': ps.fold<int>(0, (s, p) => s + p.fields)
        };
        ds.recipes.reads = 0;
        ds.productGets = 0;
        for (final p in ps) {
          p.fields = 0;
        }
        return c;
      }

      await tester.pumpWidget(MaterialApp(
          home: ProductListPage(dataService: ds, preferencesService: prefs)));
      await tester.pumpAndSettle();
      final initial = take();
      final pos =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(ListView)));
      final frames = <Map<String, dynamic>>[];
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -70));
        await tester.pump(const Duration(milliseconds: 16));
        frames.add({'offset': pos.pixels, 'counts': take()});
      }
      await gesture.up();
      await tester.pumpAndSettle();
      final end = take();
      pos.jumpTo(2000);
      await tester.pumpAndSettle();
      final far = take();
      pos.jumpTo(0);
      await tester.pumpAndSettle();
      final back = take();
      results.add({
        'products': n,
        'formulas': f,
        'legacy': legacy,
        'sorted': sorted,
        'mobile': mobile,
        'initial': initial,
        'continuous': frames,
        'gestureEnd': end,
        'jump2000': far,
        'return0': back
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      ds.dispose();
      expect(tester.takeException(), isNull);
    }
    final baseline = Platform.environment['OWN_APP'] == 'baseline-client';
    File('../MEASUREMENTS-${baseline ? 'before' : 'after'}.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    if (!baseline) {
      for (final result in results) {
        expect((result['initial'] as Map)['formulaReads'], result['formulas']);
        for (final frame in result['continuous'] as List) {
          expect(frame['counts']['formulaReads'], 0);
        }
        expect(result['gestureEnd']['productGetterCalls'], 0);
        expect(result['gestureEnd']['formulaReads'], 0);
        expect(result['jump2000']['formulaReads'], 0);
        expect(result['return0']['formulaReads'], 0);
      }
    }
  });
}
