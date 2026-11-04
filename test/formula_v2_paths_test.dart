import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/data_sync/data_sync_service.dart';
import 'package:rst_flutter/data_sync/services/source_manager.dart';
import 'package:rst_flutter/data_sync/storage/storage_adapter.dart';
import 'formula_structured_test.dart' show specimen, document;
import 'support/sync_fixture.dart';
import 'formula_protocol_probe.dart' as legacy;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unchanged 48 shared v1 goldens', legacy.main);
  for (final version in ['2.0.4', '2.0.5']) {
    test('manifest minimum 2.0.5 gates $version before CAS and retains active',
        () async {
      final f = SignedFixture();
      await f.initialize();
      final s = await f.memoryStorage();
      final sync = DataSyncService(
          storage: s,
          appVersion: version,
          sources: SourceManager(
              sources: [DataSource('synthetic', 'https://main.test/')],
              trustedKeys: f.keys,
              transport: f.transport));
      await sync.initialize();
      await f.publish(1, {'产品列表/RS87654321-Q5.md': product('old')});
      expect(await sync.synchronize(), isTrue);
      final active = await s.read(StorageAdapter.activeKey);
      final m = specimen()..['schema'] = 'rstone-recipe/2';
      await f.publish(
          2,
          {
            '产品列表/RS87654321-Q5.md': product('new'),
            '产品配方/RS87654321-Q5-底.md': document(m)
          },
          schema: 2,
          minAppVersion: '2.0.5');
      f.transport.requests.clear();
      expect(await sync.synchronize(), version == '2.0.5', reason: sync.error);
      if (version == '2.0.4') {
        expect(f.transport.objectRequests, isEmpty);
        expect(await s.read(StorageAdapter.activeKey), active);
        expect(sync.current!.sequence, 1);
      } else {
        expect(sync.snapshot.formulas.single.formulaDocument!.toJson(), m);
      }
      sync.dispose();
      await s.close();
    });
  }
}
