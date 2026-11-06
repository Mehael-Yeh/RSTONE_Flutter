import 'dart:convert';

import '../data_sync/protocol/rstone_protocol.dart';
import '../data_sync/protocol/src/casefold.dart';
import '../data_sync/storage/storage_adapter.dart';
import 'preferences_service.dart';

/// Single-writer undo journal. Clearing the journal is the commit point.
/// A pending journal is rolled back before loading or accepting another edit.
/// If recovery cannot complete, the journal remains and mutations fail closed.
class PersonalProductTransaction {
  static const journalKey = 'user/transactions/product-edit.json';
  final StorageAdapter storage;
  final PreferencesService? preferences;
  PersonalProductTransaction(this.storage, {this.preferences});

  Future<PreferencesService> _notes() async {
    final prefs = preferences ?? PreferencesService();
    await prefs.initialize();
    return prefs;
  }

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
    if (j['version'] != 1 && j['version'] != 2) {
      throw StateError('unknown-personal-transaction');
    }
    final noteChange = j['version'] == 2
        ? ProductNoteChange.fromJson(j['notes'] as Map<String, dynamic>)
        : null;
    final oldPath = j['oldPath'] as String, newPath = j['newPath'] as String;
    final before = j['before'] as String, after = j['after'] as String;
    _validate(oldPath);
    _validate(newPath);
    // readText decodes away a UTF-8 BOM. Compare the exact stored bytes
    // against journal text encoded back to bytes, including any original BOM.
    final beforeBytes = utf8.encode(before), afterBytes = utf8.encode(after);
    final old = await storage.read(oldPath);
    final next = await storage.read(newPath);
    if ((old != null &&
            !sameBytes(old, beforeBytes) &&
            !sameBytes(old, afterBytes)) ||
        (next != null &&
            !sameBytes(next, afterBytes) &&
            !(protocolCaseFold(oldPath) == protocolCaseFold(newPath) &&
                sameBytes(next, beforeBytes)))) {
      throw StateError('personal-transaction-conflict');
    }
    // Check both stores before modifying either. Unexpected later annotations
    // leave the journal intact and recovery fails closed rather than erasing.
    if (noteChange != null) {
      await (await _notes()).applyProductNoteChange(noteChange, rollback: true);
    }
    // Remove target first: also safe on a case-insensitive native filesystem.
    if (newPath != oldPath && next != null) await storage.remove(newPath);
    if (!sameBytes(await storage.read(oldPath), beforeBytes)) {
      await storage.writeText(oldPath, before);
    }
    await storage.remove(journalKey);
  }

  Future<void> edit(
      String oldPath, String newPath, String before, String after,
      {ProductNoteChange? noteChange}) async {
    _validate(oldPath);
    _validate(newPath);
    await recover();
    if (!sameBytes(await storage.read(oldPath), utf8.encode(before))) {
      throw StateError('stale-personal-product');
    }
    final conflicts = (await storage.keys('user/产品列表/')).where((key) =>
        key != oldPath && protocolCaseFold(key) == protocolCaseFold(newPath));
    if (conflicts.isNotEmpty) throw StateError('个人产品名称已存在');
    await storage.writeText(
        journalKey,
        jsonEncode({
          'version': noteChange == null ? 1 : 2,
          'oldPath': oldPath,
          'newPath': newPath,
          'before': before,
          'after': after,
          if (noteChange != null) 'notes': noteChange.toJson(),
        }));
    try {
      final caseRename = oldPath != newPath &&
          protocolCaseFold(oldPath) == protocolCaseFold(newPath);
      if (caseRename) await storage.remove(oldPath);
      await storage.writeText(newPath, after);
      if (oldPath != newPath && !caseRename) await storage.remove(oldPath);
      // File rename must succeed first. The existing journal remains the undo
      // record until the guarded, single-value note write also succeeds.
      if (noteChange != null) {
        await (await _notes()).applyProductNoteChange(noteChange, rollback: false);
      }
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
