import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'package:rst_flutter/widgets/obsidian_table.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductItem _product(String grade, {String? status}) {
  final frontmatter = status == null
      ? '---\ntags:\n  - 水性\n---\n'
      : '---\ntags:\n  - 水性\n产品状态: $status\n---\n';
  return ProductItem.fromMdContent('产品列表/$grade.md', frontmatter,
      origin: DataOrigin.official);
}

Future<void> _pumpTable(
  WidgetTester tester, {
  required bool isMobile,
  required List<ProductItem> items,
  String? sortColumn,
}) async {
  tester.view.physicalSize =
      isMobile ? const Size(320, 800) : const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = PreferencesService();
  await prefs.initialize();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ObsidianTable(
        items: items,
        formulas: const [],
        tdsByProduct: const {},
        defaultColumns: const ['牌号', '标签'],
        availableColumns: const ['牌号', '标签'],
        isMobile: isMobile,
        onColumnsChanged: (_) {},
        onSortChanged: (_) {},
        onSortDirectionChanged: (_) {},
        preferencesService: prefs,
        currentSortColumn: sortColumn,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

TextDecoration? _decorationOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.decoration;

void main() {
  final items = [
    _product('RS92001', status: '停用'),
    _product('RS92002'),
    _product('RS92003', status: '不推广'),
  ];

  testWidgets('mobile cards strike discontinued grades and show status',
      (tester) async {
    await _pumpTable(tester, isMobile: true, items: items);

    expect(_decorationOf(tester, 'RS92001'), TextDecoration.lineThrough);
    expect(_decorationOf(tester, 'RS92002'), isNot(TextDecoration.lineThrough));
    expect(_decorationOf(tester, 'RS92003'), isNot(TextDecoration.lineThrough));
    expect(find.text('停用'), findsOneWidget);
    expect(find.text('不推广'), findsOneWidget);
  });

  testWidgets('desktop rows strike discontinued grades and show status',
      (tester) async {
    await _pumpTable(tester, isMobile: false, items: items);

    expect(_decorationOf(tester, 'RS92001'), TextDecoration.lineThrough);
    expect(_decorationOf(tester, 'RS92002'), isNot(TextDecoration.lineThrough));
    expect(_decorationOf(tester, 'RS92003'), isNot(TextDecoration.lineThrough));
    expect(find.text('停用'), findsOneWidget);
    expect(find.text('不推广'), findsOneWidget);
  });

  testWidgets('desktop natural sort order is unchanged by lifecycle status',
      (tester) async {
    final sortable = [
      _product('RS9210', status: '停用'),
      _product('RS921'),
      _product('RS9211'),
    ];
    await _pumpTable(tester,
        isMobile: false, items: sortable, sortColumn: '牌号');

    final grades = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .where((data) => data != null && data.startsWith('RS92'))
        .toList();
    expect(grades, ['RS921', 'RS9210', 'RS9211']);
  });
}
