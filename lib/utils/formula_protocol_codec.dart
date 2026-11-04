import 'dart:convert';
import 'dart:typed_data';
import '../models/formula_document.dart';
import '../data_sync/protocol/rstone_protocol.dart' show parseUniqueJson;

/// Frozen byte/shape codec, independent of Flutter and of catalogue approval.
class FormulaProtocolCodec {
  /// Presence routing only. Reserved protocol keys (including escaped JSON
  /// keys) are fail-closed; ordinary old JSON/YAML metadata stays legacy.
  static bool hasStructuredMarker(String text) {
    final probe = text.replaceFirst(RegExp(r'^[\s\uFEFF]+'), '');
    if (!probe.startsWith('---')) return text.contains('rstone-recipe/');
    final end = probe.indexOf('\n---', 3);
    final h = probe.substring(3, end < 0 ? probe.length : end);
    if (RegExp(
            r'''rstone-recipe/|["']?(?:schema|recipeId|associatedProducts|ownerProduct)["']?\s*:''')
        .hasMatch(h)) {
      return true;
    }
    if (h.trimLeft().startsWith('{')) {
      if (h.length > maxHeader) return true;
      try {
        final value = parseUniqueJson(Uint8List.fromList(utf8.encode(h)));
        return value is Map &&
            const {'schema', 'recipeId', 'associatedProducts', 'ownerProduct'}
                .any(value.containsKey);
      } on FormatException {
        // Broken JSON frontmatter is isolated, never interpreted as a model
        // whose invalid metadata can silently grant a legacy fallback.
        return true;
      }
    }
    return false;
  }

  static FormulaDocument? readOptional(String text, {bool required = false}) =>
      required || hasStructuredMarker(text) ? decode(utf8.encode(text)) : null;

  static const maxFile = 16 * 1024 * 1024,
      maxHeader = 512 * 1024,
      maxDepth = 16;
  static FormulaDocument decode(List<int> raw) {
    _need(raw.length <= maxFile, 'structured-file-limit');
    _need(
        raw.length >= 4 &&
            raw[0] == 45 &&
            raw[1] == 45 &&
            raw[2] == 45 &&
            raw[3] == 10,
        'structured-envelope-required');
    final text = utf8.decode(raw, allowMalformed: false);
    _need(text.startsWith('---\n'), 'structured-envelope-required');
    final end = text.indexOf('\n---\n', 4);
    _need(end >= 4 && end - 4 <= maxHeader, 'structured-header-limit');
    final h = text.substring(4, end);
    _need(h.codeUnits.every((u) => u < 128 && u != 10 && u != 13),
        'structured-header-not-ascii-single-line');
    final dynamic value;
    try {
      value = parseUniqueJson(Uint8List.fromList(ascii.encode(h)));
    } on FormatException {
      throw const FormatException('invalid-structured-json');
    }
    _depth(value, 0);
    if (value is Map &&
        value['schema'] is String &&
        value['schema'] != FormulaDocument.schema) {
      throw const FormatException('unsupported-structured-schema');
    }
    final model = FormulaDocument.fromJson(value);
    _need(utf8.decode(encode(model)) == text,
        'noncanonical-envelope-or-display-mismatch');
    return model;
  }

  static Uint8List encode(FormulaDocument model) {
    final h = canonicalJson(model.toJson());
    _need(h.length <= maxHeader, 'structured-header-limit');
    final raw = utf8.encode('---\n$h\n---\n${body(model)}');
    _need(raw.length <= maxFile, 'structured-file-limit');
    return Uint8List.fromList(raw);
  }

  static String body(FormulaDocument model) {
    final lines = <String>['# ${entityText(model.title)}'];
    for (final p in model.preTable) {
      lines.addAll(['', entityText(p)]);
    }
    lines.addAll(
        ['', '## 配方', _row(model.columns), '| --- | --- | --- | --- | --- |']);
    lines.addAll(model.rows.map(_row));
    for (final block in model.content) {
      if (block is FormulaNote) {
        lines.addAll(['', entityText(block.text)]);
      }
      if (block is FormulaProcess) {
        lines.addAll([
          '',
          '## ${entityText(block.label)}',
          ...block.steps.map((s) => '- ${entityText(s)}')
        ]);
      }
    }
    return '${lines.join('\n')}\n';
  }

  static String entityText(String text) =>
      text.runes.map((r) => '&#x${r.toRadixString(16)};').join();
  static String _row(List<String> row) =>
      '| ${row.map(entityText).join(' | ')} |';

  /// Python json.dumps(ensure_ascii=True, sort_keys=True, separators=(',', ':')).
  static String canonicalJson(dynamic v) {
    if (v is String) {
      final out = StringBuffer('"');
      for (final u in v.codeUnits) {
        switch (u) {
          case 34:
            out.write(r'\"');
          case 92:
            out.write(r'\\');
          case 8:
            out.write(r'\b');
          case 9:
            out.write(r'\t');
          case 10:
            out.write(r'\n');
          case 12:
            out.write(r'\f');
          case 13:
            out.write(r'\r');
          default:
            if (u < 32 || u > 126) {
              out.write('\\u${u.toRadixString(16).padLeft(4, '0')}');
            } else {
              out.writeCharCode(u);
            }
        }
      }
      return '${out.toString()}"';
    }
    if (v is List) return '[${v.map(canonicalJson).join(',')}]';
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return '{${keys.map((k) => '${canonicalJson(k)}:${canonicalJson(v[k])}').join(',')}}';
    }
    // No business field admits numbers, bool or null.
    throw const FormatException('invalid-structured-json-value');
  }

  static void _depth(dynamic value, int depth) {
    _need(depth <= maxDepth, 'structured-depth-limit');
    if (value is Map) {
      for (final e in value.entries) {
        _depth(e.key, depth + 1);
        _depth(e.value, depth + 1);
      }
    } else if (value is List) {
      for (final v in value) {
        _depth(v, depth + 1);
      }
    }
  }

  static void _need(bool ok, String category) {
    if (!ok) throw FormatException(category);
  }
}
