import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../protocol/rstone_protocol.dart';
import 'storage_adapter.dart';

/// Copy only; legacy originals and SharedPreferences are never removed.
/// Unmarked legacy files remain in their original directory. Only explicitly
/// marked personal files are imported; old official assets never reappear.
Future<void> migrateLegacyData(StorageAdapter storage,
    {Directory? legacyRoot}) async {
  if (await storage.read('migration/v1') != null) return;
  legacyRoot ??=
      Directory('${(await getApplicationDocumentsDirectory()).path}/rst_data');
  final meta = File('${legacyRoot.path}/manual_items.json');
  Map<String, dynamic> manual = {};
  if (await meta.exists()) {
    final value = jsonDecode(await meta.readAsString());
    if (value is! Map<String, dynamic>) {
      throw const FormatException('旧版新增资料清单无效，原文件已保留');
    }
    manual = value;
  }
  final imported = <String>[];
  for (final pair in {
    '产品列表': 'products',
    '产品应用': 'applications',
    '产品配方': 'formulas'
  }.entries) {
    final marked = ((manual[pair.value] as List?) ?? [])
        .whereType<String>()
        .map((s) => pair.key == '产品列表' ? s.toUpperCase() : s)
        .toSet();
    if (marked.isEmpty) continue;
    final dir = Directory('${legacyRoot.path}/${pair.key}');
    if (!await dir.exists()) continue;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      final relative =
          entity.path.substring(dir.path.length + 1).replaceAll('\\', '/');
      final path = '${pair.key}/$relative';
      final name = relative.substring(0, relative.length - 3);
      final explicitUser =
          marked.contains(pair.key == '产品列表' ? name.toUpperCase() : name);
      if (!explicitUser) continue;
      validateLogicalPath(path);
      final destination = 'user/$path';
      if (await storage.read(destination) == null) {
        await storage.write(destination, await entity.readAsBytes());
      }
      imported.add(path);
    }
  }
  final rules = File('${legacyRoot.path}/tag_alias_rules.custom.txt');
  if (await rules.exists() &&
      await storage.read('user/custom_rules/tag_alias_rules.custom.txt') ==
          null) {
    await storage.write('user/custom_rules/tag_alias_rules.custom.txt',
        await rules.readAsBytes());
  }
  // Marker is last. Re-running after a crash never duplicates or overwrites.
  await storage.writeText('migration/v1', jsonEncode({'imported': imported}));
}
