/// 统一处理 Markdown 文本中与表格相关的解析逻辑。
class MarkdownTableParser {
  const MarkdownTableParser._();

  /// 将 Obsidian 风格 wiki 链接（[[XXX]]）转换为纯文本（XXX）。
  static String normalizeWikiLinks(String content) {
    return content.replaceAllMapped(
      RegExp(r'\[\[([^\]]+)\]\]'),
      (m) => m.group(1) ?? m.group(0) ?? '',
    );
  }

  /// 解析 markdown 表格数据。
  ///
  /// [rawContent] 可包含多张表格和普通文本。
  /// [nonTableContent] 若传入，则会收集非表格行（如 blockquote）。
  static List<List<String>> parseTable(
    String rawContent, [
    List<String>? nonTableContent,
  ]) {
    final rows = <List<String>>[];

    for (final line in rawContent.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (!trimmed.startsWith('|')) {
        if (nonTableContent != null) {
          nonTableContent.add(trimmed);
        }
        continue;
      }

      var isSeparator = true;
      for (final cell in trimmed.split('|')) {
        final cellText = cell.trim();
        if (cellText.isNotEmpty && !RegExp(r'^[-:]+$').hasMatch(cellText)) {
          isSeparator = false;
          break;
        }
      }

      // 仅跳过表头之后的分隔线，避免首行被误判。
      if (isSeparator && rows.isNotEmpty) continue;

      final columns = trimmed.split('|').map((cell) {
        return normalizeWikiLinks(cell.trim());
      }).toList();

      // 去掉由首尾 "|" 引入的空列。
      while (columns.isNotEmpty && columns.first.isEmpty) {
        columns.removeAt(0);
      }
      while (columns.isNotEmpty && columns.last.isEmpty) {
        columns.removeLast();
      }

      if (columns.isNotEmpty) {
        rows.add(columns);
      }
    }

    return rows;
  }
}
