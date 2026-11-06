// Only synthetic fixtures; never load the business catalog.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/main.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/pages/product_applications_page.dart';
import 'package:rst_flutter/pages/search_page.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'package:rst_flutter/utils/app_shapes.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';

Finder decoratedLabel(String label) => find.ancestor(
  of: find.text(label), matching: find.byWidgetPredicate(
    (w) => w is Container && w.decoration is BoxDecoration)).first;

void checkLabel(WidgetTester tester, String label) {
  final finder = decoratedLabel(label);
  final box = tester.widget<Container>(finder).decoration! as BoxDecoration;
  expect(box.borderRadius, AppShapes.borderRadius, reason: label);
  final rect = tester.getRect(finder);
  expect(rect.shortestSide, greaterThanOrEqualTo(AppShapes.radius * 2));
  final actual = (box.borderRadius! as BorderRadius).toRRect(rect).scaleRadii();
  expect(actual.tlRadiusX, AppShapes.radius, reason: 'real geometry must not clamp: $label');
}

Future<void> capture(WidgetTester tester, String name) async {
  final out = Platform.environment['RECIPE_TEST_OUT'];
  if (out == null) return;
  await tester.runAsync(() async {
    final image = await tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('shape-capture'))).toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [360.0, 1200.0]) {
      testWidgets('labels agree across real entries $brightness $width', (tester) async {
        await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/MicrosoftYaHei.ttf'))).load();
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final prefs = PreferencesService();
        await prefs.initialize();
        await prefs.saveProductListColumns(['牌号', '标签']);
        await prefs.saveApplicationColumns(['名称', '标签']);
        final product = ProductItem.fromMdContent('产品列表/RS990001.md',
          '---\ntags: [Synthetic]\n实验牌号: RD990002\n产品状态: 停用\n---\nSynthetic body');
        final application = ProductItem.fromMdContent('产品应用/SyntheticApplication.md',
          '---\ntags: [SyntheticAppTag]\n底漆: SyntheticPrimer\n---\nSynthetic application');
        final data = ObsidianDataService()..setItemsForTesting(products: [product], applications: [application]);
        await tester.pumpWidget(RstoneApp(dataService: data, preferencesService: prefs));
        final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        final theme = brightness == Brightness.light ? app.theme! : app.darkTheme!;
        Future<void> open(Widget child) async {
          await tester.pumpWidget(MaterialApp(theme: theme, home: RepaintBoundary(
            key: const ValueKey('shape-capture'), child: child)));
          await tester.pumpAndSettle();
        }
        final suffix = '${brightness.name}-${width.toInt()}';
        await open(ProductListPage(dataService: data, preferencesService: prefs));
        if (width < 600) checkLabel(tester, 'Synthetic');
        checkLabel(tester, '停用');
        await capture(tester, 'product-$suffix');
        await open(ProductApplicationsPage(dataService: data, preferencesService: prefs));
        if (width < 600) checkLabel(tester, '底: SyntheticPrimer');
        await capture(tester, 'application-$suffix');
        await open(SearchPage(dataService: data, preferencesService: prefs,
          onThemeModeChanged: (_) async {}, themeSeedColor: Colors.blue,
          onThemeSeedColorChanged: (_) async {}, themeMode: ThemeMode.system));
        await tester.enterText(find.byType(TextField), 'RD990002');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        checkLabel(tester, 'Synthetic');
        checkLabel(tester, 'RD990002');
        await capture(tester, 'search-$suffix');
        await open(Scaffold(body: ProductDetailSheet(product: product, productCatalog: [product])));
        checkLabel(tester, 'Synthetic');
        checkLabel(tester, '产品列表');
        await capture(tester, 'detail-$suffix');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        data.dispose();
      });
    }
  }
}
