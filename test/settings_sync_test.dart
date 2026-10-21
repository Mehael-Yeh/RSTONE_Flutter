import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/main.dart';
import 'package:rst_flutter/data_sync/storage/storage_adapter.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SignedFixture fixture;
  late StorageAdapter store;
  late ObsidianDataService app;
  late PreferencesService prefs;

  Future<void> openSettings(WidgetTester tester, {double width = 360}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'RSTONE',
        packageName: 'com.rstone.test',
        version: '2.0.0',
        buildNumber: '1',
        buildSignature: '');
    prefs = PreferencesService();
    await prefs.initialize();
    fixture = SignedFixture();
    await tester.runAsync(() async {
      await fixture.initialize();
      store = await fixture.memoryStorage();
      app = await fixture.app(store);
      await fixture.publish(1, {'产品列表/RS1.md': product('水性')});
      expect(await app.sync!.synchronize(), isTrue);
      await app.sync!.setAutoUpdate(false);
    });
    addTearDown(() async {
      app.dispose();
      await store.close();
    });
    await tester
        .pumpWidget(RstoneApp(dataService: app, preferencesService: prefs));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 360.0, 600.0]) {
    testWidgets(
        'settings combines sync controls and aligns margins at width $width',
        (tester) async {
      await openSettings(tester, width: width);
      expect(find.text('当前资料版本'), findsOneWidget);
      for (final removed in [
        '远程资料版本',
        '选择数据源',
        '恢复历史资料',
        '旧版资料恢复',
        '最近一次同步',
        '上次成功同步',
        '检查并同步',
        '数据校验与修复',
        '数据库版本'
      ]) {
        expect(find.text(removed), findsNothing);
      }
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      final button = find.widgetWithText(FilledButton, '更新');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      final card = find
          .ancestor(of: find.text('数据库同步'), matching: find.byType(Card))
          .first;
      final cardRect = tester.getRect(card),
          buttonRect = tester.getRect(button);
      expect(cardRect.left, 16);
      expect(width - cardRect.right, 16);
      expect(cardRect.right - buttonRect.right, 16);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('下载源'));
      await tester.pumpAndSettle();
      expect(find.text('镜像'), findsOneWidget);
      await tester.tap(find.text('镜像'));
      await tester.pumpAndSettle();
      expect(app.sync!.sources.preferredSource, 'https://mirror.test/');
      expect(find.text('镜像'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'new remote version appears only during an update and the result is shown once',
      (tester) async {
    await openSettings(tester);
    late Completer<void> started, release;
    late Future<bool> syncing;
    await tester.runAsync(() async {
      started = Completer<void>();
      release = Completer<void>();
      await fixture.publish(2, {'产品列表/RS1.md': product('UV')});
      fixture.transport.beforeResponse = (url) async {
        if (url.path.contains('/objects/')) {
          if (!started.isCompleted) started.complete();
          await release.future;
        }
      };
      await tester.tap(find.widgetWithText(FilledButton, '更新'));
      syncing = app.sync!.synchronize(); // Join the request started by the button.
      await Future.any([
        started.future,
        syncing.then((ok) => throw StateError(
            'Sync ended before download: $ok; ${app.sync!.failureDetails}; ${fixture.transport.requests}')),
      ]).timeout(const Duration(seconds: 5),
          onTimeout: () => throw StateError(
              'Download gate timed out: ${app.sync!.stage}; ${app.sync!.failureDetails}; ${fixture.transport.requests}'));
    });
    await tester.pump();
    expect(find.text('可更新至 2026.10.21.002'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '更新'))
            .onPressed,
        isNull);
    await tester.runAsync(() async {
      release.complete();
      expect(await syncing, isTrue);
    });
    await tester.pumpAndSettle();
    expect(find.text('可更新至 2026.10.21.002'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('资料已更新至 2026.10.21.002'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.runAsync(() => app.sync!.selectSource(null));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('最近一次同步'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
