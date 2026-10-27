/// TDS 牌号匹配：仅比较完整牌号字符串。
///
/// 大小写与首尾空白的差异不带语义，予以忽略；连字符、字母、数字、点号等
/// 后缀一律保留，不做去后缀、去标点或 RD/RS 互换。
String gradeLookupKey(String raw) => raw.trim().toLowerCase();

/// 在按相对路径（已去除 `.TDS.md`）索引的 TDS 映射中查找 [grade]。
///
/// 同一牌号出现在多个子目录时视为歧义，返回 null，绝不猜测其中一个。
String? findExactTds(Map<String, String> tdsByPath, String grade) {
  final key = gradeLookupKey(grade);
  final matches = <String>[];
  for (final entry in tdsByPath.entries) {
    final basename = entry.key.split('/').last;
    if (gradeLookupKey(basename) == key) matches.add(entry.value);
  }
  return matches.length == 1 ? matches.single : null;
}
