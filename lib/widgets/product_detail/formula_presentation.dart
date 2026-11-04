import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../../models/formula_document.dart';
import '../../utils/formula_table_clipboard_parser.dart';

/// Deliberately displays the ORIGINAL strings, including [[wiki|alias]]. No
/// link normalization, trimming, entity parsing or second Markdown fact source.
final class FormulaDisplayView {
  final FormulaDocument document;
  final List<List<String>> cells;
  FormulaDisplayView(this.document)
      : cells = List.unmodifiable([document.columns, ...document.rows]);
  String get tsv =>
      FormulaTableClipboardParser.toTsv(document.columns, document.rows);
}

/// Exact five-column geometry used by both the widget and PNG painter.
final class FormulaTableLayout {
  static const cellPadding = 10.0;
  static const style =
      TextStyle(fontFamily: 'sans-serif', fontSize: 12, height: 1.4);
  final FormulaDisplayView view;
  final List<double> widths, heights;
  FormulaTableLayout._(this.view, this.widths, this.heights);
  double get width => widths.fold(0, (a, b) => a + b);
  double get height => heights.fold(0, (a, b) => a + b);
  factory FormulaTableLayout(FormulaDisplayView view) {
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
    final heights = <double>[];
    for (var r = 0; r < view.cells.length; r++) {
      var height = 36.0;
      for (var c = 0; c < 5; c++) {
        final p = painter(view.cells[r][c], r == 0);
        p.layout(maxWidth: widths[c] - cellPadding * 2);
        height = math.max(height, p.height + 16);
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
