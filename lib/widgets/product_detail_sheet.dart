import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/product_item.dart';

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

  const ProductDetailSheet({super.key, required this.product, this.formulas = const []});

  /// 显示产品详情弹窗的便捷方法
  static void show(BuildContext context, ProductItem product, {List<ProductItem> formulas = const []}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProductDetailSheet(product: product, formulas: formulas),
    );
  }

  @override
  State<ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends State<ProductDetailSheet> {
  /// 多配方时下拉选择的索引
  int _selectedFormulaIndex = 0;

  /// 解析 markdown 表格数据
  /// [rawContent] 传入的完整 markdown 内容（可能包含多张表格和非表格文字）
  /// 返回解析后的表格行列表；同时通过 [nonTableContent] 输出不在表格内的文字（如 blockquote 等）
  List<List<String>> _parseTable(String rawContent, [List<String>? nonTableContent]) {
    final rows = <List<String>>[];
    for (final line in rawContent.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // 非表格行（如 blockquote、行首无 | 的内容）
      if (!trimmed.startsWith('|')) {
        if (nonTableContent != null && trimmed.isNotEmpty) {
          nonTableContent.add(trimmed);
        }
        continue;
      }
      bool isSep = true;
      for (final cell in trimmed.split('|')) {
        final t = cell.trim();
        if (t.isNotEmpty && !RegExp(r'^[-:]+$').hasMatch(t)) {
          isSep = false;
          break;
        }
      }
      if (isSep) continue;
      // 保留所有单元格（包括尾部空单元格），用 null 占位以保持列对齐
      // 同时把 Obsidian wiki 链接 [[XXX]] 转换为 XXX
      final cols = trimmed.split('|').map((s) {
        var cell = s.trim();
        cell = cell.replaceAllMapped(RegExp(r'\[\[([^\]]+)\]\]'), (m) => m.group(1) ?? cell);
        return cell;
      }).toList();
      // 去掉首尾空字符串（首尾 | 产生的空列）
      while (cols.isNotEmpty && cols.first.isEmpty) cols.removeAt(0);
      while (cols.isNotEmpty && cols.last.isEmpty) cols.removeLast();
      if (cols.isNotEmpty) rows.add(cols);
    }
    return rows;
  }

  /// 用 Canvas 完整渲染表格为 PNG（不依赖截图，保证所有行都渲染）
  /// [extraContent] blockquote 等表格外的文字，会渲染在表格下方
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
          text: TextSpan(text: title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFFF9800))),
          textDirection: TextDirection.ltr,
        );
        tp.layout(maxWidth: totalWidth - 24);
        titleHeight = tp.height + 16; // 上下各 8px padding
      }
      // 计算 blockquote 文字高度
      double extraHeight = 0;
      if (extraContent != null && extraContent.trim().isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(text: extraContent, style: const TextStyle(fontSize: 12, height: 1.5)),
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
        Paint()..color = const Color(0xFF1E1E1E),
      );

      // 绘制标题（wiki 链接已转换为普通文字）
      if (title.isNotEmpty) {
        final titlePainter = TextPainter(
          text: TextSpan(text: title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFFF9800))),
          textDirection: TextDirection.ltr,
        );
        titlePainter.layout(maxWidth: totalWidth - 24);
        titlePainter.paint(canvas, Offset(12, 8));
      }

      // 表头背景（表格从 titleHeight 开始）
      canvas.drawRect(
        Rect.fromLTWH(0, titleHeight, totalWidth, headerHeight),
        Paint()..color = const Color(0xFF2D2D2D),
      );

      // 绘制表头（表格从 titleHeight 开始）
      double x = 0;
      for (int i = 0; i < colCount; i++) {
        canvas.drawRect(
          Rect.fromLTWH(x, titleHeight, colWidths[i], headerHeight),
          Paint()..color = Colors.grey.shade800,
        );
        _drawCell(canvas, header[i], x, titleHeight, colWidths[i], headerHeight,
            const Color(0xFFFF9800), true);
        x += colWidths[i];
      }

      // 绘制数据行（表格从 titleHeight 开始）
      for (int r = 0; r < dataRows.length; r++) {
        final row = dataRows[r];
        final y = titleHeight + headerHeight + r * rowHeight;
        if (r.isOdd) {
          canvas.drawRect(
            Rect.fromLTWH(0, y, totalWidth, rowHeight),
            Paint()..color = const Color(0xFF2A2A2A),
          );
        }
        x = 0;
        for (int i = 0; i < colCount; i++) {
          _drawCell(canvas, i < row.length ? row[i] : '',
              x, y, colWidths[i], rowHeight, const Color(0xFFB0B0B0), false);
          x += colWidths[i];
        }
      }

      // 边框
      canvas.drawRect(
        Rect.fromLTWH(0, 0, totalWidth, totalHeight),
        Paint()
          ..color = Colors.grey.shade700
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

      // 绘制 blockquote 施工比例文字
      if (extraContent != null && extraContent.trim().isNotEmpty) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: extraContent,
            style: const TextStyle(
              color: Color(0xFFB0B0B0),
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
      final img = await picture.toImage(totalWidth.toInt(), totalHeight.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final fileName = '${title.replaceAll('配方：', '').replaceAll(' ', '_')}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
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

    const Color borderColor = Color(0xFF3D3D3D);
    const Color headerBg = Color(0xFF2D2D2D);
    const Color rowAlt = Color(0xFF252525);
    const Color rowBg = Color(0xFF1E1E1E);
    const Color headerText = Color(0xFFFF9800);
    const Color cellText = Color(0xFFB0B0B0);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: rowBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade700),
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
          // 表格下方的 blockquote 等额外文字，宽度与表格总列宽一致
          if (extraContent != null && extraContent.trim().isNotEmpty)
            Container(
              width: totalTableWidth,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Text(
                extraContent,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.5,
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

  Widget _markdownView(String content, ScrollController scrollController) {
    if (content.trim().isEmpty) return const SizedBox.shrink();
    // 把 Obsidian wiki 链接 [[XXX]] 转换为普通文字 XXX
    final converted = content.replaceAllMapped(
      RegExp(r'\[\[([^\]]+)\]\]'),
      (m) => m.group(1) ?? m.group(0) ?? '',
    );
    return Markdown(
      controller: scrollController,
      data: converted,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
        h1: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        h2: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        h3: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        listBullet: const TextStyle(color: Colors.white70),
        code: TextStyle(color: Colors.cyan[300], backgroundColor: Colors.grey[900]),
        codeblockDecoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: Colors.blue[300]!, width: 3),
          ),
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.grey[700]!, width: 1),
          ),
        ),
      ),
      selectable: true,
    );
  }

  /// 从 frontmatter 提取配方相关字段，生成结构化表格
  Widget _buildFormulaTable() {
    final fields = <MapEntry<String, String>>[];

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
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '配方信息',
              style: TextStyle(
                color: Colors.orange,
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
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      e.value,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// 查找并渲染关联的产品配方（文件名以产品牌号开头，如 RS7767-银.md 对应 RS7767）
  Widget _buildLinkedFormulas() {
    final matchedFormulas = widget.formulas.where((f) {
      // 精确匹配：配方文件名以产品牌号+"-"开头（如 RS7767-银.md 匹配产品 RS7767）
      // experimentalCode 可能指向另一个系列的产品牌号，仅在非空且有明确匹配时才使用
      final hasExperimentalCodeMatch =
          widget.product.experimentalCode != null &&
          widget.product.experimentalCode!.isNotEmpty &&
          f.fileName.startsWith(widget.product.experimentalCode!);
      return f.fileName.startsWith(widget.product.fileName + '-') ||
          hasExperimentalCodeMatch;
    }).toList();

    if (matchedFormulas.isEmpty) return const SizedBox.shrink();

    // 单配方：直接展示
    if (matchedFormulas.length == 1) {
      final formula = matchedFormulas.first;
      final title = '配方：${formula.fileName.replaceAll('.md', '')}';
      final rows = _parseTable(formula.rawContent);
      return _buildFormulaCard(title, formula.rawContent, rows);
    }

    // 多配方：下拉选择器
    final items = matchedFormulas.map((f) {
      return DropdownMenuItem(
        value: matchedFormulas.indexOf(f),
        child: Text(
          f.fileName.replaceAll('.md', ''),
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      );
    }).toList();

    final selectedFormula = matchedFormulas[_selectedFormulaIndex.clamp(0, matchedFormulas.length - 1)];
    final title = '配方：${selectedFormula.fileName.replaceAll('.md', '')}';
    final rows = _parseTable(selectedFormula.rawContent);

    return Column(
      children: [
        // 下拉选择器
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade700),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedFormulaIndex.clamp(0, matchedFormulas.length - 1),
              isExpanded: true,
              dropdownColor: const Color(0xFF2D2D2D),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
              items: items,
              onChanged: (val) {
                if (val != null) setState(() => _selectedFormulaIndex = val);
              },
            ),
          ),
        ),
        _buildFormulaCard(title, selectedFormula.rawContent, rows),
      ],
    );
  }

  Widget _buildFormulaCard(String title, String rawContent, List<List<String>> rows) {
    // 以表格位置为基准提取内容：
    // - 表格前的内容 → 渲染在表格上方
    // - 表格后的内容 → 渲染在表格下方
    // - frontmatter（--- 之间的字段）和 wiki 链接（[[...]]）不显示
    // - 去掉 markdown 格式符号（如 > 、| 、--- 等）
    final preTableLines = <String>[];
    final postTableLines = <String>[];
    bool foundTable = false;
    bool inFrontmatter = false;
    bool frontmatterEnded = false;

    for (final line in rawContent.split('\n')) {
      final trimmed = line.trim();

      // 跟踪 frontmatter 边界
      if (trimmed == '---') {
        if (!inFrontmatter) {
          inFrontmatter = true;
        } else {
          frontmatterEnded = true;
          inFrontmatter = false;
        }
        continue;
      }

      // frontmatter 内容不显示
      if (inFrontmatter) continue;

      // wiki 链接不显示
      if (frontmatterEnded && trimmed.startsWith('[[')) continue;

      // 遇到表格行，切换到 postTable 模式
      if (trimmed.startsWith('|')) {
        foundTable = true;
        continue;
      }

      // 跳过空行和分隔行（---）
      if (trimmed.isEmpty) continue;

      // 收集非表格行：去掉 > 前缀（blockquote），同时把 [[wiki链接]] 转换为普通文字
      var clean = trimmed.startsWith('> ')
          ? trimmed.substring(2).trim()
          : trimmed;
      clean = clean.replaceAllMapped(RegExp(r'\[\[([^\]]+)\]\]'), (m) => m.group(1) ?? clean);

      if (foundTable) {
        postTableLines.add(clean);
      } else {
        preTableLines.add(clean);
      }
    }

    final preContent = preTableLines.join('\n');
    final postContent = postTableLines.join('\n');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.science_outlined, color: Colors.cyan, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.cyan,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.share_outlined, color: Colors.grey, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  tooltip: '分享表格',
                  onPressed: () => _shareTableAsImage(
                    context, title,
                    _parseTable(bodyContent),
                    extraContent: preContent.isNotEmpty
                        ? '$preContent${postContent.isNotEmpty ? '\n$postContent' : ''}'
                        : postContent,
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
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          // 传入去 frontmatter 的纯 markdown 表格内容，_parseTable 只解析 body 中的表格
          String tableBody = rawContent;
          final fmEnd = tableBody.indexOf('---', 4);
          if (fmEnd != -1) tableBody = tableBody.substring(fmEnd + 3).trim();
          _buildMdTable(tableBody),
          // 表格后的额外内容（如施工比例，如有）
          if (postContent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                postContent,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 去掉 frontmatter 部分，只留 body
    String bodyContent = widget.product.rawContent;
    final frontmatterEnd = bodyContent.indexOf('---', 4);
    if (frontmatterEnd != -1) {
      bodyContent = bodyContent.substring(frontmatterEnd + 3).trim();
    }

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
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                      color: Colors.grey[600],
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
                          color: widget.product.folder == '产品列表'
                              ? Colors.blue.withOpacity(0.2)
                              : Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.product.folder,
                          style: TextStyle(
                            color: widget.product.folder == '产品列表'
                                ? Colors.blue[300]
                                : Colors.green[300],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.product.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.grey, height: 1),
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
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                // 配方表格（仅产品应用有配方字段）
                if (widget.product.folder == '产品应用') _buildFormulaTable(),
                // 产品配方 section：文件名以当前产品牌号+"-"开头时显示
                if (widget.product.folder == '产品列表')
                  _buildLinkedFormulas(),
                // MD 内容（不含 frontmatter）
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: _markdownView(bodyContent, scrollController),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
