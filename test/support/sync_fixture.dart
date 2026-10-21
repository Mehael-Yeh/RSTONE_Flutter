import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:rst_flutter/data_sync/data_sync_service.dart';
import 'package:rst_flutter/data_sync/protocol/rstone_protocol.dart';
import 'package:rst_flutter/data_sync/services/index_manager.dart';
import 'package:rst_flutter/data_sync/services/source_manager.dart';
import 'package:rst_flutter/data_sync/storage/indexed_db_storage.dart';
import 'package:rst_flutter/data_sync/storage/storage_adapter.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';

Uint8List raw(String value) => Uint8List.fromList(utf8.encode(value));
String product(String tag, [String text = '正文']) =>
    '---\ntags:\n  - $tag\n---\n$text\n';

class FakeTransport implements DataTransport {
  final Map<String, Uint8List> resources = {};
  final List<Uri> requests = [];
  final Set<String> failures = {};
  final Map<String, Uint8List> overrides = {};
  bool offline = false;
  Completer<void>? gate;
  Future<void> Function(Uri)? beforeResponse;
  @override
  Future<Uint8List> get(Uri url, {required int maxBytes}) async {
    requests.add(url);
    await beforeResponse?.call(url);
    if (gate != null) await gate!.future;
    final key = '${url.host}${url.path}';
    if (offline || failures.contains(key)) {
      throw StateError('simulated connection interruption');
    }
    final bytes =
        overrides[key] ?? resources[key] ?? resources[url.path.substring(1)];
    if (bytes == null || bytes.length > maxBytes) {
      throw StateError('simulated 404 or oversized response');
    }
    return Uint8List.fromList(bytes);
  }

  List<Uri> get objectRequests =>
      requests.where((r) => r.path.contains('/objects/')).toList();
  @override
  void close() {}
}

class SignedFixture {
  late SimpleKeyPair key;
  late Map<String, String> keys;
  final FakeTransport transport = FakeTransport();
  Future<void> initialize() async {
    key = await Ed25519().newKeyPair();
    keys = {'test-key': base64Encode((await key.extractPublicKey()).bytes)};
  }

  Future<void> publish(
    int sequence,
    Map<String, String> files, {
    String minAppVersion = '0.0.263',
    int schema = 1,
    void Function(Map<String, dynamic>)? edit,
  }) async {
    final entries = <Map<String, Object>>[];
    for (final entry in files.entries) {
      final bytes = raw(entry.value);
      final hash = await sha256Hex(bytes);
      transport.resources['objects/$hash'] = bytes;
      entries.add({'path': entry.key, 'sha256': hash, 'size': bytes.length});
    }
    entries
        .sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
    final manifest = <String, dynamic>{
      'protocolVersion': 1,
      'schemaVersion': schema,
      'sequence': sequence,
      'dataVersion': '2026.10.21.${sequence.toString().padLeft(3, '0')}',
      'minAppVersion': minAppVersion,
      'publishedAt': '2026-10-21T00:00:00Z',
      'keyId': 'test-key',
      'sourceCommits': {
        'Mehael-Yeh/Rstone': 'a' * 40,
        'Mehael-Yeh/RstoneTDS': 'b' * 40
      },
      'files': entries,
    };
    edit?.call(manifest);
    final bytes = raw('${jsonEncode(manifest)}\n');
    final name = sequence.toString().padLeft(6, '0');
    transport.resources['manifests/$name.json'] = bytes;
    final sig = await Ed25519().sign(bytes, keyPair: key);
    transport.resources['manifests/$name.sig'] =
        raw('${base64Encode(sig.bytes)}\n');
    transport.resources['latest.json'] = raw(jsonEncode({
      'protocolVersion': 1,
      'sequence': sequence,
      'dataVersion': manifest['dataVersion'],
      'keyId': manifest['keyId'],
      'manifestPath': 'manifests/$name.json',
      'signaturePath': 'manifests/$name.sig',
      'manifestSha256': await sha256Hex(bytes),
    }));
  }

  DataSyncService engine(StorageAdapter storage,
          {IndexManager? indexManager}) =>
      DataSyncService(
          storage: storage,
          appVersion: '1.0.0',
          indexManager: indexManager,
          sources: SourceManager(sources: [
            DataSource('主源', 'https://main.test/'),
            DataSource('镜像', 'https://mirror.test/')
          ], trustedKeys: keys, transport: transport));

  Future<StorageAdapter> memoryStorage() =>
      IndexedDbStorage.open(newIdbFactoryMemory(), name: 'rstone-test');
  Future<ObsidianDataService> app(StorageAdapter storage,
      {IndexManager? indexManager}) async {
    final app = ObsidianDataService(
        syncService: engine(storage, indexManager: indexManager),
        migrateLegacy: false,
        bootstrapRules: '');
    await app.initialize();
    return app;
  }
}

class FailingIndexManager extends IndexManager {
  bool fail = false;
  @override
  Future<DataSnapshot> prepare(Map<String, String> files) {
    if (fail) throw StateError('simulated index rebuild failure');
    return super.prepare(files);
  }
}

class FaultStorage extends StorageAdapter {
  final StorageAdapter base;
  bool failCommit = false, failWrite = false;
  FaultStorage(this.base);
  @override
  Future<Uint8List?> read(String key) => base.read(key);
  @override
  Future<void> write(String key, Uint8List bytes) {
    if (failWrite && key.startsWith('official/objects/')) {
      throw StateError('simulated disk full');
    }
    return base.write(key, bytes);
  }

  @override
  Future<void> remove(String key) => base.remove(key);
  @override
  Future<List<String>> keys(String prefix) => base.keys(prefix);
  @override
  Future<String?> fingerprint(String key) => base.fingerprint(key);
  @override
  Future<void> commitActive(Uint8List? expected, Uint8List next) {
    if (failCommit) throw StateError('simulated termination before commit');
    return base.commitActive(expected, next);
  }

  @override
  Future<void> close() => base.close();
}
