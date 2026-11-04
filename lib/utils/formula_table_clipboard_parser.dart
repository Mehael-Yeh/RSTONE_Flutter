/// User-input adapter, not an official facts parser. Raw cells remain strings.
class FormulaTableClipboardParser {
  FormulaTableClipboardParser._();
  static FormulaTableParseResult parse(String input) {
    if (input.trim().isEmpty) {
      return const FormulaTableParseResult.failure('剪切板为空，请先复制配方表格');
    }
    try {
      final text = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final List<List<String>> records;
      if (text.trimLeft().startsWith('|')) {
        final lines = text.split('\n');
        while (lines.isNotEmpty && lines.first.trim().isEmpty) {
          lines.removeAt(0);
        }
        while (lines.isNotEmpty && lines.last.trim().isEmpty) {
          lines.removeLast();
        }
        if (lines.length < 3) throw const FormatException('表格无效');
        final parsed = lines.map(_markdownRow).toList();
        if (!parsed[1]
            .every((c) => RegExp(r'^:?-{3,}:?$').hasMatch(c.trim()))) {
          throw const FormatException('表格分隔行无效');
        }
        records = [parsed.first, ...parsed.skip(2)];
      } else {
        records = _tsv(text);
      }
      if (records.length < 2) throw const FormatException('表格明细为空');
      final originalHeader = records.first;
      final header = originalHeader.map((h) => h.trim()).toList();
      if (header.length != 5 ||
          header[0] != '原料编号' ||
          !const {'投入数', '投入数(g)', '投入数（g)'}.contains(header[1]) ||
          header[2] != '百分比(%)' ||
          header[3] != '供应商' ||
          header[4] != '备注') {
        throw const FormatException('表头无效：需完整五列原料编号、投入数、百分比、供应商、备注');
      }
      final rows = records.skip(1).toList();
      for (final row in rows) {
        if (row.length != 5) {
          throw const FormatException('行宽无效：每行必须恰好五列，不补列或截列');
        }
        if (row[0].isEmpty || row[1].isEmpty) {
          throw const FormatException('原料编号与投入数不能为空');
        }
      }
      final columns = [...header];
      if (columns[1] == '投入数（g)') columns[1] = '投入数(g)';
      return FormulaTableParseResult._success(header, columns, rows);
    } on FormatException catch (e) {
      return FormulaTableParseResult.failure(e.message);
    }
  }

  static List<String> _markdownRow(String line) {
    var text = line.trim();
    if (!text.startsWith('|') || !text.endsWith('|')) {
      throw const FormatException('Markdown行需首尾分隔符');
    }
    text = text.substring(1, text.length - 1);
    final cells = <String>[];
    var cell = StringBuffer();
    var wiki = false;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == r'\' &&
          i + 1 < text.length &&
          (text[i + 1] == '|' || text[i + 1] == r'\')) {
        cell.write(text[++i]);
      } else if (text.startsWith('[[', i)) {
        wiki = true;
        cell.write('[[');
        i++;
      } else if (text.startsWith(']]', i)) {
        wiki = false;
        cell.write(']]');
        i++;
      } else if (text[i] == '|' && !wiki) {
        cells.add(_unpad(cell.toString()));
        cell = StringBuffer();
      } else {
        cell.write(text[i]);
      }
    }
    cells.add(_unpad(cell.toString()));
    return cells;
  }

  // One syntactic padding space, not arbitrary business whitespace.
  static String _unpad(String s) {
    if (s.startsWith(' ')) s = s.substring(1);
    if (s.endsWith(' ')) s = s.substring(0, s.length - 1);
    return s;
  }

  static List<List<String>> _tsv(String text) {
    final records = <List<String>>[];
    var row = <String>[], cell = StringBuffer();
    var quoted = false, closed = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
            closed = true;
          }
        } else {
          cell.write(c);
        }
      } else if (c == '\t' || c == '\n') {
        row.add(cell.toString());
        cell = StringBuffer();
        closed = false;
        if (c == '\n') {
          records.add(row);
          row = [];
        }
      } else if (c == '"' && cell.isEmpty && !closed) {
        quoted = true;
      } else {
        if (closed) throw const FormatException('引号单元格后有额外字符');
        cell.write(c);
      }
    }
    if (quoted) throw const FormatException('未结束的引号单元格');
    if (cell.isNotEmpty || row.isNotEmpty || closed) {
      row.add(cell.toString());
      records.add(row);
    }
    return records;
  }

  static String toTsv(List<String> columns, List<List<String>> rows) =>
      [columns, ...rows]
          .map((row) => row
              .map((s) => s.contains(RegExp('[\\t\\n"]'))
                  ? '"${s.replaceAll('"', '""')}"'
                  : s)
              .join('\t'))
          .join('\n');
}

class FormulaTableParseResult {
  final bool isValid;
  final String? errorMessage;
  final List<String> columns;
  final List<List<String>> rows;
  final List<String> _inputHeader;
  const FormulaTableParseResult.failure(String message)
      : isValid = false,
        errorMessage = message,
        columns = const [],
        rows = const [],
        _inputHeader = const [];
  FormulaTableParseResult._success(
      List<String> header, List<String> columns, List<List<String>> rows)
      : isValid = true,
        errorMessage = null,
        _inputHeader = List.unmodifiable(header),
        columns = List.unmodifiable(columns),
        rows = List.unmodifiable(rows.map((r) => List<String>.unmodifiable(r)));

  /// Lossless editable interchange, including quoted TAB/LF and trailing cells.
  String get tsv => FormulaTableClipboardParser.toTsv(columns, rows);

  /// Legacy display-only convenience; never parse this to determine facts.
  String? get markdown => !isValid
      ? null
      : [
          '| ${_inputHeader.join(' | ')} |',
          '| --- | --- | --- | --- | --- |',
          ...rows.map((r) =>
              '| ${r.map((s) => s.replaceAll(r'\', r'\\').replaceAll('|', r'\|')).join(' | ')} |')
        ].join('\n');
}
