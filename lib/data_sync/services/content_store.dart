import 'dart:typed_data';
import '../protocol/rstone_protocol.dart';
import '../storage/storage_adapter.dart';
import 'integrity_verifier.dart';

class ContentStore {
  final StorageAdapter storage;
  final Map<String, String> _verifiedFingerprints = {};
  ContentStore(this.storage);
  String key(String hash) => 'official/objects/$hash';

  Future<bool> containsValid(DataFile file, {bool full = false}) async {
    final token = await storage.fingerprint(key(file.sha256));
    final identity = '${file.size}:$token';
    if (!full &&
        token != null &&
        _verifiedFingerprints[file.sha256] == identity) {
      return true;
    }
    final bytes = await storage.read(key(file.sha256));
    if (bytes == null || !await verifyContent(file, bytes)) {
      _verifiedFingerprints.remove(file.sha256);
      return false;
    }
    if (token != null) _verifiedFingerprints[file.sha256] = identity;
    return true;
  }

  Future<void> save(DataFile file, Uint8List bytes) async {
    if (!await verifyContent(file, bytes)) {
      throw const FormatException('对象内容校验失败');
    }
    await storage.write(key(file.sha256), bytes);
    // Read back before a generation can reference it (disk full / write faults).
    if (!await containsValid(file, full: true)) throw StateError('保存后的数据校验失败');
  }

  Future<Set<String>> validHashes(Iterable<DataFile> files,
      {bool full = false}) async {
    final valid = <String>{}, checked = <String>{};
    for (final file in files) {
      if (checked.add(file.sha256) && await containsValid(file, full: full)) {
        valid.add(file.sha256);
      }
    }
    return valid;
  }
}
