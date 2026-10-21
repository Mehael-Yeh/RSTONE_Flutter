import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/main.dart';
import 'package:rst_flutter/data_sync/storage/storage_adapter.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'open detail closes once and search refreshes after official deletion',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'RSTONE',
        packageName: 'com.rstone.test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
    final prefs = PreferencesService();
    await prefs.initialize();
    final f = SignedFixture();
    late StorageAdapter store;
    late ObsidianDataService app;
    await tester.runAsync(() async {
      await f.initialize();
      store = await f.memoryStorage();
      app = await f.app(store);
      await f.publish(
          1, {'产品列表/RS1.md': product('水性'), '产品列表/RS2.md': product('UV')});
      expect(await app.sync!.synchronize(), isTrue);
      await app.sync!.setAutoUpdate(false);
    });
    await tester
        .pumpWidget(RstoneApp(dataService: app, preferencesService: prefs));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '水性');
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('RS1'), findsOneWidget);
    await tester.tap(find.text('RS1'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductDetailSheet), findsOneWidget);
    await tester.runAsync(() async {
      await f.publish(2, {'产品列表/RS2.md': product('UV')});
      expect(await app.sync!.synchronize(), isTrue);
    });
    await tester.pumpAndSettle();
    expect(find.byType(ProductDetailSheet), findsNothing);
    expect(find.text('RS1'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    expect(find.text('RS2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
    await store.close();
  }, timeout: const Timeout(Duration(seconds: 45)));
}
