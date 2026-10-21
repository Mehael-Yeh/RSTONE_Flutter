import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rst_flutter/data_sync/storage/native_storage.dart';
import 'package:rst_flutter/models/product_item.dart';
import '../test/support/sync_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'native platform transaction, offline restart, repair and user overlay',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: Text('验证离线资料同步'))));
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('rstone-integration-');
      var store = await NativeStorage.open(root: root);
      final f = SignedFixture();
      await f.initialize();
      var app = await f.app(store);
      try {
        await f.publish(1, {
          '产品列表/RS1.md': product('水性'),
          '产品列表/RS2.md': product('UV'),
          '产品TDS/RS1.TDS.md': '# TDS',
          '产品应用/方案.md': '[[RS1]]'
        });
        expect(await app.sync!.synchronize(), isTrue,
            reason: app.sync!.failureDetails);
        await app.addProductMarkdown(code: 'RS1', markdown: product('个人'));
        final record = app.sync!.current!.files.first;
        await store.write('official/objects/${record.sha256}', raw('corrupt'));
        expect(await app.sync!.synchronize(repair: true), isTrue,
            reason: app.sync!.failureDetails);
        await f.publish(
            9, {'产品列表/RS2.md': product('UV'), '产品应用/方案.md': '[[RS1]]'});
        expect(await app.sync!.synchronize(), isTrue,
            reason: app.sync!.failureDetails);
        expect(app.tdsForProduct('RD1'), isNull);
        app.dispose();
        await store.close();
        store = await NativeStorage.open(root: root);
        f.transport.offline = true;
        app = await f.app(store);
        expect(app.sync!.current!.sequence, 9);
        expect(app.products.singleWhere((p) => p.fileName == 'RS1').origin,
            DataOrigin.user);
        await app.deleteManualItem(
            app.products.singleWhere((p) => p.fileName == 'RS1'));
        expect(app.products.map((p) => p.fileName).toList(), ['RS2']);
        expect(app.applications.single.unresolvedProductReferences, ['RS1']);
        expect(await app.sync!.synchronize(), isFalse);
        expect(app.products.single.fileName, 'RS2');
      } finally {
        app.dispose();
        await store.close();
        if (root.path.startsWith(Directory.systemTemp.path) &&
            root.path.contains('rstone-integration-')) {
          await root.delete(recursive: true);
        }
      }
    });
  });
}
