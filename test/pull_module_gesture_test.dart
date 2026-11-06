// Synthetic catalog; real scroll gestures and Navigator route pops.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/main.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';

class GestureCatalog extends ObsidianDataService {
  int generation = 0;
  int applicationReads = 0;
  @override
  List<ProductItem> get applications {
    applicationReads++;
    return super.applications;
  }

  @override
  int get revision => generation;
  void clearCatalog() {
    setItemsForTesting(products: [], applications: []);
    generation++;
    notifyListeners();
  }
}

Future<GestureCatalog> mount(WidgetTester t, {int count = 40}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = PreferencesService();
  await prefs.initialize();
  final ds = GestureCatalog();
  ProductItem item(String folder, int i) => ProductItem(
      fileName: 'SYNTHETIC-$i',
      filePath: '$folder/SYNTHETIC-$i.md',
      folder: folder,
      rawContent: '',
      frontmatter: const {});
  ds.setItemsForTesting(
      products: List.generate(count, (i) => item('产品列表', i)),
      applications: List.generate(count, (i) => item('产品应用', i)));
  addTearDown(ds.dispose);
  await t.pumpWidget(RstoneApp(dataService: ds, preferencesService: prefs));
  await t.pumpAndSettle();
  return ds;
}

Future<void> pull(WidgetTester t) async {
  await t.drag(find.byType(ListView).hitTestable().first, const Offset(0, 150));
  await t.pumpAndSettle();
}

Future<void> back(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

void main() {
  testWidgets('application unchanged ScrollEnd does not rebuild expanded page',
      (t) async {
    final ds = await mount(t);
    await t.tap(find.byTooltip('产品应用'));
    await t.pumpAndSettle();
    await pull(t);
    final state =
        t.state<ScrollableState>(find.byType(Scrollable).hitTestable().first);
    ds.applicationReads = 0;
    ScrollEndNotification(metrics: state.position, context: state.context)
        .dispatch(state.context);
    await t.pumpAndSettle();
    expect(ds.applicationReads, 0);
    expect(find.text('新增产品应用').hitTestable(), findsOneWidget);
  });
  testWidgets('formula modal back leaves both add modules expanded', (t) async {
    await mount(t);
    await t.tap(find.byTooltip('产品应用'));
    await t.pumpAndSettle();
    await pull(t);
    await t.tap(find.text('新增产品配方').hitTestable());
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await back(t);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('新增产品配方').hitTestable(), findsOneWidget);
    expect(find.text('新增产品应用').hitTestable(), findsOneWidget);
    await back(t);
    expect(find.text('新增产品配方'), findsNothing);
    expect(find.text('新增产品应用'), findsNothing);
    expect(t.takeException(), isNull);
  });
  for (final tab in ['产品列表', '产品应用']) {
    final button = tab == '产品列表' ? '新增产品信息' : '新增产品应用';
    testWidgets('$tab taps and modal back preserve expanded module', (t) async {
      await mount(t);
      await t.tap(find.byTooltip(tab));
      await t.pumpAndSettle();
      await pull(t);
      expect(find.text(button).hitTestable(), findsOneWidget);
      await t.tap(find.text('SYNTHETIC-0').hitTestable().first);
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await back(t);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text(button).hitTestable(), findsOneWidget);
      await t.tapAt(Offset(2, t.getCenter(find.text(button).hitTestable()).dy));
      await t.pumpAndSettle();
      expect(find.text(button).hitTestable(), findsOneWidget);
      await t.tap(find.text(button).hitTestable());
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await back(t);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(button).hitTestable(), findsOneWidget);
      await back(t);
      expect(find.text(button), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      await pull(t);
      await t.drag(
          find.byType(ListView).hitTestable().first, const Offset(0, -100));
      await t.pumpAndSettle();
      expect(find.text(button), findsNothing);
      expect(t.takeException(), isNull);
    });
    testWidgets('$tab real persisted save retains expanded module', (t) async {
      await mount(t);
      final app = t.widget<RstoneApp>(find.byType(RstoneApp));
      final ds = (await t.runAsync(() async {
        final fixture = SignedFixture();
        await fixture.initialize();
        final service = await fixture.app(await fixture.memoryStorage());
        await fixture.publish(1, {
          '产品列表/SYNTHETIC-SEED.md': '---\ntags: []\n---\n',
          '产品应用/SYNTHETIC-SEED.md': '---\ntags: []\n---\n',
        });
        expect(await service.sync!.synchronize(), isTrue);
        return service;
      }))!;
      addTearDown(ds.dispose);
      await t.pumpWidget(RstoneApp(
          dataService: ds, preferencesService: app.preferencesService));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip(tab));
      await t.pumpAndSettle();
      await pull(t);
      await t.tap(find.text(button).hitTestable());
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'SYNTHETIC-SAVED');
      await t.runAsync(() async {
        await t.tap(find.text('保存').hitTestable());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final saved = tab == '产品列表' ? ds.products : ds.applications;
      expect(saved.any((item) => item.fileName == 'SYNTHETIC-SAVED'), isTrue);
      expect(find.text(button).hitTestable(), findsOneWidget);
      await back(t);
      expect(find.text(button), findsNothing);
      expect(t.takeException(), isNull);
    });
    testWidgets('$tab module upward swipe closes, horizontal does not',
        (t) async {
      await mount(t);
      await t.tap(find.byTooltip(tab));
      await t.pumpAndSettle();
      await pull(t);
      await t.drag(find.text(button).hitTestable(), const Offset(90, 0));
      await t.pumpAndSettle();
      expect(find.text(button).hitTestable(), findsOneWidget);
      await t.drag(find.text(button).hitTestable(), const Offset(0, -45));
      await t.pumpAndSettle();
      expect(find.text(button), findsNothing);
    });
    testWidgets('$tab short list upward overscroll closes module', (t) async {
      await mount(t, count: 1);
      await t.tap(find.byTooltip(tab));
      await t.pumpAndSettle();
      await pull(t);
      expect(find.text(button).hitTestable(), findsOneWidget);
      await t.drag(
          find.byType(ListView).hitTestable().first, const Offset(0, -100));
      await t.pumpAndSettle();
      expect(find.text(button), findsNothing);
    });
    testWidgets('$tab clear removes invisible back interception', (t) async {
      final ds = await mount(t);
      await t.tap(find.byTooltip(tab));
      await t.pumpAndSettle();
      await pull(t);
      ds.clearCatalog();
      await t.pumpAndSettle();
      final scopes =
          t.widgetList<PopScope<Object?>>(find.byType(PopScope<Object?>));
      expect(scopes.every((scope) => scope.canPop), isTrue);
    });
    testWidgets(
        '$tab service replacement rebinds lifecycle with equal revision',
        (t) async {
      final old = await mount(t);
      await t.tap(find.byTooltip(tab));
      await t.pumpAndSettle();
      await pull(t);
      final replacement = GestureCatalog();
      replacement.setItemsForTesting(
          products: old.products, applications: old.applications);
      addTearDown(replacement.dispose);
      final app = t.widget<RstoneApp>(find.byType(RstoneApp));
      await t.pumpWidget(RstoneApp(
          dataService: replacement,
          preferencesService: app.preferencesService));
      await t.pumpAndSettle();
      expect(find.text(button), findsNothing);
      await pull(t);
      old.clearCatalog();
      await t.pumpAndSettle();
      expect(find.text(button).hitTestable(), findsOneWidget);
      replacement.clearCatalog();
      await t.pumpAndSettle();
      expect(
          t
              .widgetList<PopScope<Object?>>(find.byType(PopScope<Object?>))
              .every((scope) => scope.canPop),
          isTrue);
      expect(t.takeException(), isNull);
    });
    testWidgets('$tab focus cancel and stacked modal back preserve module',
        (t) async {
      await mount(t);
      await t.tap(find.byTooltip(tab));
      await t.pumpAndSettle();
      await pull(t);
      await t.tap(find.text(button).hitTestable());
      await t.pumpAndSettle();
      await t.tap(find.byType(TextField).first);
      await t.enterText(find.byType(TextField).first, 'SYNTHETIC-NEW');
      await t.pumpAndSettle();
      final context = t.element(find.byType(AlertDialog));
      showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('SYNTHETIC-TOP')));
      await t.pumpAndSettle();
      await back(t);
      expect(find.text('SYNTHETIC-TOP'), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.text('取消').hitTestable());
      await t.pumpAndSettle();
      expect(find.text(button).hitTestable(), findsOneWidget);
      await back(t);
      expect(find.text(button), findsNothing);
      await pull(t);
      await t.tap(find.byTooltip('搜索'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip(tab));
      await t.pumpAndSettle();
      expect(find.text(button), findsNothing);
    });
  }
}
