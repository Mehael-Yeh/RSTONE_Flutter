import 'dart:convert';

import '../data_sync/protocol/rstone_protocol.dart';
import '../data_sync/protocol/src/casefold.dart';
import '../data_sync/storage/storage_adapter.dart';

/// Single-writer undo journal. Clearing the journal is the commit point.
/// A pending journal is rolled back before loading or accepting another edit.
/// If recovery cannot complete, the journal remains and mutations fail closed.
class PersonalProductTransaction {
  static const journalKey = 'user/transactions/product-edit.json';
  final StorageAdapter storage;
  PersonalProductTransaction(this.storage);

  void _validate(String path) {
    if (!path.startsWith('user/产品列表/')) {
      throw StateError('invalid-personal-transaction-path');
    }
    validateLogicalPath(path.substring(5));
  }

  Future<void> recover() async {
    final raw = await storage.readText(journalKey);
    if (raw == null) return;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['version'] != 1) throw StateError('unknown-personal-transaction');
    final oldPath = j['oldPath'] as String, newPath = j['newPath'] as String;
    final before = j['before'] as String, after = j['after'] as String;
    _validate(oldPath);
    _validate(newPath);
    final old = await storage.readText(oldPath);
    final next = await storage.readText(newPath);
    if ((old != null && old != before && old != after) ||
        (next != null &&
            next != after &&
            !(protocolCaseFold(oldPath) == protocolCaseFold(newPath) &&
                next == before))) {
      throw StateError('personal-transaction-conflict');
    }
    // Remove target first: also safe on a case-insensitive native filesystem.
    if (newPath != oldPath && next != null) await storage.remove(newPath);
    if (await storage.readText(oldPath) != before) {
      await storage.writeText(oldPath, before);
    }
    await storage.remove(journalKey);
  }

  Future<void> edit(
      String oldPath, String newPath, String before, String after) async {
    _validate(oldPath);
    _validate(newPath);
    await recover();
    if (await storage.readText(oldPath) != before) {
      throw StateError('stale-personal-product');
    }
    final conflicts = (await storage.keys('user/产品列表/')).where((key) =>
        key != oldPath && protocolCaseFold(key) == protocolCaseFold(newPath));
    if (conflicts.isNotEmpty) throw StateError('个人产品名称已存在');
    await storage.writeText(
        journalKey,
        jsonEncode({
          'version': 1,
          'oldPath': oldPath,
          'newPath': newPath,
          'before': before,
          'after': after,
        }));
    try {
      final caseRename = oldPath != newPath &&
          protocolCaseFold(oldPath) == protocolCaseFold(newPath);
      if (caseRename) await storage.remove(oldPath);
      await storage.writeText(newPath, after);
      if (oldPath != newPath && !caseRename) await storage.remove(oldPath);
      await storage.remove(journalKey);
    } catch (_) {
      // Disk failure may also prevent rollback. Never erase its recovery record.
      try {
        await recover();
      } catch (_) {/* retry on next load/mutation */}
      rethrow;
    }
  }
}
