import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../../models/formula_document.dart';
import '../../utils/formula_table_clipboard_parser.dart';

/// Display-only projection; never used for facts, protocol emit or clipboard.
/// Only the explicitly approved bilingual pair is deduplicated.
String formulaDisplayText(String text) => text.replaceAllMapped(
    RegExp(r'去离子水[ \t]*(?:（[ \t]*DI water[ \t]*）|\([ \t]*DI water[ \t]*\))',
        caseSensitive: false),
    (_) => '去离子水');

List<({String text, String? target})> formulaDisplayParts(
    String text, List<String> associated) {
  final parts = <({String text, String? target})>[];
  var cursor = 0;
  while (cursor < text.length) {
    final open = text.indexOf('[[', cursor);
    final close = open < 0 ? -1 : text.indexOf(']]', open + 2);
    if (open < 0 || close < 0) {
      parts.add(
          (text: formulaDisplayText(text.substring(cursor)), target: null));
      break;
    }
    if (open > cursor) {
      parts.add((
        text: formulaDisplayText(text.substring(cursor, open)),
        target: null
      ));
    }
    var target = text.substring(open + 2, close);
    if (target.startsWith('产品列表/')) target = target.substring('产品列表/'.length);
    final valid =
        RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(target) &&
            associated.contains(target) &&
            (open == 0 || (text[open - 1] != '[' && text[open - 1] != r'\')) &&
            (close + 2 == text.length || text[close + 2] != ']');
    parts.add((
      text: valid ? target : text.substring(open, close + 2),
      target: valid ? target : null
    ));
    cursor = close + 2;
  }
  return parts;
}

final class FormulaDisplayView {
  final FormulaDocument document;
  final List<List<String>> cells;
  FormulaDisplayView(this.document)
      : cells = List.unmodifiable([
          document.columns,
          for (final row in document.rows)
            List<String>.unmodifiable([
              formulaDisplayParts(row[0], document.associatedProducts)
                  .map((p) => p.text)
                  .join(),
              ...row.skip(1).map(formulaDisplayText),
            ]),
        ]);
  String get tsv =>
      FormulaTableClipboardParser.toTsv(document.columns, document.rows);
}

/// Exact five-column geometry used by both the widget and PNG painter.
final class FormulaTableLayout {
  static const cellPadding = 10.0;
  static const style = TextStyle(
      inherit: false, fontFamily: 'sans-serif', fontSize: 12, height: 1.4);
  final FormulaDisplayView view;
  final List<double> widths, heights;
  FormulaTableLayout._(this.view, this.widths, this.heights);
  double get width => widths.fold(0, (a, b) => a + b);
  double get height => heights.fold(0, (a, b) => a + b);
  factory FormulaTableLayout(FormulaDisplayView view,
      {double firstColumnMax = 280}) {
    final widths = List<double>.filled(5, 88);
    for (final row in view.cells) {
      for (var c = 0; c < 5; c++) {
        final p = painter(row[c], identical(row, view.cells.first));
        p.layout();
        widths[c] =
            math.max(widths[c], (p.width + cellPadding * 2).clamp(88, 280));
        p.dispose();
      }
    }
    widths[0] = math.min(widths[0], firstColumnMax);
    final heights = <double>[];
    for (var r = 0; r < view.cells.length; r++) {
      var height = 36.0;
      for (var c = 0; c < 5; c++) {
        final p = painter(view.cells[r][c], r == 0);
        p.layout(maxWidth: widths[c] - cellPadding * 2 - 1);
        // Container's 0.5px border contributes to its inner padding on both sides.
        height = math.max(height, (p.height + 17).ceilToDouble());
        p.dispose();
      }
      heights.add(height);
    }
    return FormulaTableLayout._(
        view, List.unmodifiable(widths), List.unmodifiable(heights));
  }
  static TextPainter painter(String text, bool bold,
          {Color color = const Color(0xff111111)}) =>
      TextPainter(
          text: TextSpan(
              text: text,
              style: style.copyWith(
                  color: color,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          textDirection: TextDirection.ltr);
}
