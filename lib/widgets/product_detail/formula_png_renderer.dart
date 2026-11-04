import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../models/formula_document.dart';
import 'formula_presentation.dart';

final class FormulaPaintText {
  final String text;
  final ui.Rect rect;
  final bool bold;
  const FormulaPaintText(this.text, this.rect, this.bold);
}

final class FormulaPngLayout {
  final FormulaTableLayout table;
  final List<FormulaPaintText> text;
  final double width, height, tableTop;
  const FormulaPngLayout(
      this.table, this.text, this.width, this.height, this.tableTop);
}

/// Full-content Canvas export. Does not capture a scrolled/clipped widget.
class FormulaPngRenderer {
  static FormulaPngLayout layout(FormulaDisplayView view) {
    final table = FormulaTableLayout(view);
    final nodes = <FormulaPaintText>[];
    final width = table.width + 24;
    var y = 12.0;
    void paragraph(String text, {bool bold = false}) {
      final p = FormulaTableLayout.painter(text, bold)
        ..layout(maxWidth: width - 24);
      nodes.add(FormulaPaintText(
          text, ui.Rect.fromLTWH(12, y, width - 24, p.height), bold));
      y += p.height + 12;
      p.dispose();
    }

    paragraph('配方：${view.document.title}', bold: true);
    for (final p in view.document.preTable) {
      paragraph(p);
    }
    final top = y;
    for (var r = 0; r < view.cells.length; r++) {
      var x = 12.0;
      for (var c = 0; c < 5; c++) {
        final p = FormulaTableLayout.painter(view.cells[r][c], r == 0)
          ..layout(
              maxWidth: table.widths[c] - FormulaTableLayout.cellPadding * 2);
        nodes.add(FormulaPaintText(
            view.cells[r][c],
            ui.Rect.fromLTWH(
                x + FormulaTableLayout.cellPadding,
                y + (table.heights[r] - p.height) / 2,
                table.widths[c] - FormulaTableLayout.cellPadding * 2,
                p.height),
            r == 0));
        x += table.widths[c];
        p.dispose();
      }
      y += table.heights[r];
    }
    y += 12;
    for (final b in view.document.content) {
      if (b is FormulaNote) {
        paragraph(b.text);
      }
      if (b is FormulaProcess) {
        paragraph(b.label, bold: true);
        for (final s in b.steps) {
          paragraph(s);
        }
      }
    }
    return FormulaPngLayout(table, List.unmodifiable(nodes), width, y, top);
  }

  static Future<Uint8List> render(FormulaDisplayView view) async {
    final plan = layout(view);
    const scale = 2.0;
    final width = (plan.width * scale).ceil(),
        height = (plan.height * scale).ceil();
    if (width > 32768 || height > 32768 || width * height > 64000000) {
      // Explicit refusal instead of dropping rows, content or reducing columns.
      throw const FormatException('recipe-image-resource-limit');
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale, scale);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, plan.width, plan.height),
        ui.Paint()..color = const ui.Color(0xffffffff));
    var y = plan.tableTop;
    for (var r = 0; r < view.cells.length; r++) {
      var x = 12.0;
      for (var c = 0; c < 5; c++) {
        final rect =
            ui.Rect.fromLTWH(x, y, plan.table.widths[c], plan.table.heights[r]);
        canvas.drawRect(
            rect,
            ui.Paint()
              ..color = r == 0
                  ? const ui.Color(0xffe8edf3)
                  : const ui.Color(0xffffffff));
        canvas.drawRect(
            rect,
            ui.Paint()
              ..color = const ui.Color(0xffaaaaaa)
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = 0.5);
        x += plan.table.widths[c];
      }
      y += plan.table.heights[r];
    }
    for (final n in plan.text) {
      final p = FormulaTableLayout.painter(n.text, n.bold)
        ..layout(maxWidth: n.rect.width);
      p.paint(canvas, n.rect.topLeft);
      p.dispose();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('recipe-image-encoding-failed');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}
