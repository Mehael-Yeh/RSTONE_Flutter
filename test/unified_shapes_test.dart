import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/utils/app_shapes.dart';
import 'package:rst_flutter/widgets/compact_token_row.dart';
import 'package:rst_flutter/widgets/swipe_note_item_card.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('compact and status labels share unclamped corners $brightness',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: RepaintBoundary(key: const ValueKey('pixels'), child: Scaffold(body: Column(children: [
          const CompactTokenRow(tokens: ['Synthetic']),
          SwipeNoteItemCard(title: 'Synthetic item', subtitleTokens: const ['Test'],
            indicatorColor: Colors.green, onTap: () {}, onNoteTap: () async {},
            noteResetSignal: 0, statusLabel: 'Draft'),
        ]))),
      ));
      for (final label in ['Synthetic', 'Test', 'Draft']) {
        final container = find.ancestor(of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration)).first;
        final box = tester.widget<Container>(container).decoration! as BoxDecoration;
        expect(box.borderRadius, AppShapes.borderRadius, reason: label);
        final rect = tester.getRect(container);
        expect(rect.shortestSide, greaterThanOrEqualTo(4), reason: 'radius must not clamp');
      }
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image = await tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('pixels'))).toImage();
        final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
        final box = find.ancestor(of: find.text('Synthetic'), matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration)).first;
        final rect = tester.getRect(box);
        List<int> pixel(int x, int y) => raw.sublist((y * image.width + x) * 4, (y * image.width + x) * 4 + 4);
        final corner = pixel(rect.left.toInt(), rect.top.toInt());
        final edge = pixel(rect.center.dx.toInt(), rect.top.toInt());
        expect(corner, isNot(edge), reason: 'real rounded corner must differ from the straight top edge');
        if (Platform.environment['RECIPE_TEST_OUT'] case final String out) {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/tag-pixels-${brightness.name}.png').writeAsBytesSync(png!.buffer.asUint8List());
          File('$out/tag-pixels-${brightness.name}.json').writeAsStringSync(jsonEncode({'corner': corner, 'topEdge': edge, 'width': rect.width, 'height': rect.height, 'radius': AppShapes.radius}));
        }
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    });
  }
}
