import 'dart:typed_data';
import 'dart:convert';
import 'package:idb_shim/idb.dart';
import 'storage_adapter.dart';

/// Shared by real browser IndexedDB and the in-memory IDB contract tests.
class IndexedDbStorage extends StorageAdapter {
  final Database db;
  IndexedDbStorage._(this.db);
  static Future<IndexedDbStorage> open(IdbFactory factory,
      {String name = 'rstone-data-v1'}) async {
    final db = await factory.open(name, version: 1, onUpgradeNeeded: (event) {
      event.database.createObjectStore('data');
    });
    return IndexedDbStorage._(db);
  }

  Future<T> _transaction<T>(
      String mode, Future<T> Function(ObjectStore) action) async {
    final tx = db.transaction('data', mode);
    // idb_shim installs native completion handlers lazily. Subscribe before
    // the first request so fast browser transactions cannot finish first.
    final done = tx.completed;
    done.ignore();
    try {
      final result = await action(tx.objectStore('data'));
      await done;
      return result;
    } catch (_) {
      try {
        tx.abort();
      } catch (_) {/* Already completed or aborted. */}
      try {
        await done;
      } catch (_) {/* Preserve the original failure. */}
      rethrow;
    }
  }

  @override
  Future<Uint8List?> read(String key) {
    validateStorageKey(key);
    return _transaction(idbModeReadOnly, (store) async {
      final value = await store.getObject(key);
      return value == null
          ? null
          : Uint8List.fromList((value as List).cast<int>());
    });
  }

  @override
  Future<void> write(String key, Uint8List bytes) {
    validateStorageKey(key);
    if (key == StorageAdapter.activeKey) throw StateError('Use commitActive');
    return _transaction(idbModeReadWrite, (store) async {
      final revision =
          ((await store.getObject('_write_revision')) as int? ?? 0) + 1;
      await store.put(revision, '_write_revision');
      await store.put(bytes, key);
      await store.put(
          Uint8List.fromList(utf8.encode('$revision')), 'fingerprint/$key');
    });
  }

  @override
  Future<void> remove(String key) {
    validateStorageKey(key);
    if (key == StorageAdapter.activeKey) {
      throw StateError('Active state cannot be cleared');
    }
    return _transaction(idbModeReadWrite, (store) async {
      await store.delete(key);
      await store.delete('fingerprint/$key');
    });
  }

  @override
  Future<List<String>> keys(String prefix) =>
      _transaction(idbModeReadOnly, (store) async {
        final keys = await store.getAllKeys();
        return keys.cast<String>().where((k) => k.startsWith(prefix)).toList();
      });

  // The monotonic token changes in the SAME IDB transaction as the bytes.
  // ContentStore re-verifies all objects after a browser restart.
  @override
  Future<String?> fingerprint(String key) => readText('fingerprint/$key');

  @override
  Future<void> commitActive(Uint8List? expected, Uint8List next) =>
      _transaction(idbModeReadWrite, (store) async {
        final value = await store.getObject(StorageAdapter.activeKey);
        if (!sameBytes(
            value == null ? null : (value as List).cast<int>(), expected)) {
          throw StateError('Another synchronization committed first');
        }
        await store.put(next, StorageAdapter.activeKey);
      });

  @override
  Future<void> close() async => db.close();
}
