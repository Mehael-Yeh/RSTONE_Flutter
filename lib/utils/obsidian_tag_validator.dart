class ObsidianTagValidator {
  const ObsidianTagValidator._();

  static final RegExp _validTagPattern = RegExp(
    r'^[\p{L}\p{N}_/-]+$',
    unicode: true,
  );

  static final RegExp _hasNonDigitPattern = RegExp(
    r'[^\p{N}]',
    unicode: true,
  );

  static List<String> splitSpaceSeparated(String input) {
    return input
        .trim()
        .split(RegExp(r'\s+'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  static List<String> validateAndNormalizeTags(Iterable<String> rawTags) {
    final normalized = <String>[];
    for (final rawTag in rawTags) {
      final tag = rawTag.trim();
      final error = validationError(tag);
      if (error != null) {
        throw ArgumentError(error);
      }
      if (tag.isNotEmpty) {
        normalized.add(tag.startsWith('#') ? tag.substring(1) : tag);
      }
    }
    return normalized;
  }

  static String? validationError(String rawTag) {
    final tag = rawTag.trim();
    if (tag.isEmpty) return null;
    final normalized = tag.startsWith('#') ? tag.substring(1) : tag;
    if (normalized.isEmpty) {
      return '标签“$rawTag”不能只有 #';
    }
    if (normalized.contains('#')) {
      return '标签“$rawTag”只能在开头使用 #';
    }
    if (normalized.contains(',') || normalized.contains('，')) {
      return '标签“$rawTag”不能包含逗号，请用空格分隔多个标签';
    }
    if (normalized.startsWith('/') ||
        normalized.endsWith('/') ||
        normalized.contains('//')) {
      return '标签“$rawTag”的 / 只能用于分隔嵌套标签';
    }
    if (!_validTagPattern.hasMatch(normalized)) {
      return '标签“$rawTag”只能包含字母、数字、下划线、连字符或正斜杠';
    }
    if (!_hasNonDigitPattern.hasMatch(normalized)) {
      return '标签“$rawTag”必须至少包含一个非数字字符';
    }
    return null;
  }
}
