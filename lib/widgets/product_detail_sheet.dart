import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../models/product_item.dart';
import '../services/tds_pdf_service.dart';
import 'product_detail/formula_content_parser.dart';
import 'product_detail/markdown_table_parser.dart';

/// 产品详情底部弹窗
/// 
/// 从屏幕底部滑出的半屏弹窗，用于展示产品/应用的完整信息。
/// 支持：
/// - Markdown 内容渲染
/// - 产品配方表格展示（Canvas 绘制，支持分享）
/// - 配方信息结构化展示
/// - 拖拽调整弹窗高度（向上展开、向下收起）
class ProductDetailSheet extends StatefulWidget {
  final ProductItem product;
  final List<ProductItem> formulas;
  final String? tdsContent;
  static bool _isShowing = false;

  const ProductDetailSheet({
    super.key,
    required this.product,
    this.formulas = const [],
    this.tdsContent,
  });

  /// 显示产品详情弹窗的便捷方法
  static Future<void> show(
    BuildContext context,
    ProductItem product, {
    List<ProductItem> formulas = const [],
    String? tdsContent,
  }) async {
    if (_isShowing) {
      hideIfOpen(context);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    _isShowing = true;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProductDetailSheet(
        product: product,
        formulas: formulas,
        tdsContent: tdsContent,
      ),
    ).whenComplete(() {
      _isShowing = false;
    });
  }

  static void hideIfOpen(BuildContext context) {
    if (!_isShowing) return;
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  @override
  State<ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends State<ProductDetailSheet> {
  static const double _kPdfMinScaleSnapThreshold = 1.05;
  /// 多配方时下拉选择的索引
  int _selectedFormulaIndex = 0;
  String? _selectedApplicationFormulaName;
  bool _isGeneratingTds = false;
  Uint8List? _pdfLongImage;
  int _pdfPageCount = 0;
  double? _singlePageHeightRatio;
  bool _isRasterizingPdf = false;
  final TransformationController _pdfTransformationController = TransformationController();
  bool _isSyncingPdfTransform = false;

  void _resetPdfPreviewTransform() {
    if (_isSyncingPdfTransform) return;
    _isSyncingPdfTransform = true;
    _pdfTransformationController.value = Matrix4.identity();
    _isSyncingPdfTransform = false;
  }

  Future<void> _preparePdfPreview(Uint8List pdfBytes) async {
    setState(() {
      _isRasterizingPdf = true;
      _pdfLongImage = null;
      _pdfPageCount = 0;
      _singlePageHeightRatio = null;
      _resetPdfPreviewTransform();
    });

    final pages = <Uint8List>[];
    await for (final page in Printing.raster(pdfBytes, dpi: 160)) {
      pages.add(await page.toPng());
    }

    double? singlePageHeightRatio;
    if (pages.length == 1) {
      final singlePageImage = await _decodeImage(pages.first);
      singlePageHeightRatio = singlePageImage.height / singlePageImage.width;
      singlePageImage.dispose();
    }

    final previewImage = pages.length <= 1
        ? (pages.isEmpty ? null : pages.first)
        : await _composeLongPdfImage(pages);

    if (!mounted) return;
    setState(() {
      _pdfLongImage = previewImage;
      _pdfPageCount = pages.length;
      _singlePageHeightRatio = singlePageHeightRatio;
      _isRasterizingPdf = false;
    });
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<Uint8List?> _composeLongPdfImage(List<Uint8List> pageImages) async {
    if (pageImages.isEmpty) return null;
    final decodedPages = <ui.Image>[];
    try {
      for (final bytes in pageImages) {
        decodedPages.add(await _decodeImage(bytes));
      }
      if (decodedPages.isEmpty) return null;

      const gap = 16.0;
      final maxWidth = decodedPages
          .map((img) => img.width.toDouble())
          .reduce((a, b) => a > b ? a : b);
      final scaledHeights = decodedPages
          .map((img) => img.height * (maxWidth / img.width))
          .toList();
      final totalHeight =
          scaledHeights.fold<double>(0, (sum, h) => sum + h) +
              gap * (decodedPages.length - 1);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, maxWidth, totalHeight),
        Paint()..color = Colors.white,
      );

      var dy = 0.0;
      for (var i = 0; i < decodedPages.length; i++) {
        final page = decodedPages[i];
        final targetHeight = scaledHeights[i];
        canvas.drawImageRect(
          page,
          Rect.fromLTWH(0, 0, page.width.toDouble(), page.height.toDouble()),
          Rect.fromLTWH(0, dy, maxWidth, targetHeight),
          Paint(),
        );
        dy += targetHeight + gap;
      }

      final picture = recorder.endRecording();
      final longImage = await picture.toImage(maxWidth.ceil(), totalHeight.ceil());
      final byteData = await longImage.toByteData(format: ui.ImageByteFormat.png);
      longImage.dispose();
      return byteData?.buffer.asUint8List();
    } finally {
      for (final image in decodedPages) {
        image.dispose();
      }
    }
  }

  void _handlePdfTransformChanged() {
    if (_isSyncingPdfTransform) return;
    final matrix = _pdfTransformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    if (scale > _kPdfMinScaleSnapThreshold) return;

    final isSinglePage = _pdfPageCount <= 1;
    final yOffset = matrix.storage[13];
    final hasHorizontalOffset = matrix.storage[12].abs() > 0.5;
    final hasScaleOffset = (scale - 1).abs() > 0.01;
    final hasVerticalOffset = matrix.storage[13].abs() > 0.5;

    if (isSinglePage) {
      if (!hasHorizontalOffset && !hasScaleOffset && !hasVerticalOffset) return;
      _resetPdfPreviewTransform();
      return;
    }

    if (!hasHorizontalOffset && !hasScaleOffset) return;
    _isSyncingPdfTransform = true;
    _pdfTransformationController.value = Matrix4.identity()
      ..setTranslationRaw(0, yOffset, 0);
    _isSyncingPdfTransform = false;
  }

  Widget _buildPdfPreviewViewer(BoxConstraints constraints) {
    if (_pdfPageCount <= 1) {
      return _buildSinglePagePdfPreviewViewer(constraints);
    }
    return _buildMultiPagePdfPreviewViewer(constraints);
  }

  Widget _buildSinglePagePdfPreviewViewer(BoxConstraints constraints) {
    final pageHeightRatio = _singlePageHeightRatio ?? 1.4142;
    final pageWidth = constraints.maxWidth;
    final pageHeight = pageWidth * pageHeightRatio;
    final widthScale = constraints.maxWidth / pageWidth;
    final heightScale = constraints.maxHeight / pageHeight;
    final fittedScale = widthScale < heightScale ? widthScale : heightScale;
    final viewerWidth = pageWidth * fittedScale;
    final viewerHeight = pageHeight * fittedScale;

    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: SizedBox(
          width: viewerWidth,
          height: viewerHeight,
          child: InteractiveViewer(
            transformationController: _pdfTransformationController,
            minScale: 1,
            maxScale: 3.5,
            panEnabled: true,
            scaleEnabled: true,
            boundaryMargin: EdgeInsets.zero,
            clipBehavior: Clip.hardEdge,
            onInteractionEnd: (_) => _handlePdfTransformChanged(),
            child: SizedBox(
              width: viewerWidth,
              height: viewerHeight,
              child: Image.memory(
                _pdfLongImage!,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMultiPagePdfPreviewViewer(BoxConstraints constraints) {
    return InteractiveViewer(
      transformationController: _pdfTransformationController,
      constrained: false,
      minScale: 1,
      maxScale: 3.5,
      panEnabled: true,
      scaleEnabled: true,
      boundaryMargin: EdgeInsets.zero,
      clipBehavior: Clip.none,
      onInteractionUpdate: (_) => _handlePdfTransformChanged(),
      onInteractionEnd: (_) => _handlePdfTransformChanged(),
      child: ColoredBox(
        color: Colors.white,
        child: SizedBox(
          width: constraints.maxWidth,
          child: Image.memory(
            _pdfLongImage!,
            fit: BoxFit.fitWidth,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }

  Future<void> _handlePreviewTds() async {
    if (_isGeneratingTds || widget.product.folder != '产品列表' || widget.tdsContent == null) {
      return;
    }

    setState(() {
      _isGeneratingTds = true;
    });

    try {
      final pdfBytes = await TdsPdfService.generatePdfBytes(
        widget.product,
        tdsMarkdown: widget.tdsContent!,
      );
      await _preparePdfPreview(pdfBytes);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final cs = Theme.of(dialogContext).colorScheme;
          final mediaSize = MediaQuery.sizeOf(dialogContext);
          const defaultPageHeightRatio = 1.4142;
          final pageHeightRatio = _singlePageHeightRatio ?? defaultPageHeightRatio;
          final maxDialogWidth = mediaSize.width - 24;
          final maxDialogHeight = mediaSize.height - 32;
          final dialogWidth = math.min(maxDialogWidth, maxDialogHeight / pageHeightRatio);
          final dialogHeight = dialogWidth * pageHeightRatio;

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            backgroundColor: cs.surfaceContainerHigh,
            surfaceTintColor: cs.surfaceTint,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: dialogWidth,
              height: dialogHeight,
              child: Container(
                color: Colors.white,
                padding: EdgeInsets.zero,
                child: _isRasterizingPdf
                    ? const Center(child: CircularProgressIndicator())
                    : _pdfLongImage == null
                        ? Center(
                            child: Text(
                              'PDF 预览加载失败',
                              style: Theme.of(dialogContext).textTheme.bodyLarge?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              return _buildPdfPreviewViewer(constraints);
                            },
                          ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('TDS 生成失败：$e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isGeneratingTds = false;
      });
    }
  }

  Future<void> _handleShareTds() async {
    if (_isGeneratingTds || widget.product.folder != '产品列表' || widget.tdsContent == null) {
      return;
    }

    setState(() {
      _isGeneratingTds = true;
    });

    try {
      await TdsPdfService.generateAndShareTds(
        widget.product,
        tdsMarkdown: widget.tdsContent!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TDS 已生成并打开分享面板')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('TDS 分享失败：$e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isGeneratingTds = false;
      });
    }
  }

  List<ProductItem> _deduplicateFormulasByFileName(List<ProductItem> formulas) {
    final unique = <String, ProductItem>{};
    for (final formula in formulas) {
      unique.putIfAbsent(formula.fileName, () => formula);
    }
    return unique.values.toList();
  }

  bool _isWaterBasedProduct() {
    return widget.product.tags.any((tag) => tag.contains('水性'));
  }

  Color _folderAccent(ColorScheme cs) {
    if (widget.product.folder == '产品列表') {
      return _isWaterBasedProduct() ? cs.primary : cs.tertiary;
    }
    return cs.secondary;
  }

  String _withUnit(String label, String value) {
    final trimmed = value.trim();
    switch (label) {
      case '固含':
        return trimmed.contains('%') ? trimmed : '$trimmed%';
      case '羟值':
        return trimmed.toLowerCase().contains('mgkoh/g') ? trimmed : '$trimmed mgKOH/g';
      default:
        return trimmed;
    }
  }

  @override
  void initState() {
    super.initState();
    final linked = _getApplicationLinkedFormulas();
    if (linked.isNotEmpty) {
      _selectedApplicationFormulaName = linked.first.fileName.replaceAll('.md', '');
    }
  }

  @override
  void dispose() {
    _pdfTransformationController.dispose();
    super.dispose();
  }

  String _extractMarkdownBody(String rawContent) =>
      FormulaContentParser.extractMarkdownBody(rawContent);

  /// 解析 markdown 表格数据
  /// [rawContent] 传入的完整 markdown 内容（可能包含多张表格和非表格文字）
  /// 返回解析后的表格行列表；同时通过 [nonTableContent] 输出不在表格内的文字（如 blockquote 等）
  List<List<String>> _parseTable(String rawContent, [List<String>? nonTableContent]) {
    return MarkdownTableParser.parseTable(rawContent, nonTableContent);
  }

  /// 用 Canvas 完整渲染表格为 PNG（不依赖截图，保证所有行都渲染）
  /// [extraContent] 表格外的完整文字（表格前/后的补充信息），会渲染在表格下方
  Future<void> _shareTableAsImage(
    BuildContext context,
    String title,
    List<List<String>> rows, {
    String? extraContent,
  }) async {
    if (rows.isEmpty) return;
    try {
      const double rowHeight = 36.0;
      const double headerHeight = 40.0;
      const double cellPaddingH = 16.0;
      const double colMinWidth = 80.0;
      const double scale = 2.0; // 2x 分辨率提升清晰度
      final cs = Theme.of(context).colorScheme;
      final backgroundColor = cs.surface;
      final headerBackgroundColor = cs.surfaceContainerHigh;
      final headerCellColor = cs.surfaceContainerHighest;
      final borderColor = cs.outlineVariant;
      final rowAltColor = cs.surfaceContainerLowest;
      final titleColor = cs.secondary;
      final headerTextColor = cs.primary;
      final bodyTextColor = cs.onSurface;
      final extraTextColor = cs.onSurfaceVariant;

      final header = rows.first;
      final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];
      final colCount = header.length;

      // 计算每列宽度（根据内容）
      List<double> colWidths = List.filled(colCount, colMinWidth);
      for (final row in rows) {
        for (int i = 0; i < row.length && i < colCount; i++) {
          final len = row[i].length * 10.0 + cellPaddingH * 2;
          if (len > colWidths[i]) colWidths[i] = len.clamp(colMinWidth, 300.0);
        }
      }
      final totalWidth = colWidths.reduce((a, b) => a + b) + 4;
      // 计算标题高度（缩放后已是逻辑像素，直接用）
      double titleHeight = 0;
      if (title.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(text: title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: titleColor)),
          textDirection: TextDirection.ltr,
        );
        tp.layout(maxWidth: totalWidth - 24);
        titleHeight = tp.height + 16; // 上下各 8px padding
      }
      // 计算表格外附加文字高度
      double extraHeight = 0;
      if (extraContent != null && extraContent.trim().isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(text: extraContent, style: TextStyle(fontSize: 12, height: 1.5, color: extraTextColor)),
          textDirection: TextDirection.ltr,
        );
        tp.layout(maxWidth: totalWidth - 24);
        extraHeight = tp.height + 16; // 上下各 8px padding
      }
      final tableHeight = headerHeight + dataRows.length * rowHeight + 4;
      final totalHeight = titleHeight + tableHeight + extraHeight;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(scale, scale); // 2x 缩放提升清晰度

      // 背景
      canvas.drawRect(
        Rect.fromLTWH(0, 0, totalWidth, totalHeight),
        Paint()..color = backgroundColor,
      );

      // 绘制标题（wiki 链接已转换为普通文字）
      if (title.isNotEmpty) {
        final titlePainter = TextPainter(
          text: TextSpan(text: title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: titleColor)),
          textDirection: TextDirection.ltr,
        );
        titlePainter.layout(maxWidth: totalWidth - 24);
        titlePainter.paint(canvas, Offset(12, 8));
      }

      // 表头背景（表格从 titleHeight 开始）
      canvas.drawRect(
        Rect.fromLTWH(0, titleHeight, totalWidth, headerHeight),
        Paint()..color = headerBackgroundColor,
      );

      // 绘制表头（表格从 titleHeight 开始）
      double x = 0;
      for (int i = 0; i < colCount; i++) {
        canvas.drawRect(
          Rect.fromLTWH(x, titleHeight, colWidths[i], headerHeight),
          Paint()..color = headerCellColor,
        );
        _drawCell(canvas, header[i], x, titleHeight, colWidths[i], headerHeight,
            headerTextColor, true);
        x += colWidths[i];
      }

      // 绘制数据行（表格从 titleHeight 开始）
      for (int r = 0; r < dataRows.length; r++) {
        final row = dataRows[r];
        final y = titleHeight + headerHeight + r * rowHeight;
        if (r.isOdd) {
          canvas.drawRect(
            Rect.fromLTWH(0, y, totalWidth, rowHeight),
            Paint()..color = rowAltColor,
          );
        }
        x = 0;
        for (int i = 0; i < colCount; i++) {
          _drawCell(canvas, i < row.length ? row[i] : '',
              x, y, colWidths[i], rowHeight, bodyTextColor, false);
          x += colWidths[i];
        }
      }

      // 边框
      canvas.drawRect(
        Rect.fromLTWH(0, 0, totalWidth, totalHeight),
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

      // 绘制表格外附加文字
      if (extraContent != null && extraContent.trim().isNotEmpty) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: extraContent,
            style: TextStyle(
              color: extraTextColor,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: totalWidth - 24);
        final blockY = titleHeight + tableHeight + 8; // 标题+表格高度之后 + padding
        textPainter.paint(canvas, Offset(12, blockY));
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage(
        (totalWidth * scale).ceil(),
        (totalHeight * scale).ceil(),
      );
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final safeTitle = title.replaceAll('配方：', '').replaceAll(RegExp(r'[\\/:*?"<>|\\s]+'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${safeTitle}_$timestamp.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pngBytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png', name: fileName)],
        subject: '$title - 锐石 RSTONE',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _drawCell(Canvas canvas, String text, double x, double y,
      double w, double h, Color color, bool bold) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: w - 8);
    tp.paint(canvas, Offset(x + 8, y + (h - tp.height) / 2));
  }

  double _textWidth(String text, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    return tp.width;
  }

  /// 渲染配方 markdown 表格（完全自定义渲染，列宽自动适配内容）
  /// [tableContent] 应为去掉 frontmatter 后的纯 markdown 表格内容
  /// [extraContent] 表格外的文字（如 blockquote 施工比例），渲染在表格下方，宽度与表格总列宽一致
  Widget _buildMdTable(String tableContent, {String? extraContent}) {
    final cs = Theme.of(context).colorScheme;
    final rows = _parseTable(tableContent);
    if (rows.isEmpty) return const SizedBox.shrink();

    final header = rows.first;
    final colCount = header.length;
    final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];

    // 计算每列最小宽度（根据内容）
    const double minColWidth = 60.0;
    const double maxColWidth = 300.0;
    const double cellHPadding = 12.0;
    const double rowHeight = 36.0;
    const double headerHeight = 38.0;

    List<double> colWidths = List.filled(colCount, minColWidth);
    void measureCol(int col, String text) {
      final w = _textWidth(text, 12) + cellHPadding * 2;
      if (w > colWidths[col]) colWidths[col] = w.clamp(minColWidth, maxColWidth);
    }
    for (int i = 0; i < colCount; i++) measureCol(i, header[i]);
    for (final row in dataRows) {
      for (int i = 0; i < row.length; i++) measureCol(i, row[i]);
    }
    // 填充空列
    while (colWidths.length < colCount) colWidths.add(minColWidth);
    final totalTableWidth = colWidths.reduce((a, b) => a + b);

    final borderColor = cs.outlineVariant;
    final headerBg = cs.surfaceContainerHigh;
    final rowAlt = cs.surfaceContainerLowest;
    final rowBg = cs.surfaceContainer;
    final headerText = cs.primary;
    final cellText = cs.onSurface;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: rowBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 表头行
                _buildTableRow(header, colWidths, headerHeight, true, cellHPadding,
                    headerBg, headerText, borderColor),
                // 数据行
                for (int ri = 0; ri < dataRows.length; ri++)
                  _buildTableRow(
                    dataRows[ri].length >= colCount
                        ? dataRows[ri].take(colCount).toList()
                        : List.generate(colCount, (i) => i < dataRows[ri].length ? dataRows[ri][i] : ''),
                    colWidths, rowHeight, false, cellHPadding,
                    ri.isOdd ? rowAlt : rowBg, cellText, borderColor,
                  ),
              ],
            ),
          ),
          // 表格下方的 blockquote 等额外文字，放入横向滚动容器，避免宽表撑爆布局
          if (extraContent != null && extraContent.trim().isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalTableWidth,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Text(
                    extraContent,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableRow(List<String> cells, List<double> colWidths, double height,
      bool isHeader, double hPadding, Color bg, Color textColor, Color borderColor) {
    double totalWidth = colWidths.reduce((a, b) => a + b);
    return Container(
      width: totalWidth,
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: borderColor, width: 0.5)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < cells.length; i++)
            Container(
              width: colWidths[i],
              height: height,
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.symmetric(horizontal: hPadding),
              decoration: BoxDecoration(
                border: i > 0 ? Border(left: BorderSide(color: borderColor, width: 0.5)) : null,
              ),
              child: Text(
                cells[i],
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _markdownView(String content) {
    if (content.trim().isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    // 把 Obsidian wiki 链接 [[XXX]] 转换为普通文字 XXX
    final converted = MarkdownTableParser.normalizeWikiLinks(content);
    return MarkdownBody(
      data: converted,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(color: cs.onSurfaceVariant, fontSize: 14, height: 1.6),
        h1: TextStyle(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.bold),
        h2: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
        h3: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
        listBullet: TextStyle(color: cs.onSurfaceVariant),
        code: TextStyle(color: cs.secondary, backgroundColor: cs.surfaceContainerHighest),
        codeblockDecoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: cs.primary, width: 3),
          ),
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: cs.outlineVariant, width: 1),
          ),
        ),
      ),
      selectable: true,
    );
  }

  /// 从 frontmatter 提取配方相关字段，生成结构化表格
  Widget _buildFormulaTable() {
    final cs = Theme.of(context).colorScheme;
    final fields = <MapEntry<String, String>>[];
    final linkedByName = {
      for (final f in _getApplicationLinkedFormulas()) f.fileName.replaceAll('.md', ''): f,
    };

    void add(String label, String? value) {
      if (value != null && value.isNotEmpty) {
        fields.add(MapEntry(label, value));
      }
    }

    add('底漆', widget.product.primer);
    add('中漆', widget.product.midCoat);
    add('面漆', widget.product.topCoat);
    add('基材', widget.product.baseMaterial);

    if (fields.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '应用信息',
              style: TextStyle(
                color: cs.primary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Table(
            columnWidths: const {
              0: FixedColumnWidth(70),
              1: FlexColumnWidth(1),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: fields.map((e) {
              return TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      e.key,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: linkedByName.containsKey(e.value)
                        ? InkWell(
                            onTap: () => setState(() => _selectedApplicationFormulaName = e.value),
                            borderRadius: BorderRadius.circular(4),
                            child: Text(
                              e.value,
                              style: TextStyle(
                                color: _selectedApplicationFormulaName == e.value
                                    ? cs.primary
                                    : cs.secondary,
                                fontSize: 13,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          )
                        : Text(
                            e.value,
                            style: TextStyle(color: cs.onSurface, fontSize: 13),
                          ),
                  ),
                ],
              );
            }).toList(),
          ),
          if (_selectedApplicationFormulaName != null &&
              linkedByName[_selectedApplicationFormulaName!] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
              child: _buildFormulaCard(
                '配方：$_selectedApplicationFormulaName',
                linkedByName[_selectedApplicationFormulaName!]!.rawContent,
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 产品元数据表（放在配方之前，且与配方分区展示）
  Widget _buildProductMetaTable() {
    if (widget.product.folder != '产品列表') return const SizedBox.shrink();

    final entries = <MapEntry<String, String>>[
      if (widget.product.experimentalCode?.isNotEmpty == true)
        MapEntry('实验牌号', widget.product.experimentalCode!),
      if (widget.product.engineer?.isNotEmpty == true)
        MapEntry('工程师', widget.product.engineer!),
      if (widget.product.solidContent?.isNotEmpty == true)
        MapEntry('固含', widget.product.solidContent!),
      if (widget.product.hydroxylValue?.isNotEmpty == true)
        MapEntry('羟值', widget.product.hydroxylValue!),
      if (widget.product.waterContactAngle?.isNotEmpty == true)
        MapEntry('水接触角', widget.product.waterContactAngle!),
      if (widget.product.technologySource?.isNotEmpty == true)
        MapEntry('技术源', widget.product.technologySource!),
      if (widget.product.benchmark?.isNotEmpty == true)
        MapEntry('对标', widget.product.benchmark!),
      if (widget.product.viscosity?.isNotEmpty == true)
        MapEntry('粘度', widget.product.viscosity!),
    ];

    if (entries.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final typeColor = _folderAccent(cs);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.table_view, size: 16, color: typeColor),
                const SizedBox(width: 6),
                Text(
                  '产品信息',
                  style: TextStyle(
                    color: typeColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Table(
            columnWidths: const {0: FixedColumnWidth(90), 1: FlexColumnWidth(1)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: entries.map((e) {
              return TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      e.key,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      _withUnit(e.key, e.value),
                      style: TextStyle(color: cs.onSurface, fontSize: 13),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  List<ProductItem> _getApplicationLinkedFormulas() {
    if (widget.product.folder != '产品应用') return const [];
    final keys = <String>{
      if (widget.product.primer != null && widget.product.primer!.isNotEmpty) widget.product.primer!,
      if (widget.product.midCoat != null && widget.product.midCoat!.isNotEmpty) widget.product.midCoat!,
      if (widget.product.topCoat != null && widget.product.topCoat!.isNotEmpty) widget.product.topCoat!,
    };
    final linked = widget.formulas.where((f) => keys.contains(f.fileName.replaceAll('.md', ''))).toList();
    return _deduplicateFormulasByFileName(linked);
  }

  /// 查找并渲染关联的产品配方（文件名以产品牌号开头，如 RS7767-银.md 对应 RS7767）
  Widget _buildLinkedFormulas() {
    final cs = Theme.of(context).colorScheme;
    final matchedFormulas = _deduplicateFormulasByFileName(widget.formulas.where((f) {
      // 精确匹配：配方文件名以产品牌号+"-"开头（如 RS7767-银.md 匹配产品 RS7767）
      // experimentalCode 可能指向另一个系列的产品牌号，仅在非空且有明确匹配时才使用
      final hasExperimentalCodeMatch =
          widget.product.experimentalCode != null &&
          widget.product.experimentalCode!.isNotEmpty &&
          f.fileName.startsWith(widget.product.experimentalCode!);
      return f.fileName.startsWith(widget.product.fileName + '-') ||
          hasExperimentalCodeMatch;
    }).toList());

    if (matchedFormulas.isEmpty) return const SizedBox.shrink();

    // 单配方：直接展示
    if (matchedFormulas.length == 1) {
      final formula = matchedFormulas.first;
      final title = '配方：${formula.fileName.replaceAll('.md', '')}';
      return _buildFormulaCard(title, formula.rawContent);
    }

    // 多配方：下拉选择器
    final items = matchedFormulas.asMap().entries.map((entry) {
      final index = entry.key;
      final formula = entry.value;
      return DropdownMenuItem(
        value: index,
        child: Text(
          formula.fileName.replaceAll('.md', ''),
          style: TextStyle(color: cs.onSurface, fontSize: 13),
        ),
      );
    }).toList();

    final selectedFormula = matchedFormulas[_selectedFormulaIndex.clamp(0, matchedFormulas.length - 1)];
    final title = '配方：${selectedFormula.fileName.replaceAll('.md', '')}';

    return Column(
      children: [
        // 下拉选择器
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedFormulaIndex.clamp(0, matchedFormulas.length - 1),
              isExpanded: true,
              dropdownColor: cs.surfaceContainerHigh,
              icon: Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
              items: items,
              onChanged: (val) {
                if (val != null) setState(() => _selectedFormulaIndex = val);
              },
            ),
          ),
        ),
        _buildFormulaCard(title, selectedFormula.rawContent),
      ],
    );
  }

  bool _hasLinkedFormulasForCurrentProduct() {
    if (widget.product.folder != '产品列表') return false;
    return widget.formulas.any((f) {
      final formulaName = f.fileName.replaceAll('.md', '');
      return formulaName.startsWith('${widget.product.fileName}-');
    });
  }

  String _removeStandaloneWikiLines(String content) {
    return content
        .split('\n')
        .where((line) => !RegExp(r'^\s*(\[\[[^\]]+\]\]\s*)+$').hasMatch(line))
        .join('\n');
  }

  Widget _buildFormulaCard(String title, String rawContent) {
    final cs = Theme.of(context).colorScheme;
    // 将复杂文本解析逻辑下沉到独立解析器，UI 层仅做渲染。
    final displayContent = FormulaContentParser.parse(rawContent);
    final preContent = displayContent.preTableContent;
    final postContent = displayContent.postTableContent;
    final bodyContent = displayContent.tableMarkdownBody;
    final tableBodyRows = _parseTable(bodyContent);
    final fullExtraContent = displayContent.combinedExtraContent;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Icon(Icons.science_outlined, color: cs.secondary, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: cs.secondary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.share_outlined, color: cs.onSurfaceVariant, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  tooltip: '分享配方图片',
                  onPressed: () => _shareTableAsImage(
                    context,
                    title,
                    tableBodyRows,
                    extraContent: fullExtraContent.isNotEmpty ? fullExtraContent : null,
                  ),
                ),
              ],
            ),
          ),
          // 表格前的额外内容（如有）
          if (preContent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                preContent,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          _buildMdTable(
            bodyContent,
            extraContent: postContent.isNotEmpty ? postContent : null,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final folderAccent = _folderAccent(cs);
    // 去掉 frontmatter 部分，只留 body
    final bodyContent = _extractMarkdownBody(widget.product.rawContent);
    final markdownContent = _hasLinkedFormulasForCurrentProduct()
        ? _removeStandaloneWikiLines(bodyContent)
        : bodyContent;

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        // 当 sheet 被拖动到接近底部时（extent 接近 minExtent），关闭弹窗
        if (notification.extent < notification.minExtent * 0.6) {
          Navigator.pop(context);
          return true;
        }
        // 当 sheet 拖动超出 maxChildSize 时，阻止默认弹性拉伸
        // DraggableScrollableNotification 没有 maxChildSize 属性，直接用 DraggableScrollableSheet 的实际值 1.0
        if (notification.extent > 1.0) {
          return true; // 阻止通知向上冒泡
        }
        return false;
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.1,
        maxChildSize: 1.0,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: ListView(
              controller: scrollController,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                // 拖动条（把手）
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // 标题栏
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: folderAccent.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.product.folder,
                          style: TextStyle(
                            color: folderAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.product.displayName,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.product.folder == '产品列表' && widget.tdsContent != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _isGeneratingTds ? null : _handlePreviewTds,
                            onLongPress: _isGeneratingTds ? null : _handleShareTds,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: _isGeneratingTds
                                  ? SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: cs.onSecondaryContainer,
                                      ),
                                    )
                                  : Text(
                                      'TDS',
                                      style: TextStyle(
                                        color: cs.onSecondaryContainer,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Divider(color: cs.outlineVariant, height: 1),
                // 标签
                if (widget.product.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.product.tags.map((tag) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              color: cs.onSecondaryContainer,
                              fontSize: 12,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                // 配方表格（仅产品应用有配方字段）
                if (widget.product.folder == '产品应用') _buildFormulaTable(),
                // 产品详情字段表格（位于配方区块之前）
                if (widget.product.folder == '产品列表') _buildProductMetaTable(),
                // 产品配方 section：文件名以当前产品牌号+"-"开头时显示
                if (widget.product.folder == '产品列表')
                  _buildLinkedFormulas(),
                // MD 内容（不含 frontmatter）
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: _markdownView(markdownContent),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
