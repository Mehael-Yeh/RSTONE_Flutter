import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/widgets/swipe_note_item_card.dart';
import 'package:rst_flutter/utils/natural_sort.dart';

class CountingList extends ListBase<ProductItem> {
  final List<ProductItem> values;
  int reads = 0;
  CountingList(this.values);
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  ProductItem operator [](int i) {
    reads++;
    return values[i];
  }

  @override
  void operator []=(int i, ProductItem value) =>
      throw UnsupportedError('read only');
}

class CountingProduct extends ProductItem {
  int fields = 0;
  CountingProduct(int i)
      : super(
            fileName: 'RS${900000 + i}',
            filePath: '产品列表/RS${900000 + i}.md',
            folder: '产品列表',
            rawContent: '',
            frontmatter: const {});
  @override
  Map<String, String> getTableFields() {
    fields++;
    return super.getTableFields();
  }
}

class Catalog extends ObsidianDataService {
  CountingList recipes = CountingList([]);
  int productGets = 0;
  @override
  List<ProductItem> get products {
    productGets++;
    return super.products;
  }

  @override
  List<ProductItem> get formulas => recipes;
}

List<ProductItem> products(int n) => List.generate(
    n,
    (i) => ProductItem(
        fileName: 'RS${900000 + i}',
        filePath: '产品列表/RS${900000 + i}.md',
        folder: '产品列表',
        rawContent: '',
        frontmatter: const {},
        tags: const ['水性', 'SYNTHETIC']));
List<ProductItem> formulas(int n, List<ProductItem> ps,
        {bool legacy = false}) =>
    List.generate(n, (i) {
      final grade = ps[i % ps.length].fileName;
      return ProductItem(
          fileName: 'SYNTHETIC-$i',
          filePath: '产品配方/SYNTHETIC-$i.md',
          folder: '产品配方',
          rawContent:
              '---\n关联产品: "[[$grade]]"\n---\n| 原料编号 | 投入数(g) |\n| --- | --- |\n| [[$grade]] | 100 |\n',
          frontmatter: const {},
          formulaDocument: legacy
              ? null
              : FormulaDocument.fromJson({
                  'schema': 'rstone-recipe/1',
                  'recipeId': 'SYNTHETIC-$i',
                  'title': 'SYNTHETIC',
                  'classification': 'example',
                  'ownerProduct': grade,
                  'associatedProducts': [grade],
                  'columns': ['原料编号', '投入数(g)', '百分比(%)', '供应商', '备注'],
                  'rows': [
                    ['SYNTHETIC', '100', '100', '', '']
                  ],
                  'preTable': [],
                  'content': []
                }));
    });
Future<Catalog> mount(WidgetTester tester,
    {int n = 500,
    bool legacy = false,
    List<ProductItem>? supplied,
    bool sorted = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = PreferencesService();
  await prefs.initialize();
  if (sorted) await prefs.saveProductListSort('牌号');
  final ps = supplied ?? products(n);
  final ds = Catalog();
  ds.setItemsForTesting(products: ps);
  ds.recipes = CountingList(formulas(n, ps, legacy: legacy));
  await tester.pumpWidget(MaterialApp(
      home: ProductListPage(dataService: ds, preferencesService: prefs)));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  addTearDown(ds.dispose);
  return ds;
}

void main() {
  testWidgets('ordinary upward fling has no catalog scan or page rebuild',
      (tester) async {
    final ds = await mount(tester, n: 500);
    ds.productGets = 0;
    ds.recipes.reads = 0;
    await tester.fling(find.byType(ListView), const Offset(0, -1000), 2000);
    await tester.pumpAndSettle();
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(position.pixels, greaterThan(500));
    expect(ds.productGets, 0);
    expect(ds.recipes.reads, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'horizontal swipe still opens note editor after vertical scrolling',
      (tester) async {
    await mount(tester, n: 244);
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(500);
    await tester.pumpAndSettle();
    final row = find.byType(SwipeNoteItemCard).hitTestable().first;
    await tester.drag(row, const Offset(140, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.note_alt_outlined).hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('desktop header toggles sort without reparsing comparator fields',
      (tester) async {
    final ps = List.generate(244, (i) => CountingProduct(243 - i));
    await mount(tester, n: 244, supplied: ps);
    final page = tester.widget<ProductListPage>(find.byType(ProductListPage));
    await page.preferencesService.saveProductListColumns(['牌号', '标签']);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpWidget(MaterialApp(
        home: ProductListPage(
            dataService: page.dataService,
            preferencesService: page.preferencesService)));
    await tester.pumpAndSettle();
    for (final descending in [false, true]) {
      for (final p in ps) {
        p.fields = 0;
      }
      await tester.tap(find.text('牌号'));
      await tester.pumpAndSettle();
      expect(page.preferencesService.getProductListSort(), '牌号');
      expect(page.preferencesService.getProductListSortDesc(), descending);
      expect(find.text(descending ? 'RS900243' : 'RS900000'), findsOneWidget);
      expect(ps.fold<int>(0, (sum, p) => sum + p.fields),
          lessThanOrEqualTo(244 + 40));
    }
  });
  testWidgets(
      'pull thresholds, add dialog and page reset keep original behavior',
      (tester) async {
    final ds = await mount(tester, n: 244);
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final context = state.context;
    final metrics = state.position;
    void pull(double value) {
      OverscrollNotification(
              metrics: metrics, context: context, overscroll: -value)
          .dispatch(context);
    }

    void end() {
      ScrollEndNotification(metrics: metrics, context: context)
          .dispatch(context);
    }

    pull(40);
    await tester.pumpAndSettle();
    end();
    await tester.pumpAndSettle();
    expect(find.text('新增产品信息'), findsNothing);
    pull(56);
    await tester.pumpAndSettle();
    end();
    await tester.pumpAndSettle();
    expect(find.text('新增产品信息'), findsOneWidget);
    ds.productGets = 0;
    end();
    await tester.pumpAndSettle();
    expect(ds.productGets, 0);
    await tester.tap(find.text('新增产品信息'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    pull(58);
    await tester.pumpAndSettle();
    end();
    await tester.pumpAndSettle();
    final page = tester.widget<ProductListPage>(find.byType(ProductListPage));
    await tester.pumpWidget(MaterialApp(
        home: ProductListPage(
            dataService: ds,
            preferencesService: page.preferencesService,
            pageChangeSignal: 1)));
    await tester.pumpAndSettle();
    expect(find.text('新增产品信息'), findsNothing);
  });
  testWidgets('filter and sort retain revision index and scroll offset',
      (tester) async {
    final ds = await mount(tester, n: 244);
    final index = ds.formulaAssociations;
    ds.recipes.reads = 0;
    await tester.tap(find.byTooltip('筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is CheckedPopupMenuItem<String> && widget.value == '水性'));
    await tester.pumpAndSettle();
    expect(ds.formulaAssociations, same(index));
    expect(ds.recipes.reads, 0);
    await tester.tap(find.byIcon(Icons.sort_by_alpha));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Z-A'));
    await tester.pumpAndSettle();
    expect(find.text('RS900243'), findsOneWidget);
    expect(ds.recipes.reads, 0);
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(900);
    await tester.pumpAndSettle();
    final offset = position.pixels;
    ds.revision++;
    ds.notifyListeners();
    await tester.pumpAndSettle();
    expect(position.pixels, offset);
    expect(ds.recipes.reads, 244);
  });

  for (final desktop in [false, true]) {
    for (final descending in [false, true]) {
      testWidgets(
          'equal, blank and natural keys preserve all rendered row order desktop=$desktop descending=$descending',
          (tester) async {
        final ps = List.generate(
            244,
            (i) => ProductItem(
                fileName: 'RS${900000 + i}',
                filePath: '产品列表/RS${900000 + i}.md',
                folder: '产品列表',
                rawContent: '',
                frontmatter: const {},
                engineer: ['', 'a2', 'a10', 'a02'][i % 4]));
        final expected = List<ProductItem>.from(ps);
        int compare(ProductItem a, ProductItem b) {
          final c = compareNaturalText(a.engineer ?? '', b.engineer ?? '');
          return descending ? -c : c;
        }

        expected.sort(compare);
        expected.sort(compare);
        await mount(tester, n: 244, supplied: ps);
        final page =
            tester.widget<ProductListPage>(find.byType(ProductListPage));
        await page.preferencesService.saveProductListSort('工程师');
        await page.preferencesService.saveProductListSortDesc(descending);
        await page.preferencesService.saveProductListColumns(['牌号', '标签']);
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.physicalSize =
            desktop ? const Size(1400, 900) : const Size(390, 844);
        await tester.pumpWidget(MaterialApp(
            home: ProductListPage(
                dataService: page.dataService,
                preferencesService: page.preferencesService)));
        await tester.pumpAndSettle();
        if (!desktop) {
          final titles = tester
              .widgetList<SwipeNoteItemCard>(find.byType(SwipeNoteItemCard))
              .map((w) => w.title)
              .toList();
          expect(titles,
              expected.take(titles.length).map((p) => p.fileName).toList());
        } else {
          final labels = tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .whereType<String>()
              .where((s) => s.startsWith('RS900'))
              .toList();
          expect(labels,
              expected.take(labels.length).map((p) => p.fileName).toList());
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('replacement data service owns the page subscription',
      (tester) async {
    await mount(tester, n: 244);
    final prefs = tester
        .widget<ProductListPage>(find.byType(ProductListPage))
        .preferencesService;
    final next = Catalog();
    final ps = products(244);
    next.setItemsForTesting(products: ps);
    next.recipes = CountingList(formulas(1, ps));
    await tester.pumpWidget(MaterialApp(
        home: ProductListPage(dataService: next, preferencesService: prefs)));
    await tester.pumpAndSettle();
    next.recipes = CountingList(formulas(2, [ps.first]));
    next.revision++;
    next.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('配方 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    next.dispose();
  });
  testWidgets('opening a product reuses the badge association collection',
      (tester) async {
    final ds = await mount(tester, n: 244);
    ds.recipes.reads = 0;
    await tester.tap(find.text('RS900000'));
    await tester.pumpAndSettle();
    expect(find.text('SYNTHETIC'), findsWidgets);
    expect(ds.recipes.reads, 0,
        reason:
            'detail must consume the same immutable associations as the badge');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
  });
  testWidgets('product page sorts once with one field extraction per item',
      (tester) async {
    final ps = List.generate(244, (i) => CountingProduct(243 - i));
    await mount(tester, n: 244, supplied: ps, sorted: true);
    expect(find.text('RS900000'), findsOneWidget);
    expect(ps.fold<int>(0, (n, p) => n + p.fields), lessThanOrEqualTo(244 + 40),
        reason:
            'one sort must precompute field values, not rebuild maps in comparators or sort in parent and child');
  });
  testWidgets('ordinary ScrollEnd does not rebuild product page',
      (tester) async {
    final ds = await mount(tester, n: 244);
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(ListView)));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, -70));
      await tester.pump(const Duration(milliseconds: 16));
    }
    ds.productGets = 0;
    await gesture.up();
    await tester.pumpAndSettle();
    expect(ds.productGets, 0,
        reason: 'ending a normal scroll has no page state change');
  });
  testWidgets('newly visible rows do not scan unchanged recipe data',
      (tester) async {
    final ds = await mount(tester);
    ds.recipes.reads = 0;
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(ListView)));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, -70));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final reads = ds.recipes.reads;
    await gesture.up();
    await tester.pumpAndSettle();
    expect(reads, 0,
        reason: 'continuous 0→490 scroll must reuse complete catalog index');
  });
}
