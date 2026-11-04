import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/data_sync/data_sync_service.dart';
import 'package:rst_flutter/data_sync/services/source_manager.dart';
import 'package:rst_flutter/data_sync/services/index_manager.dart';
import 'package:rst_flutter/data_sync/storage/storage_adapter.dart';
import 'formula_structured_test.dart' show specimen, document;
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'schema2 >=2.0.2 synchronizes typed generation; invalid candidates never commit active',
      () async {
    final f = SignedFixture();
    await f.initialize();
    final store = await f.memoryStorage();
    final sync = DataSyncService(
        storage: store,
        appVersion: '2.0.2',
        sources: SourceManager(
            sources: [DataSource('synthetic', 'https://main.test/')],
            trustedKeys: f.keys,
            transport: f.transport));
    await sync.initialize();
    await f.publish(1, {
      '产品列表/RS87654321-Q5.md': product('水性'),
      '产品配方/old.md': '| legacy | 1 |'
    });
    expect(await sync.synchronize(), isTrue);
    final files = {
      '产品列表/RS87654321-Q5.md': product('水性'),
      '产品配方/RS87654321-Q5-底.md': document()
    };
    await f.publish(2, files, schema: 2, minAppVersion: '2.0.2');
    expect(await sync.synchronize(), isTrue, reason: sync.error);
    expect(sync.snapshot.formulas.single.formulaDocument, isNotNull);
    final active = await store.read(StorageAdapter.activeKey);
    final badMissing = specimen()
      ..['associatedProducts'] = ['RS87654321-Q5', 'RS404-Z'];
    for (final bad in [
      document().replaceFirst('rstone-recipe/1', 'rstone-recipe/9'),
      '${document()}\n',
      '\uFEFF${document()}',
      document(badMissing),
      'legacy markdown'
    ]) {
      await f.publish(3, {...files, '产品配方/RS87654321-Q5-底.md': bad},
          schema: 2, minAppVersion: '2.0.2');
      expect(await sync.synchronize(), isFalse);
      expect(sync.error, contains('配方资料校验未通过'));
      expect(sync.current!.sequence, 2);
      expect(await store.read(StorageAdapter.activeKey), active);
      expect(sync.snapshot.formulas.single.formulaDocument!.recipeId,
          specimen()['recipeId']);
    }
    await f.publish(4, files, schema: 2, minAppVersion: '2.0.1');
    expect(await sync.synchronize(), isFalse);
    await f.publish(4, files, schema: 3, minAppVersion: '2.0.2');
    expect(await sync.synchronize(), isFalse);
    sync.dispose();
    await store.close();
  });
  test('2.0.1 client retains last-good when schema2 requires 2.0.2', () async {
    final f = SignedFixture();
    await f.initialize();
    final s = await f.memoryStorage();
    final sync = DataSyncService(
        storage: s,
        appVersion: '2.0.1',
        sources: SourceManager(
            sources: [DataSource('synthetic', 'https://main.test/')],
            trustedKeys: f.keys,
            transport: f.transport));
    await sync.initialize();
    await f.publish(1, {'产品列表/RS1.md': product('old')});
    expect(await sync.synchronize(), isTrue);
    final active = await s.read(StorageAdapter.activeKey);
    await f.publish(2, {'产品列表/RS1.md': product('new')},
        schema: 2, minAppVersion: '2.0.2');
    f.transport.requests.clear();
    expect(await sync.synchronize(), isFalse);
    expect(sync.snapshot.products.single.tags, ['old']);
    expect(f.transport.objectRequests, isEmpty);
    expect(await s.read(StorageAdapter.activeKey), active);
    sync.dispose();
    await s.close();
  });
  test(
      'Web 32-entry path joins entire catalog before exact reference validation',
      () async {
    final files = {
      '产品配方/RS87654321-Q5-底.md': document(),
      for (var i = 0; i < 64; i++) '产品列表/RS${i + 100}.md': 'product',
      '产品列表/RS87654321-Q5.md': 'product'
    };
    final manager = IndexManager();
    final dynamic dynamicManager = manager;
    final DataSnapshot joined = await dynamicManager.prepareBatched(files);
    expect(joined.products, hasLength(65));
    expect(joined.formulas, hasLength(1));
    expect(
        (await manager.prepare(files))
            .formulas
            .single
            .formulaDocument!
            .toJson(),
        joined.formulas.single.formulaDocument!.toJson());
    files.remove('产品列表/RS87654321-Q5.md');
    expect(() => dynamicManager.prepareBatched(files), throwsFormatException);
  });
}
