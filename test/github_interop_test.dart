import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/data_sync/data_sync_service.dart';
import 'package:rst_flutter/data_sync/services/source_manager.dart';
import 'support/sync_fixture.dart';

void main() {
  test('public GitHub publisher example verifies and downloads over real HTTPS',
      () async {
    // Explicit opt-in. Normal CI/regression tests never depend on GitHub.
    final corpus =
        jsonDecode(await File('test/fixtures/protocol_v1.json').readAsString())
            as Map<String, dynamic>;
    final store = await SignedFixture().memoryStorage();
    final transport = HttpDataTransport();
    final sync = DataSyncService(
        storage: store,
        appVersion: '1.0.0',
        sources: SourceManager(
            sources: [
              DataSource('GitHub public protocol fixture',
                  'https://raw.githubusercontent.com/Mehael-Yeh/RSTONE_Data/07e489195ce77acdb0aecabaf5a6ea646ae085f6/examples/distribution/')
            ],
            trustedKeys: Map<String, String>.from(corpus['keys'] as Map),
            transport: transport));
    try {
      await sync.initialize();
      expect(await sync.synchronize(), isTrue,
          reason: '${sync.failureDetails}; ${sync.sources.failures}');
      expect(sync.current!.sequence, 2);
      expect(sync.current!.files, hasLength(5));
      expect(sync.snapshot.products, hasLength(2));
      expect(await sync.synchronize(), isTrue, reason: sync.failureDetails);
      expect(sync.downloadedBytes, 0);
    } finally {
      sync.dispose();
      transport.close();
      await store.close();
    }
  },
      skip: !const bool.fromEnvironment('RUN_GITHUB_INTEROP'),
      timeout: const Timeout(Duration(minutes: 2)));
}
