import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'storage_adapter.dart';

class NativeStorage extends StorageAdapter {
  final Directory root;
  final Database _db;
  int _tempId = 0;
  NativeStorage._(this.root, this._db);

  static Future<NativeStorage> open({Directory? root}) async {
    root ??=
        Directory('${(await getApplicationSupportDirectory()).path}/rst_data');
    await Directory('${root.path}/official/objects').create(recursive: true);
    final DatabaseFactory factory;
    if (Platform.isAndroid || Platform.isIOS) {
      factory = mobile.databaseFactory;
    } else {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    }
    final db = await factory.openDatabase('${root.path}/official/state.db',
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) async {
            await db.execute('PRAGMA synchronous = FULL');
            await db.rawQuery('PRAGMA journal_mode = DELETE');
          },
          onCreate: (db, _) => db.execute(
              'CREATE TABLE state (key TEXT PRIMARY KEY, value BLOB NOT NULL)'),
        ));
    return NativeStorage._(root, db);
  }

  bool _fileKey(String key) =>
      key.startsWith('official/objects/') ||
      key.startsWith('user/') ||
      key.startsWith('cache/');
  File _file(String key) {
    validateStorageKey(key);
    return File('${root.path}/$key');
  }

  @override
  Future<Uint8List?> read(String key) async {
    validateStorageKey(key);
    if (_fileKey(key)) {
      final file = _file(key);
      return await file.exists() ? file.readAsBytes() : null;
    }
    final rows = await _db.query('state',
        columns: ['value'], where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty
        ? null
        : Uint8List.fromList(rows.single['value'] as List<int>);
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    validateStorageKey(key);
    if (key == StorageAdapter.activeKey) throw StateError('Use commitActive');
    if (_fileKey(key)) {
      final file = _file(key);
      await file.parent.create(recursive: true);
      final part = File(
          '${file.path}.${DateTime.now().microsecondsSinceEpoch}.${_tempId++}.part');
      try {
        await part.writeAsBytes(bytes, flush: true);
        await part.rename(file.path);
      } finally {
        if (await part.exists()) await part.delete();
      }
    } else {
      await _db.insert('state', {'key': key, 'value': bytes},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  @override
  Future<void> remove(String key) async {
    validateStorageKey(key);
    if (key == StorageAdapter.activeKey) {
      throw StateError('Active state cannot be cleared');
    }
    if (_fileKey(key)) {
      final file = _file(key);
      if (await file.exists()) await file.delete();
    } else {
      await _db.delete('state', where: 'key = ?', whereArgs: [key]);
    }
  }

  @override
  Future<List<String>> keys(String prefix) async {
    final rows = await _db.query('state', columns: ['key']);
    final result = rows
        .map((r) => r['key'] as String)
        .where((k) => k.startsWith(prefix))
        .toList();
    for (final folder in ['official/objects', 'user', 'cache']) {
      final directory = Directory('${root.path}/$folder');
      if (!await directory.exists() ||
          (!'$folder/'.startsWith(prefix) && !prefix.startsWith(folder))) {
        continue;
      }
      await for (final entity
          in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final key =
              entity.path.substring(root.path.length + 1).replaceAll('\\', '/');
          if (key.startsWith(prefix) && !key.endsWith('.part')) result.add(key);
        }
      }
    }
    return result;
  }

  @override
  Future<String?> fingerprint(String key) async {
    if (!_fileKey(key)) return null;
    final stat = await _file(key).stat();
    return stat.type == FileSystemEntityType.file
        ? '${stat.size}:${stat.modified.microsecondsSinceEpoch}:${stat.changed.microsecondsSinceEpoch}'
        : null;
  }

  @override
  Future<void> commitActive(Uint8List? expected, Uint8List next) =>
      _db.transaction((tx) async {
        final rows = await tx.query('state',
            where: 'key = ?', whereArgs: [StorageAdapter.activeKey]);
        final current = rows.isEmpty ? null : rows.single['value'] as List<int>;
        if (!sameBytes(current, expected)) {
          throw StateError('Another synchronization committed first');
        }
        await tx.insert(
            'state', {'key': StorageAdapter.activeKey, 'value': next},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });

  @override
  Future<void> close() => _db.close();
}

Future<StorageAdapter> openStorage() => NativeStorage.open();
