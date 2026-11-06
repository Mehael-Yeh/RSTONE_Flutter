// Synthetic 900000+ identifiers; the model owns scalar alias semantics.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/pages/search_page.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';
import 'package:rst_flutter/widgets/swipe_note_item_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductItem item(String name, String alias, {String folder = '产品列表'}) =>
    ProductItem.fromMdContent('$folder/$name.md', '---\n实验牌号: $alias\n---\n');
Future<void> search(
    WidgetTester tester, List<ProductItem> products, String query) async {
  await (FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/MicrosoftYaHei.ttf')))
      .load();
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
  SharedPreferences.setMockInitialValues({});
  final prefs = PreferencesService();
  await prefs.initialize();
  final service = ObsidianDataService()..setItemsForTesting(products: products);
  await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
          key: const ValueKey('identity-capture'),
          child: SearchPage(
              dataService: service,
              preferencesService: prefs,
              onThemeModeChanged: (_) async {},
              themeSeedColor: Colors.blue,
              onThemeSeedColorChanged: (_) async {},
              themeMode: ThemeMode.system))));
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 412.0, 1200.0]) {
    testWidgets(
        'alias query shows adjacent same-line capsule and opens same identity at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = item('RS900001-9', '"RD900002-9"');
      await search(tester, [p], 'RD900002-9');
      final card = find.byType(SwipeNoteItemCard);
      expect(card, findsOneWidget);
      final title =
          find.descendant(of: card, matching: find.text('RS900001-9'));
      final alias =
          find.descendant(of: card, matching: find.text('RD900002-9'));
      expect(alias, findsOneWidget);
      final a = tester.getRect(alias), t = tester.getRect(title);
      debugPrint(
          'IDENTITY_GEOMETRY width=$width title=$t alias=$a gap=${a.left - t.right}');
      expect(a.center.dy, closeTo(t.center.dy, .5));
      expect(a.left - t.right, inInclusiveRange(4, 12));
      expect(a.right, lessThan(width));
      expect(find.text('量产'), findsNothing);
      if (Platform.environment['RECIPE_TEST_OUT'] case final String out) {
        await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('identity-capture')))
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/search-$width.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(alias);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<ProductDetailSheet>(find.byType(ProductDetailSheet))
              .product,
          same(p));
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'empty self RD and unknown-folder identities do not fabricate capsules',
      (tester) async {
    await search(
        tester,
        [
          item('RS900010', ''),
          item('RS900011', 'RS900011'),
          item('RD900012', 'RD900013'),
          item('900014', 'RD900015', folder: 'unknown')
        ],
        '9000');
    expect(find.byKey(const ValueKey('experimental-alias:RS900010')),
        findsNothing);
    expect(find.byKey(const ValueKey('experimental-alias:RS900011')),
        findsNothing);
    expect(find.byKey(const ValueKey('experimental-alias:RD900012')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('experimental-alias:900014')), findsNothing);
    expect(find.text('RD900013'), findsNothing);
    expect(find.text('RD900015'), findsNothing);
  });
  testWidgets(
      'multiple-looking scalar stays one declared scalar without invented split identities',
      (tester) async {
    final p = item('RS900020', '"RD900021, RD900022"');
    await search(tester, [p], 'RD900022');
    expect(find.text(p.experimentalCode!), findsOneWidget);
    expect(find.text('RD900021'), findsNothing);
    expect(
        find.descendant(
            of: find.byType(SwipeNoteItemCard),
            matching: find.text('RD900022')),
        findsNothing);
    expect(find.byKey(const ValueKey('experimental-alias:RS900020')),
        findsOneWidget);
  });
}
