import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/formula_document.dart';
import '../../utils/formula_protocol_codec.dart';
import '../../services/share_file.dart';
import 'formula_presentation.dart';
import 'formula_png_renderer.dart';

class StructuredFormulaCard extends StatelessWidget {
  final FormulaDisplayView view;
  final bool Function(String)? canOpenProduct;
  final ValueChanged<String>? onOpenProduct;
  StructuredFormulaCard(
      {super.key,
      required FormulaDocument document,
      this.canOpenProduct,
      this.onOpenProduct})
      : view = FormulaDisplayView(document);

  Widget _ingredient(String text, TextStyle style) {
    final parts = FormulaProtocolCodec.ingredientParts(
        text, view.document.associatedProducts);
    if (onOpenProduct == null ||
        !parts.any((p) =>
            p.target != null && canOpenProduct?.call(p.target!) == true)) {
      return Text(text, style: style, textScaler: TextScaler.noScaling);
    }
    return Text.rich(
        TextSpan(children: [
          for (final p in parts)
            if (p.target != null && canOpenProduct?.call(p.target!) == true)
              WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                      key: ValueKey('recipe-link:${p.target}'),
                      onTap: () => onOpenProduct!(p.target!),
                      child: Text(p.text,
                          style: style.copyWith(
                              decoration: TextDecoration.underline),
                          textScaler: TextScaler.noScaling)))
            else
              TextSpan(text: p.text),
        ]),
        style: style,
        textScaler: TextScaler.noScaling);
  }

  Future<void> _share(BuildContext context) async {
    try {
      final png = await FormulaPngRenderer.render(view);
      final safe = view.document.recipeId;
      await shareFileBytes(png,
          name: '$safe.png',
          mimeType: 'image/png',
          subject: '${view.document.title} - 锐石 RSTONE');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('配方图片生成或分享失败，请重试。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final layout = FormulaTableLayout(view);
    final d = view.document;
    Widget paragraph(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(text,
            style: FormulaTableLayout.style.copyWith(
                color: cs.onSurface,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal),
            textScaler: TextScaler.noScaling));
    return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: paragraph('配方：${d.title}', bold: true)),
            IconButton(
                tooltip: '复制配方五列',
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: view.tsv));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制完整五列（TSV）')));
                  }
                }),
            IconButton(
                tooltip: '分享配方图片',
                icon: const Icon(Icons.share_outlined),
                onPressed: () => _share(context)),
          ]),
          for (final p in d.preTable) paragraph(p),
          SingleChildScrollView(
              key: ValueKey('recipe-scroll:${d.recipeId}'),
              scrollDirection: Axis.horizontal,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var r = 0; r < view.cells.length; r++)
                      Row(children: [
                        for (var c = 0; c < 5; c++)
                          Container(
                            key: ValueKey('recipe-cell:${d.recipeId}:$r:$c'),
                            width: layout.widths[c],
                            height: layout.heights[r],
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                                horizontal: FormulaTableLayout.cellPadding,
                                vertical: 8),
                            decoration: BoxDecoration(
                                color: r == 0
                                    ? cs.surfaceContainerHigh
                                    : cs.surface,
                                border: Border.all(
                                    color: cs.outlineVariant, width: 0.5)),
                            child: r > 0 && c == 0
                                ? _ingredient(
                                    view.cells[r][c],
                                    FormulaTableLayout.style
                                        .copyWith(color: cs.onSurface))
                                : Text(view.cells[r][c],
                                    style: FormulaTableLayout.style.copyWith(
                                        color: cs.onSurface,
                                        fontWeight: r == 0
                                            ? FontWeight.bold
                                            : FontWeight.normal),
                                    textScaler: TextScaler.noScaling),
                          )
                      ]),
                  ])),
          for (final block in d.content) ...[
            if (block is FormulaNote) paragraph(block.text),
            if (block is FormulaProcess) ...[
              paragraph(block.label, bold: true),
              for (final s in block.steps) paragraph(s),
            ],
          ],
        ]));
  }
}
