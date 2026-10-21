import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:rst_flutter/data_sync/data_sync_service.dart';
import 'package:rst_flutter/data_sync/services/index_manager.dart';
import 'package:rst_flutter/data_sync/services/source_manager.dart';
import 'package:rst_flutter/data_sync/storage/native_storage.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';

class _MeasuredTransport implements DataTransport {
  final delegate = HttpDataTransport();
  final requests = <Uri>[];
  int objectBytes = 0;
  bool offline = false;
  int get objectRequests =>
      requests.where((u) => u.path.contains('/objects/')).length;

  @override
  Future<Uint8List> get(Uri url, {required int maxBytes}) async {
    requests.add(url);
    if (offline) throw const SocketException('Offline verification');
    final bytes = await delegate.get(url, maxBytes: maxBytes);
    if (url.path.contains('/objects/')) objectBytes += bytes.length;
    return bytes;
  }

  void reset() {
    requests.clear();
    objectBytes = 0;
  }

  @override
  void close() => delegate.close();
}

void main() {
  // Network verification is opt-in; ordinary regression tests stay offline.
  const enabled = bool.fromEnvironment('RUN_PRODUCTION_INTEROP');
  final config =
      jsonDecode(File('assets/data_sync_config.json').readAsStringSync())
          as Map<String, dynamic>;
  final version =
      (loadYaml(File('pubspec.yaml').readAsStringSync())['version'] as String)
          .split('+')
          .first;
  final entries = config['sources'] as List;
  for (var index = 0; index < entries.length; index++) {
    final source = entries[index] as Map;
    test(
        'production ${source['name']}: install, zero-object repeat, offline reopen',
        () async {
      final root = await Directory.systemTemp.createTemp('rstone-live-test-');
      var store = await NativeStorage.open(root: root);
      final transport = _MeasuredTransport();
      DataSyncService makeSync() => DataSyncService(
          storage: store,
          appVersion: version,
          sources: SourceManager(
              sources: [DataSource(source['name'], source['url'])],
              trustedKeys: Map<String, String>.from(config['keys']),
              transport: transport));
      ObsidianDataService makeApp() => ObsidianDataService(
          syncService: makeSync(),
          appVersion: version,
          migrateLegacy: false,
          bootstrapRules: '');
      var app = makeApp();
      try {
        final installWatch = Stopwatch()..start();
        await app.initialize();
        expect(app.initializationError, isNull);
        expect(await app.sync!.synchronize(), isTrue,
            reason:
                '${app.sync!.failureDetails}; ${app.sync!.sources.failures}');
        final manifest = app.sync!.current!;
        installWatch.stop();
        final signed = jsonDecode(utf8.decode(manifest.manifestBytes)) as Map;
        final hashes = manifest.files.map((f) => f.sha256).toSet();
        final sizes = {
          for (final file in manifest.files) file.sha256: file.size
        };
        expect(transport.objectRequests, hashes.length);
        expect(transport.objectBytes, sizes.values.reduce((a, b) => a + b));
        expect(
            app.products.length,
            manifest.files
                .where((f) =>
                    f.path.startsWith('产品列表/') && f.path != officialRulesPath)
                .length);
        expect(app.applications.length,
            manifest.files.where((f) => f.path.startsWith('产品应用/')).length);
        expect(app.formulas.length,
            manifest.files.where((f) => f.path.startsWith('产品配方/')).length);
        expect(app.tdsByProduct.length,
            manifest.files.where((f) => f.path.startsWith('产品TDS/')).length);
        final tdsFile =
            manifest.files.firstWhere((f) => f.path.startsWith('产品TDS/'));
        final tdsName = tdsFile.path
            .substring('产品TDS/'.length, tdsFile.path.length - '.TDS.md'.length);
        expect(app.tdsForProduct(tdsName), isNotNull);
        final report = <String, dynamic>{
          'source': source,
          'appVersion': version,
          'sequence': manifest.sequence,
          'dataVersion': manifest.dataVersion,
          'manifestSha256': manifest.hash,
          'keyId': signed['keyId'],
          'sourceCommits': signed['sourceCommits'],
          'files': manifest.files.length,
          'products': app.products.length,
          'applications': app.applications.length,
          'formulas': app.formulas.length,
          'tds': app.tdsByProduct.length,
          'firstObjectRequests': transport.objectRequests,
          'firstObjectBytes': transport.objectBytes,
          'installDurationMs': installWatch.elapsedMilliseconds,
        };

        await app.addProductMarkdown(
            code: 'RS-LIVE-PRIVATE', markdown: '# 个人验证\n\n标签: #个人');
        transport.reset();
        expect(await app.sync!.synchronize(), isTrue,
            reason: app.sync!.failureDetails);
        expect(transport.objectRequests, 0);
        expect(app.sync!.downloadedBytes, 0);
        report['repeatObjectRequests'] = transport.objectRequests;
        report['repeatObjectBytes'] = app.sync!.downloadedBytes;
        app.dispose();
        await store.close();

        store = await NativeStorage.open(root: root);
        transport.reset();
        transport.offline = true;
        app = makeApp();
        await app.initialize();
        expect(app.initializationError, isNull);
        expect(app.sync!.current!.hash, manifest.hash);
        expect(app.products.length, (report['products'] as int) + 1);
        expect(
            app.products
                .singleWhere((p) => p.fileName == 'RS-LIVE-PRIVATE')
                .origin,
            DataOrigin.user);
        expect(app.tdsForProduct(tdsName), isNotNull);
        expect(transport.requests, isEmpty);
        report['offlineReopen'] = true;
        report['personalPreserved'] = true;
        await Directory('build').create(recursive: true);
        await File('build/production-sync-$index.json').writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(report)}\n');
      } finally {
        app.dispose();
        transport.close();
        await store.close();
        // Remove only the isolated directory created by this test.
        if (root.absolute.path.startsWith(Directory.systemTemp.absolute.path) &&
            root.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('rstone-live-test-')) {
          await root.delete(recursive: true);
        }
      }
    }, skip: !enabled, timeout: const Timeout(Duration(minutes: 8)));
  }
}
