// Synthetic identities only; display changes must not alter model identity.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';

ProductItem product(String name, String alias) => ProductItem.fromMdContent(
    '产品列表/$name.md', '---\n实验牌号: $alias\n固含: 50%\n---\n');

Future<void> open(WidgetTester tester, ProductItem item) async {
  await (FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/MicrosoftYaHei.ttf')))
      .load();
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
  await tester.pumpWidget(MaterialApp(
      builder: (context, child) =>
          RepaintBoundary(key: const ValueKey('detail-capture'), child: child!),
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => ProductDetailSheet.show(context, item,
                      productCatalog: [item]),
                  child: const Text('open'))))));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String label) async {
  if (Platform.environment['RECIPE_TEST_OUT'] case final String out) {
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('detail-capture')))
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$label.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }
}

void main() {
  for (final origin in [DataOrigin.user, DataOrigin.official]) {
    for (final folder in ['产品列表', '产品应用']) {
      testWidgets('$folder detail category has no source suffix for $origin',
          (tester) async {
        final p = ProductItem.fromMdContent('$folder/Synthetic900001.md', '',
            origin: origin);
        await open(tester, p);
        expect(find.text(folder), findsOneWidget);
        expect(find.text('$folder · 个人'), findsNothing);
        expect(find.text('$folder · 官方'), findsNothing);
        expect(
            tester
                .widget<ProductDetailSheet>(find.byType(ProductDetailSheet))
                .product
                .origin,
            origin);
        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();
      });
    }
  }
  for (final width in [360.0, 412.0, 1200.0]) {
    for (final rd in [true, false]) {
      testWidgets(
          '${rd ? 'RD omits' : 'RS retains'} explicit experimental alias at $width',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final p = product('${rd ? 'RD' : 'RS'}900001-9', '"RD900002-9"');
        final original = p.experimentalCode;
        await open(tester, p);
        expect(find.text('实验牌号'), rd ? findsNothing : findsOneWidget);
        expect(find.text('RD900002-9'), rd ? findsNothing : findsOneWidget);
        expect(find.text('50%'), findsOneWidget);
        expect(find.text('量产'), findsNothing);
        expect(p.experimentalCode, original);
        await capture(tester, 'detail-${p.fileName}-$width');
        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();
      });
    }
  }
}
