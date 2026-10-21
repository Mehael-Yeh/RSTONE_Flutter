import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_browser.dart';
import 'package:rst_flutter/data_sync/storage/indexed_db_storage.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'real browser IndexedDB transaction, reopen, repair, deletion and user overlay',
      () async {
    final name = 'rstone-browser-test-${DateTime.now().microsecondsSinceEpoch}';
    var store = await IndexedDbStorage.open(idbFactoryNative, name: name);
    final f = SignedFixture();
    await f.initialize();
    var app = await f.app(store);
    try {
      await f.publish(1, {
        '产品列表/RS1.md': product('水性'),
        '产品列表/RS2.md': product('UV'),
        '产品TDS/RS1.TDS.md': '# TDS'
      });
      expect(await app.sync!.synchronize(), isTrue, reason: app.sync!.error);
      await app.addProductMarkdown(code: 'RS1', markdown: product('个人'));
      final oldHash = app.sync!.current!.files.first.sha256;
      await store.write('official/objects/$oldHash', raw('broken'));
      expect(await app.sync!.synchronize(repair: true), isTrue,
          reason: app.sync!.error);
      await f.publish(2, {'产品列表/RS2.md': product('UV')});
      expect(await app.sync!.synchronize(), isTrue, reason: app.sync!.error);
      expect(app.tdsForProduct('RD1'), isNull);
      app.dispose();
      await store.close();
      store = await IndexedDbStorage.open(idbFactoryNative, name: name);
      app = await f.app(store);
      expect(app.products.singleWhere((p) => p.fileName == 'RS1').origin,
          DataOrigin.user);
      await app.deleteManualItem(
          app.products.singleWhere((p) => p.fileName == 'RS1'));
      expect(app.products.map((p) => p.fileName).toList(), ['RS2']);
      expect(app.sync!.current!.sequence, 2);
      await expectLater(store.commitActive(null, raw('{}')), throwsStateError);
    } finally {
      app.dispose();
      await store.close();
      await idbFactoryNative.deleteDatabase(name);
    }
  }, skip: !kIsWeb);
}
