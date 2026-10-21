import 'dart:convert';
import 'dart:typed_data';

/// All keys are internal relative paths. Official logical paths never address
/// the filesystem: only their SHA-256 objects do.
abstract class StorageAdapter {
  static const activeKey = 'official/active';
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
  Future<void> remove(String key);
  Future<List<String>> keys(String prefix);
  Future<String?> fingerprint(String key);

  /// Compare and swap the entire signed generation and replay watermark in one
  /// durable transaction. Objects must be flushed before calling this.
  Future<void> commitActive(Uint8List? expected, Uint8List next);
  Future<void> close();

  Future<String?> readText(String key) async {
    final bytes = await read(key);
    return bytes == null ? null : utf8.decode(bytes);
  }

  Future<void> writeText(String key, String text) =>
      write(key, Uint8List.fromList(utf8.encode(text)));
}

void validateStorageKey(String key) {
  if (key.isEmpty ||
      key.startsWith('/') ||
      key.contains('\\') ||
      key.split('/').any((p) => p.isEmpty || p == '.' || p == '..') ||
      RegExp(r'[\x00-\x1f<>:"|?*]').hasMatch(key)) {
    throw ArgumentError('Unsafe storage key');
  }
}

bool sameBytes(List<int>? a, List<int>? b) =>
    a == null || b == null ? a == b : base64Encode(a) == base64Encode(b);
