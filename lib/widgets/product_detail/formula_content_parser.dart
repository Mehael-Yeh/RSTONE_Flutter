/// 配方展示结构。
///
/// 将原始 Markdown 拆解为：
/// - [preTableContent]：表格前的说明文本
/// - [postTableContent]：表格后的补充文本
/// - [tableMarkdownBody]：仅保留 body 的 Markdown（去 frontmatter）
class FormulaDisplayContent {
  final String preTableContent;
  final String postTableContent;
  final String tableMarkdownBody;

  const FormulaDisplayContent({
    required this.preTableContent,
    required this.postTableContent,
    required this.tableMarkdownBody,
  });

  /// 方便分享图片时合并表格上下文说明。
  String get combinedExtraContent => [
        if (preTableContent.isNotEmpty) preTableContent,
        if (postTableContent.isNotEmpty) postTableContent,
      ].join('\n');
}

/// 负责解析配方 Markdown 的轻量工具。
///
/// 目的：把 UI 组件内的文本解析逻辑拆离，降低 `ProductDetailSheet`
/// 中单个方法的复杂度，便于单元测试和复用。
class FormulaContentParser {
  const FormulaContentParser._();

  /// 提取 frontmatter 之后的正文。
  static String extractMarkdownBody(String rawContent) {
    final normalized = rawContent.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) {
      return normalized.trim();
    }

    final endIndex = normalized.indexOf('\n---\n', 4);
    if (endIndex == -1) {
      return normalized.trim();
    }
    return normalized.substring(endIndex + 5).trim();
  }

  /// 解析配方内容，输出用于 UI 展示的数据结构。
  static FormulaDisplayContent parse(String rawContent) {
    final preTableLines = <String>[];
    final postTableLines = <String>[];
    var foundTable = false;
    var inFrontmatter = false;
    var frontmatterEnded = false;

    for (final line in rawContent.split('\n')) {
      final trimmed = line.trim();

      // 跟踪 frontmatter 边界
      if (trimmed == '---') {
        if (!inFrontmatter) {
          inFrontmatter = true;
        } else {
          frontmatterEnded = true;
          inFrontmatter = false;
        }
        continue;
      }

      if (inFrontmatter || trimmed.isEmpty) continue;

      // frontmatter 结束后，单独成行的 wiki 链接通常是跳转辅助信息，不在详情中展示。
      if (frontmatterEnded && RegExp(r'^\s*\[\[[^\]]+\]\]\s*$').hasMatch(trimmed)) {
        continue;
      }

      if (trimmed.startsWith('|')) {
        foundTable = true;
        continue;
      }

      var clean = trimmed.startsWith('> ') ? trimmed.substring(2).trim() : trimmed;
      clean = clean.replaceAllMapped(RegExp(r'\[\[([^\]]+)\]\]'), (m) => m.group(1) ?? clean);

      if (foundTable) {
        postTableLines.add(clean);
      } else {
        preTableLines.add(clean);
      }
    }

    return FormulaDisplayContent(
      preTableContent: preTableLines.join('\n'),
      postTableContent: postTableLines.join('\n'),
      tableMarkdownBody: extractMarkdownBody(rawContent),
    );
  }
}
