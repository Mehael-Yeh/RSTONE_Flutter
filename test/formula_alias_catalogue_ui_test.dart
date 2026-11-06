import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/pages/search_page.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';
import 'package:rst_flutter/widgets/swipe_note_item_card.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductItem _item(String folder, String name, String content) =>
    ProductItem.fromMdContent('$folder/$name.md', content);

Future<PreferencesService> _preferences() async {
  SharedPreferences.setMockInitialValues({});
  final preferences = PreferencesService();
  await preferences.initialize();
  await preferences.saveProductListColumns(['牌号', '标签']);
  return preferences;
}

ObsidianDataService _service({bool independent = true}) => ObsidianDataService()
  ..setItemsForTesting(products: [
    _item(
        '产品列表', 'RS990001-2B', '---\ntags:\n  - 水性\n实验牌号: RD990002-2B\n---\n'),
    if (independent) _item('产品列表', 'RD990002-2B', '---\ntags:\n  - 油性\n---\n'),
  ], formulas: [
    _item(
        '产品配方', 'synthetic-independent', '---\n关联产品: "[[RD990002-2B]]"\n---\n'),
  ]);

void _size(WidgetTester tester, bool mobile) {
  tester.view.physicalSize =
      mobile ? const Size(390, 900) : const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _filteredList(WidgetTester tester,
    {bool independent = true}) async {
  await tester.pumpWidget(MaterialApp(
    home: ProductListPage(
      dataService: _service(independent: independent),
      preferencesService: await _preferences(),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.filter_alt_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.byWidgetPredicate((widget) =>
      widget is CheckedPopupMenuItem<String> && widget.value == '水性'));
  await tester.pumpAndSettle();
  expect(find.text('RD990002-2B'), findsNothing);
  expect(find.text('RS990001-2B'), findsOneWidget);
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.close).last);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  for (final mobile in [true, false]) {
    final layout = mobile ? 'mobile' : 'desktop';
    testWidgets('$layout filtered badge reserves the hidden canonical identity',
        (tester) async {
      _size(tester, mobile);
      await _filteredList(tester);
      expect(find.byKey(const ValueKey('formula-badge:RS990001-2B')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$layout filtered row detail rejects a stolen alias formula',
        (tester) async {
      _size(tester, mobile);
      await _filteredList(tester);
      await tester.tap(find.text('RS990001-2B'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductDetailSheet), findsOneWidget);
      try {
        expect(find.text('配方：synthetic-independent'), findsNothing);
      } finally {
        await _close(tester);
      }
    });

    testWidgets('$layout preserves historical alias without a canonical owner',
        (tester) async {
      _size(tester, mobile);
      await _filteredList(tester, independent: false);
      final badge = find.byKey(const ValueKey('formula-badge:RS990001-2B'));
      expect(badge, findsOneWidget);
      expect(find.text('配方 1'), findsOneWidget);
      await tester.tap(badge);
      await tester.pumpAndSettle();
      expect(find.text('配方：synthetic-independent'), findsOneWidget);
      await _close(tester);
    });
  }

  for (final id in ['RS990001-2B', 'RD990002-2B']) {
    testWidgets('search detail uses the full product catalogue for $id',
        (tester) async {
      _size(tester, true);
      await tester.pumpWidget(MaterialApp(
        home: SearchPage(
          dataService: _service(),
          preferencesService: await _preferences(),
          onThemeModeChanged: (_) async {},
          themeSeedColor: Colors.blue,
          onThemeSeedColorChanged: (_) async {},
          themeMode: ThemeMode.system,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), id);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byWidgetPredicate(
              (w) => w is SwipeNoteItemCard && w.title == id),
          matching: find.text(id)));
      await tester.pumpAndSettle();
      expect(find.byType(ProductDetailSheet), findsOneWidget);
      try {
        expect(find.text('配方：synthetic-independent'),
            id.startsWith('RD') ? findsOneWidget : findsNothing);
      } finally {
        await _close(tester);
      }
    });
  }
}
