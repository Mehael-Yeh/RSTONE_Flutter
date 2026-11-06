import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../utils/app_shapes.dart';
import 'package:flutter/services.dart';
import '../../models/formula_document.dart';

import '../../services/share_file.dart';
import 'formula_presentation.dart';
import 'process_presentation.dart';
import 'formula_png_renderer.dart';
import 'formula_pinned_table.dart';
import 'formula_card_header.dart';

class StructuredFormulaCard extends StatelessWidget {
  final FormulaDisplayView view;
  final bool Function(String)? canOpenProduct;
  final ValueChanged<String>? onOpenProduct;
  final Widget? selector;
  StructuredFormulaCard(
      {super.key,
      required FormulaDocument document,
      this.selector,
      this.canOpenProduct,
      this.onOpenProduct})
      : view = FormulaDisplayView(document);

  Widget _ingredient(String text, TextStyle style) {
    final parts = formulaDisplayParts(text, view.document.associatedProducts);
    if (onOpenProduct == null ||
        !parts.any((p) =>
            p.target != null && canOpenProduct?.call(p.target!) == true)) {
      return Text(parts.map((p) => p.text).join(),
          style: style, textScaler: TextScaler.noScaling);
    }
    return _IngredientLinks(
        text: text,
        style: style,
        associated: view.document.associatedProducts,
        canOpenProduct: canOpenProduct!,
        onOpenProduct: onOpenProduct!);
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
            borderRadius: AppShapes.borderRadius),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FormulaCardHeader(
            title: d.title,
            selector: selector,
            onCopy: () async {
              await Clipboard.setData(ClipboardData(text: view.tsv));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制完整五列（TSV）')));
              }
            },
            onShare: () => _share(context),
          ),
          for (final p in d.preTable) paragraph(p),
          LayoutBuilder(builder: (context, constraints) {
            final layout = FormulaTableLayout(view,
                firstColumnMax: constraints.maxWidth * .55);
            return FormulaPinnedTable(
                key: ValueKey('recipe-table:${d.recipeId}'),
                id: d.recipeId,
                widths: layout.widths,
                heights: layout.heights,
                cell: (r, c) => Container(
                      key: ValueKey('recipe-cell:${d.recipeId}:$r:$c'),
                      width: layout.widths[c],
                      height: layout.heights[r],
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                          horizontal: FormulaTableLayout.cellPadding,
                          vertical: 8),
                      decoration: BoxDecoration(
                          color: r == 0 ? cs.surfaceContainerHigh : cs.surface,
                          border:
                              Border.all(color: cs.outlineVariant, width: .5)),
                      child: r > 0 && c == 0
                          ? _ingredient(
                              d.rows[r - 1][c],
                              FormulaTableLayout.style
                                  .copyWith(color: cs.onSurface))
                          : Text(view.cells[r][c],
                              style: FormulaTableLayout.style.copyWith(
                                  color: cs.onSurface,
                                  fontWeight: r == 0
                                      ? FontWeight.bold
                                      : FontWeight.normal),
                              textScaler: TextScaler.noScaling),
                    ));
          }),
          for (final block in d.content) ...[
            if (block is FormulaNote) paragraph(block.text),
            if (block is FormulaProcess) ...[
              paragraph(block.label, bold: true),
              for (final s in presentFormulaProcess(block.steps)) paragraph(s),
            ],
          ],
        ]));
  }
}

/// Inline spans keep exactly the same shaping/wrapping as the measured text.
/// This state owns every recognizer, including when a cell changes documents.
class _IngredientLinks extends StatefulWidget {
  final String text;
  final TextStyle style;
  final List<String> associated;
  final bool Function(String) canOpenProduct;
  final ValueChanged<String> onOpenProduct;
  const _IngredientLinks(
      {required this.text,
      required this.style,
      required this.associated,
      required this.canOpenProduct,
      required this.onOpenProduct});
  @override
  State<_IngredientLinks> createState() => _IngredientLinksState();
}

class _IngredientLinksState extends State<_IngredientLinks> {
  final _recognizers = <TapGestureRecognizer>[];
  late List<InlineSpan> _spans;

  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _updateSpans() {
    _clear();
    _spans = [
      for (final part in formulaDisplayParts(widget.text, widget.associated))
        if (part.target != null && widget.canOpenProduct(part.target!))
          TextSpan(
              text: part.text,
              style:
                  widget.style.copyWith(decoration: TextDecoration.underline),
              recognizer: _recognizer(part.target!))
        else
          TextSpan(text: part.text),
    ];
  }

  TapGestureRecognizer _recognizer(String target) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        if (widget.canOpenProduct(target)) widget.onOpenProduct(target);
      };
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  void initState() {
    super.initState();
    _updateSpans();
  }

  @override
  void didUpdateWidget(covariant _IngredientLinks oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateSpans();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: _spans),
      style: widget.style, textScaler: TextScaler.noScaling);
}
