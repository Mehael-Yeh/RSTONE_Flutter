import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/data_sync/services/diff_engine.dart';
import 'package:rst_flutter/data_sync/data_sync_service.dart';
import 'package:rst_flutter/data_sync/services/index_manager.dart';
import 'package:rst_flutter/data_sync/storage/storage_adapter.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SignedFixture f;
  late StorageAdapter store;
  late ObsidianDataService app;
  setUp(() async {
    f = SignedFixture();
    await f.initialize();
    store = await f.memoryStorage();
    app = await f.app(store);
  });
  tearDown(() async {
    app.dispose();
    await store.close();
  });

  Future<void> install(Map<String, String> files) async {
    await f.publish(1, files);
    expect(await app.sync!.synchronize(), isTrue, reason: app.sync!.error);
    f.transport.requests.clear();
  }

  test('first install and offline restart use the accepted signed generation',
      () async {
    await install({'产品列表/RS1.md': product('水性')});
    expect(app.products.single.fileName, 'RS1');
    f.transport.offline = true;
    final offline = await f.app(store);
    expect(offline.products.single.tags, ['水性']);
    expect(await offline.sync!.synchronize(), isFalse);
    expect(offline.products.single.fileName, 'RS1');
    expect(offline.sync!.current!.sequence, 1);
    offline.dispose();
  });

  test('first install overlaps downloads with a bounded pool', () async {
    await f.publish(1, {
      for (var i = 0; i < 25; i++) '产品列表/RS$i.md': product('水性', 'file $i')
    });
    final started = Completer<void>(), release = Completer<void>();
    var active = 0, peak = 0;
    f.transport.beforeResponse = (url) async {
      if (!url.path.contains('/objects/')) return;
      active++;
      if (active > peak) peak = active;
      if (active == DataSyncService.downloadConcurrency &&
          !started.isCompleted) {
        started.complete();
      }
      await release.future;
      active--;
    };
    final syncing = app.sync!.synchronize();
    try {
      await started.future.timeout(const Duration(seconds: 5));
      expect(f.transport.objectRequests,
          hasLength(DataSyncService.downloadConcurrency));
      expect(app.sync!.current, isNull);
    } finally {
      release.complete();
    }
    expect(await syncing, isTrue);
    expect(peak, DataSyncService.downloadConcurrency);
    expect(f.transport.objectRequests, hasLength(25));
    expect(app.products, hasLength(25));
  });

  test('an unavailable source is not retried for every remaining object',
      () async {
    await f.publish(1, {
      for (var i = 0; i < 25; i++) '产品列表/RS$i.md': product('水性', 'file $i')
    });
    f.transport.beforeResponse = (url) async {
      if (url.host == 'main.test' && url.path.contains('/objects/')) {
        throw StateError('unavailable primary');
      }
    };
    expect(await app.sync!.synchronize(), isTrue);
    final primary =
        f.transport.objectRequests.where((url) => url.host == 'main.test');
    expect(primary.length,
        inInclusiveRange(1, DataSyncService.downloadConcurrency));
    expect(f.transport.objectRequests.where((url) => url.host == 'mirror.test'),
        hasLength(25));
  });

  test(
      'a failed parallel download drains in-flight writes before allowing retry',
      () async {
    await install({'产品列表/RS1.md': product('水性')});
    await f.publish(
        2, {'产品列表/RS1.md': product('UV'), '产品列表/RS2.md': product('PU')});
    final manifest = jsonDecode(
        utf8.decode(f.transport.resources['manifests/000002.json']!));
    final held = manifest['files'][0]['sha256'],
        blocked = manifest['files'][1]['sha256'];
    final started = Completer<void>(),
        failed = Completer<void>(),
        release = Completer<void>();
    var blockedAttempts = 0, finished = false;
    f.transport.beforeResponse = (url) async {
      if (url.path.endsWith(held)) {
        if (!started.isCompleted) started.complete();
        await release.future;
      }
      if (url.path.endsWith(blocked)) {
        if (++blockedAttempts == 2) failed.complete();
        throw StateError('object unavailable on both mirrors');
      }
    };
    final syncing = app.sync!.synchronize();
    syncing.then((_) => finished = true);
    await Future.wait([started.future, failed.future])
        .timeout(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(app.sync!.isSyncing, isTrue);
    release.complete();
    expect(await syncing, isFalse);
    expect(app.sync!.current!.sequence, 1);
    expect(await store.read('official/objects/$held'), isNotNull);
    f.transport.beforeResponse = null;
    f.transport.requests.clear();
    expect(await app.sync!.synchronize(), isTrue);
    expect(f.transport.objectRequests, hasLength(1));
    expect(f.transport.objectRequests.single.path, endsWith(blocked));
  });

  test(
      'post-download validation repairs changed bytes even with an unchanged fingerprint',
      () async {
    await install({'产品列表/RS1.md': product('水性')});
    final file = app.sync!.current!.files.single;
    final key = app.sync!.content.key(file.sha256);
    // Simulate a storage fault outside this session's verified fingerprint.
    final bytes = await store.read(key);
    final oldToken = await store.read('fingerprint/$key');
    await store.write(key, raw('X' * file.size));
    await store.write('fingerprint/$key', oldToken!);
    expect(await app.sync!.synchronize(), isTrue);
    expect(await store.read(key), bytes);
    expect(f.transport.objectRequests, hasLength(1));
    expect(app.sync!.plan!.count(DataChange.repair), 1);
  });

  test(
      'completion notice is consumed once and is not replayed after restart or a no-op',
      () async {
    await install({'产品列表/RS1.md': product('水性')});
    expect(app.sync!.takeCompletionNotice(), contains('资料已更新至'));
    expect(app.sync!.takeCompletionNotice(), isNull);
    expect(await app.sync!.synchronize(), isTrue);
    expect(app.sync!.takeCompletionNotice(), isNull);
    final reopened = await f.app(store);
    await f.publish(2, {'产品列表/RS1.md': product('水性')});
    expect(await app.sync!.synchronize(), isTrue);
    expect(app.sync!.downloadedBytes, 0);
    expect(app.sync!.takeCompletionNotice(), contains('2026.10.21.002'));
    expect(reopened.sync!.takeCompletionNotice(), isNull);
    reopened.dispose();
  });

  test('500 files: add 5 modify 8 delete 3 downloads exactly 13 objects',
      () async {
    final v1 = {
      for (var i = 0; i < 500; i++) '产品列表/RS$i.md': product('水性', 'original $i')
    };
    await install(v1);
    await app.addProductMarkdown(
        code: 'RS0', markdown: product('用户', 'my own file'));
    final v2 = {...v1};
    for (var i = 0; i < 3; i++) {
      v2.remove('产品列表/RS$i.md');
    }
    for (var i = 3; i < 11; i++) {
      v2['产品列表/RS$i.md'] = product('油性', 'modified $i');
    }
    for (var i = 500; i < 505; i++) {
      v2['产品列表/RS$i.md'] = product('水性', 'new $i');
    }
    await f.publish(2, v2);
    expect(await app.sync!.synchronize(), isTrue, reason: app.sync!.error);
    final plan = app.sync!.plan!;
    expect(plan.count(DataChange.add), 5);
    expect(plan.count(DataChange.modify), 8);
    expect(plan.count(DataChange.delete), 3);
    expect(plan.count(DataChange.unchanged), 489);
    expect(f.transport.objectRequests.length, 13);
    expect(app.sync!.downloadedBytes, plan.downloadBytes);
    expect(app.sync!.current!.files.length, 502);
    expect(app.products.length,
        503); // The user's RS0 survives its official deletion.
    expect(app.products.singleWhere((p) => p.fileName == 'RS0').origin,
        DataOrigin.user);
    expect(app.products.any((p) => p.fileName == 'RS1' || p.fileName == 'RS2'),
        isFalse);
    expect(app.search('RS1').any((p) => p.fileName == 'RS1'), isFalse);
    expect((await store.keys('official/objects/')).length,
        513); // Old deleted objects remain harmless.
    final restarted = await f.app(store);
    expect(restarted.products.any((p) => p.fileName == 'RS1'), isFalse);
    expect(restarted.products.singleWhere((p) => p.fileName == 'RS0').origin,
        DataOrigin.user);
    restarted.dispose();
  });

  test('rename and nested move share the existing immutable object', () async {
    await install({'产品列表/RS1.md': product('水性'), '产品应用/方案.md': '[[RS1]]'});
    await f.publish(
        20, {'产品列表/RS-renamed.md': product('水性'), '产品应用/PC/方案.md': '[[RS1]]'});
    expect(await app.sync!.synchronize(), isTrue);
    expect(app.sync!.plan!.count(DataChange.add), 2);
    expect(app.sync!.plan!.count(DataChange.delete), 2);
    expect(f.transport.objectRequests, isEmpty);
    expect(app.applications.single.filePath, '产品应用/PC/方案.md');
  });

  test('product and TDS deletions invalidate exact grade and search indexes',
      () async {
    await install({
      '产品列表/RS1.md': product('水性'),
      '产品TDS/RS1.TDS.md': '# TDS',
      '产品应用/方案.md': '[[RS1]]'
    });
    expect(app.tdsForProduct('RS1'), '# TDS');
    expect(app.tdsForProduct(' rs1 '), '# TDS');
    expect(app.tdsForProduct('rd 1'), isNull);
    await f.publish(2, {'产品应用/方案.md': '[[RS1]]'});
    expect(await app.sync!.synchronize(), isTrue);
    expect(app.products, isEmpty);
    expect(app.search('水性'), isEmpty);
    expect(app.tdsByProduct, isEmpty);
    for (final name in ['RS1', 'rs-1', 'RD1']) {
      expect(app.tdsForProduct(name), isNull);
    }
    expect(app.applications, hasLength(1));
    expect(app.unresolvedReferencesFor(app.applications.single), ['RS1']);
  });

  test('official rules change dynamically and user rules stay intact',
      () async {
    await install(
        {'产品列表/RS1.md': product('新材'), officialRulesPath: '新材 -> 旧名'});
    await app.saveTagAliasRules('新材 -> 自定义');
    expect(app.search('旧名'), hasLength(1));
    await f.publish(
        2, {'产品列表/RS1.md': product('新材'), officialRulesPath: '新材 -> 新名'});
    expect(await app.sync!.synchronize(), isTrue);
    expect(app.search('旧名'), isEmpty);
    expect(app.search('新名'), hasLength(1));
    expect(app.search('自定义'), hasLength(1));
    expect(app.customTagAliasRulesRaw, '新材 -> 自定义');
  });

  for (final mode in ['missing', 'corrupt', 'wrong-size']) {
    test(
        'same sequence repairs a $mode object without downloading healthy files',
        () async {
      await install(
          {'产品列表/RS1.md': product('水性'), '产品列表/RS2.md': product('油性')});
      final file = app.sync!.current!.files.first;
      final key = 'official/objects/${file.sha256}';
      if (mode == 'missing') {
        await store.remove(key);
      } else {
        await store.write(
            key, mode == 'corrupt' ? raw('X' * file.size) : raw('X'));
      }
      expect(await app.sync!.synchronize(), isTrue, reason: app.sync!.error);
      expect(app.sync!.current!.sequence, 1);
      expect(app.sync!.plan!.count(DataChange.repair), 1);
      expect(f.transport.objectRequests, hasLength(1));
      expect(app.products, hasLength(2));
    });
  }

  test(
      'download interruption leaves old snapshot active and retries reuse completed objects',
      () async {
    await install({'产品列表/RS1.md': product('水性')});
    await f.publish(
        2, {'产品列表/RS1.md': product('油性'), '产品列表/RS2.md': product('PU')});
    final latest = jsonDecode(
        utf8.decode(f.transport.resources['manifests/000002.json']!));
    final blocked = 'objects/${latest['files'][1]['sha256']}';
    f.transport.failures.addAll(['main.test/$blocked', 'mirror.test/$blocked']);
    expect(await app.sync!.synchronize(), isFalse);
    expect(app.products.single.tags, ['水性']);
    expect(app.sync!.current!.sequence, 1);
    f.transport.failures.clear();
    f.transport.requests.clear();
    expect(await app.sync!.synchronize(), isTrue);
    expect(f.transport.objectRequests, hasLength(1));
    expect(app.products, hasLength(2));
  });

  test(
      'per-object mirror fallback verifies bytes without changing target manifest',
      () async {
    await install({'产品列表/RS1.md': product('水性')});
    await f.publish(2, {'产品列表/RS1.md': product('油性')});
    final m = jsonDecode(
        utf8.decode(f.transport.resources['manifests/000002.json']!));
    final path = 'objects/${m['files'][0]['sha256']}';
    f.transport.overrides['main.test/$path'] = raw('bad');
    expect(await app.sync!.synchronize(), isTrue);
    expect(f.transport.objectRequests.map((r) => r.host).toList(),
        ['main.test', 'mirror.test']);
    expect(app.products.single.tags, ['油性']);
  });

  test('forged signatures keep installed data and watermark intact', () async {
    await install({'产品列表/RS1.md': product('水性')});
    await f.publish(2, {'产品列表/RS1.md': product('油性')});
    f.transport.resources['manifests/000002.sig'] =
        raw('${base64Encode(List.filled(64, 0))}\n');
    expect(await app.sync!.synchronize(), isFalse);
    expect(app.sync!.current!.sequence, 1);
    expect(f.transport.objectRequests, isEmpty);
    expect(app.products.single.tags, ['水性']);
  });

  for (final mode in ['schema', 'appVersion', 'key']) {
    test('incompatible $mode fails before downloading objects', () async {
      await install({'产品列表/RS1.md': product('水性')});
      await f.publish(2, {'产品列表/RS1.md': product('油性')},
          schema: mode == 'schema' ? 2 : 1,
          minAppVersion: mode == 'appVersion' ? '99.0.0' : '0.0.263',
          edit: mode == 'key'
              ? (m) {
                  m['keyId'] = 'unknown';
                }
              : null);
      expect(await app.sync!.synchronize(), isFalse);
      expect(app.sync!.current!.sequence, 1);
      expect(f.transport.objectRequests, isEmpty);
    });
  }

  test(
      'replay and same-sequence conflicts rejected; higher-sequence restore accepted',
      () async {
    await install({'产品列表/RS1.md': product('水性')});
    final v1 = Map.of(f.transport.resources);
    await f.publish(2, {'产品列表/RS1.md': product('油性')});
    expect(await app.sync!.synchronize(), isTrue);
    f.transport.resources.addAll(v1);
    expect(await app.sync!.synchronize(), isFalse);
    await f.publish(2, {'产品列表/RS1.md': product('PU')});
    expect(await app.sync!.synchronize(), isFalse);
    await f.publish(3, {'产品列表/RS1.md': product('水性')});
    f.transport.requests.clear();
    expect(await app.sync!.synchronize(), isTrue);
    expect(f.transport.objectRequests, isEmpty);
    expect(app.sync!.current!.sequence, 3);
  });

  test('termination after objects persisted but before commit restarts into V1',
      () async {
    await install({'产品列表/RS1.md': product('水性')});
    final fault = FaultStorage(store)..failCommit = true;
    final crashing = await f.app(fault);
    await f.publish(2, {'产品列表/RS1.md': product('油性')});
    expect(await crashing.sync!.synchronize(), isFalse);
    expect(crashing.products.single.tags, ['水性']);
    final restarted = await f.app(store);
    expect(restarted.sync!.current!.sequence, 1);
    f.transport.requests.clear();
    expect(await restarted.sync!.synchronize(), isTrue);
    expect(f.transport.objectRequests, isEmpty);
    crashing.dispose();
    restarted.dispose();
  });

  test(
      'index rebuild failure happens before commit and after-commit restart rebuilds',
      () async {
    await install({'产品列表/RS1.md': product('水性')});
    final manager = FailingIndexManager();
    final indexed = await f.app(store, indexManager: manager);
    manager.fail = true;
    await f.publish(2, {'产品列表/RS1.md': product('油性')});
    expect(await indexed.sync!.synchronize(), isFalse);
    final old = await f.app(store);
    expect(old.sync!.current!.sequence, 1);
    old.dispose();
    manager.fail = false;
    expect(await indexed.sync!.synchronize(), isTrue);
    final restarted = await f.app(store);
    expect(restarted.products.single.tags, ['油性']);
    indexed.dispose();
    restarted.dispose();
  });

  test(
      'disk full and malformed Markdown roll back without changing user overlay',
      () async {
    await install({'产品列表/RS1.md': product('水性')});
    await app.addApplicationMarkdown(name: '个人方案', markdown: 'my work');
    final fault = FaultStorage(store)..failWrite = true;
    final broken = await f.app(fault);
    await f.publish(2, {'产品列表/RS1.md': product('油性')});
    expect(await broken.sync!.synchronize(), isFalse);
    fault.failWrite = false;
    await f.publish(3, {'产品列表/RS1.md': '---\ntags: [broken\n---\n正文'});
    expect(await broken.sync!.synchronize(), isFalse);
    expect(broken.sync!.current!.sequence, 1);
    expect(broken.applications.single.rawContent, 'my work');
    broken.dispose();
  });

  test(
      'user same-name override survives official changes and deletion, then removal never restores assets',
      () async {
    await install({'产品列表/RS1.md': product('水性'), '产品列表/RS2.md': product('UV')});
    await app.addProductMarkdown(code: 'RS1', markdown: product('个人'));
    await f.publish(
        2, {'产品列表/RS1.md': product('油性'), '产品列表/RS2.md': product('UV')});
    expect(await app.sync!.synchronize(), isTrue);
    expect(app.products.singleWhere((p) => p.fileName == 'RS1').tags, ['个人']);
    await f.publish(3, {'产品列表/RS2.md': product('UV')});
    expect(await app.sync!.synchronize(), isTrue);
    await app
        .deleteManualItem(app.products.singleWhere((p) => p.fileName == 'RS1'));
    expect(app.products.any((p) => p.fileName == 'RS1'), isFalse);
  });

  test('notes columns sorting and theme retain their existing preference keys',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.initialize();
    await prefs.saveProductNote('RS1', 'my note');
    await prefs.saveThemeMode('dark');
    await prefs.saveProductListColumns(['标签', '牌号']);
    await prefs.saveProductListSort('牌号');
    await install({'产品列表/RS1.md': product('水性')});
    await f.publish(8, {'产品列表/RS2.md': product('油性')});
    expect(await app.sync!.synchronize(), isTrue);
    final reloaded = PreferencesService();
    await reloaded.initialize();
    expect(reloaded.getProductNote('RS1'), 'my note');
    expect(reloaded.getThemeMode(), 'dark');
    expect(reloaded.getProductListColumns([]), ['标签', '牌号']);
    expect(reloaded.getProductListSort(), '牌号');
  });

  test('simultaneous sync requests share one flight', () async {
    await f.publish(1, {'产品列表/RS1.md': product('水性')});
    f.transport.gate = Completer<void>();
    final first = app.sync!.synchronize();
    final second = app.sync!.synchronize(repair: true);
    expect(identical(first, second), isTrue);
    f.transport.gate!.complete();
    expect(await first, isTrue);
    expect(f.transport.objectRequests, hasLength(1));
  });

  test(
      'BOM and CRLF are hashed raw and parsed without changing content identity',
      () async {
    await install(
        {'产品列表/RS1.md': '\uFEFF---\r\ntags:\r\n  - 水性\r\n---\r\n正文\r\n'});
    expect(app.products.single.tags, ['水性']);
    expect(await app.sync!.synchronize(), isTrue);
    expect(f.transport.objectRequests, isEmpty);
  });

  test(
      'startup falls back to the complete previous generation without lowering watermark',
      () async {
    await install({'产品列表/RS1.md': product('水性')});
    await f.publish(2, {'产品列表/RS2.md': product('油性')});
    expect(await app.sync!.synchronize(), isTrue);
    final hash = app.sync!.current!.files.single.sha256;
    await store.remove('official/objects/$hash');
    final recovered = await f.app(store);
    expect(recovered.sync!.current!.sequence, 2);
    expect(recovered.sync!.servingManifest!.sequence, 1);
    expect(recovered.products.single.fileName, 'RS1');
    expect(recovered.sync!.databaseVersion, '2026.10.21.001');
    expect(await recovered.sync!.synchronize(repair: true), isTrue);
    expect(recovered.products.single.fileName, 'RS2');
    expect(recovered.sync!.servingManifest!.sequence, 2);
    recovered.dispose();
  });

  test(
      'corrupt replay record fails closed instead of treating installation as new',
      () async {
    await install({'产品列表/RS1.md': product('水性')});
    await app.addProductMarkdown(code: 'RS-user', markdown: product('个人'));
    final active = await store.read(StorageAdapter.activeKey);
    final json = jsonDecode(utf8.decode(active!)) as Map<String, dynamic>;
    json['highestSequence'] = 0;
    await store.commitActive(active, raw(jsonEncode(json)));
    final broken = await f.app(store);
    expect(broken.initializationError, isNotNull);
    expect(broken.products.single.origin, DataOrigin.user);
    expect(await broken.sync!.synchronize(), isFalse);
    expect(
        jsonDecode(utf8.decode((await store.read(StorageAdapter.activeKey))!))[
            'highestSequence'],
        0);
    broken.dispose();
  });

  test('a verified same-sequence conflict in one mirror halts the whole update',
      () async {
    await install({'产品列表/RS1.md': product('水性')});
    final old = Map.of(f.transport.resources);
    await f.publish(1, {'产品列表/RS1.md': product('油性')});
    for (final path in [
      'latest.json',
      'manifests/000001.json',
      'manifests/000001.sig'
    ]) {
      f.transport.overrides['mirror.test/$path'] = old[path]!;
    }
    expect(await app.sync!.synchronize(), isFalse);
    expect(app.products.single.tags, ['水性']);
    expect(f.transport.objectRequests, isEmpty);
  });

  test('cached hash verification also binds the expected object length',
      () async {
    await install({'产品列表/RS1.md': product('水性')});
    await f.publish(2, {'产品列表/RS1.md': product('水性')}, edit: (m) {
      m['files'][0]['size'] = (m['files'][0]['size'] as int) + 1;
    });
    expect(await app.sync!.synchronize(), isFalse);
    expect(app.sync!.current!.sequence, 1);
    expect(app.products.single.tags, ['水性']);
  });

  test('preferred mirror wins equal sequences and source choice persists',
      () async {
    await f.publish(1, {'产品列表/RS1.md': product('水性')});
    await app.sync!.selectSource('https://mirror.test/');
    expect(await app.sync!.synchronize(), isTrue);
    expect(f.transport.objectRequests.single.host, 'mirror.test');
    final reopened = await f.app(store);
    expect(reopened.sync!.sources.preferredSource, 'https://mirror.test/');
    await reopened.sync!.selectSource(null);
    expect(reopened.sync!.sources.ordered.first.baseUrl.host, 'main.test');
    reopened.dispose();
  });
}
