/// Converts formula tables copied from Markdown or spreadsheet apps into a
/// validated Markdown table string.
class FormulaTableClipboardParser {
  FormulaTableClipboardParser._();

  static FormulaTableParseResult parse(String input) {
    final normalized = input
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (normalized.isEmpty) {
      return const FormulaTableParseResult.failure('剪切板为空，请先复制配方表格');
    }

    final markdown = _parseMarkdownTable(normalized);
    if (markdown != null) return markdown;

    final spreadsheet = _parseSpreadsheetTable(normalized);
    if (spreadsheet != null) return spreadsheet;

    return const FormulaTableParseResult.failure(
      '未识别到有效表格，请复制包含“原料编号、投入数、百分比”等列的 Markdown 表格或 Excel 表格',
    );
  }

  static FormulaTableParseResult? _parseMarkdownTable(String input) {
    final lines = input
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length < 3 || !lines.every((line) => line.contains('|'))) {
      return null;
    }

    final rows = lines
        .map(_splitMarkdownRow)
        .where((row) => row.isNotEmpty)
        .toList();
    if (rows.length < 3 || !_isMarkdownSeparatorRow(rows[1])) return null;

    final header = rows.first;
    final dataRows = rows.skip(2).toList();
    return _validateAndBuild(header, dataRows);
  }

  static FormulaTableParseResult? _parseSpreadsheetTable(String input) {
    final lines = input
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2 || !lines.any((line) => line.contains('\t'))) {
      return null;
    }

    final rows = lines
        .map((line) => line.split('\t').map((cell) => cell.trim()).toList())
        .toList();
    final header = rows.first;
    final dataRows = rows.skip(1).toList();
    return _validateAndBuild(header, dataRows);
  }

  static FormulaTableParseResult _validateAndBuild(
    List<String> header,
    List<List<String>> dataRows,
  ) {
    final normalizedHeader = header.map((cell) => cell.trim()).toList();
    if (normalizedHeader.length < 3 || !_hasRequiredHeaders(normalizedHeader)) {
      return const FormulaTableParseResult.failure(
        '表头无效：至少需要包含原料编号、投入数和百分比列',
      );
    }

    final width = normalizedHeader.length;
    final normalizedRows = <List<String>>[];
    for (final row in dataRows) {
      final normalizedRow = _normalizeWidth(row, width);
      if (normalizedRow.every((cell) => cell.trim().isEmpty)) continue;
      normalizedRows.add(normalizedRow);
    }

    if (normalizedRows.isEmpty) {
      return const FormulaTableParseResult.failure('表格无效：未找到配方明细行');
    }

    final invalidRowIndex = normalizedRows.indexWhere(
      (row) => row.first.trim().isEmpty,
    );
    if (invalidRowIndex >= 0) {
      return FormulaTableParseResult.failure(
        '第 ${invalidRowIndex + 1} 行原料编号为空，请检查表格内容',
      );
    }

    final amountIndex = _findHeaderIndex(
      normalizedHeader,
      const ['投入', '用量', '重量'],
    );
    if (amountIndex != -1) {
      final invalidAmountIndex = normalizedRows.indexWhere(
        (row) => !_looksLikeNumber(row[amountIndex]),
      );
      if (invalidAmountIndex >= 0) {
        return FormulaTableParseResult.failure(
          '第 ${invalidAmountIndex + 1} 行投入数无效，请检查表格内容',
        );
      }
    }

    final percentIndex = _findHeaderIndex(
      normalizedHeader,
      const ['百分比', '比例', '%'],
    );
    if (percentIndex != -1) {
      final invalidPercentIndex = normalizedRows.indexWhere(
        (row) => !_looksLikeNumber(row[percentIndex]),
      );
      if (invalidPercentIndex >= 0) {
        return FormulaTableParseResult.failure(
          '第 ${invalidPercentIndex + 1} 行百分比无效，请检查表格内容',
        );
      }
    }

    return FormulaTableParseResult.success(
      _buildMarkdownTable(normalizedHeader, normalizedRows),
    );
  }

  static List<String> _splitMarkdownRow(String line) {
    var row = line.trim();
    if (row.startsWith('|')) row = row.substring(1);
    if (row.endsWith('|')) row = row.substring(0, row.length - 1);
    return row.split('|').map((cell) => cell.trim()).toList();
  }

  static bool _isMarkdownSeparatorRow(List<String> row) {
    if (row.isEmpty) return false;
    return row.every(
      (cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell.replaceAll(' ', '')),
    );
  }

  static bool _hasRequiredHeaders(List<String> header) {
    final hasMaterial = _findHeaderIndex(header, const ['原料']) != -1;
    final hasAmount = _findHeaderIndex(header, const ['投入', '用量', '重量']) != -1;
    final hasPercent = _findHeaderIndex(header, const ['百分比', '比例', '%']) != -1;
    return hasMaterial && hasAmount && hasPercent;
  }

  static int _findHeaderIndex(List<String> header, List<String> keywords) {
    return header.indexWhere((cell) => keywords.any(cell.contains));
  }

  static List<String> _normalizeWidth(List<String> row, int width) {
    final normalized = row.map((cell) => cell.trim()).toList();
    if (normalized.length > width) return normalized.take(width).toList();
    return [...normalized, ...List.filled(width - normalized.length, '')];
  }

  static bool _looksLikeNumber(String value) {
    final normalized = value.trim().replaceAll(',', '').replaceAll('%', '');
    if (normalized.isEmpty) return false;
    return double.tryParse(normalized) != null;
  }

  static String _buildMarkdownTable(
    List<String> header,
    List<List<String>> rows,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('| ${header.map(_escapeMarkdownCell).join(' | ')} |');
    buffer.writeln('| ${header.map((_) => '---').join(' | ')} |');
    for (final row in rows) {
      buffer.writeln('| ${row.map(_escapeMarkdownCell).join(' | ')} |');
    }
    return buffer.toString().trimRight();
  }

  static String _escapeMarkdownCell(String cell) {
    return cell.trim().replaceAll('|', r'\|');
  }
}

class FormulaTableParseResult {
  final bool isValid;
  final String? markdown;
  final String? errorMessage;

  const FormulaTableParseResult._({
    required this.isValid,
    this.markdown,
    this.errorMessage,
  });

  const FormulaTableParseResult.success(String markdown)
      : this._(isValid: true, markdown: markdown);

  const FormulaTableParseResult.failure(String errorMessage)
      : this._(isValid: false, errorMessage: errorMessage);
}
