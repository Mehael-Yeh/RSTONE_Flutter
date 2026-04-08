import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/product_item.dart';

/// 产品详情底部弹窗
class ProductDetailSheet extends StatefulWidget {
  final ProductItem product;
  final List<ProductItem> formulas;

  const ProductDetailSheet({super.key, required this.product, this.formulas = const []});

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
  int _selectedFormulaIndex = 0;

  /// 解析 markdown 表格数据
  List<List<String>> _parseTable(String rawContent) {
    final rows = <List<String>>[];
    for (final line in rawContent.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
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
      final cols = trimmed.split('|').map((s) => s.trim()).toList();
      // 去掉首尾空字符串（首尾 | 产生的空列）
      while (cols.isNotEmpty && cols.first.isEmpty) cols.removeAt(0);
      while (cols.isNotEmpty && cols.last.isEmpty) cols.removeLast();
      if (cols.isNotEmpty) rows.add(cols);
    }
    return rows;
  }

  /// 用 Canvas 完整渲染表格为 PNG（不依赖截图，保证所有行都渲染）
  Future<void> _shareTableAsImage(
    BuildContext context,
    String title,
    List<List<String>> rows,
  ) async {
    if (rows.isEmpty) return;
    try {
      const double rowHeight = 36.0;
      const double headerHeight = 40.0;
      const double cellPaddingH = 16.0;
      const double colMinWidth = 80.0;

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
      final totalHeight = headerHeight + dataRows.length * rowHeight + 4;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // 背景
      canvas.drawRect(
        Rect.fromLTWH(0, 0, totalWidth, totalHeight),
        Paint()..color = const Color(0xFF1E1E1E),
      );

      // 表头背景
      canvas.drawRect(
        Rect.fromLTWH(0, 0, totalWidth, headerHeight),
        Paint()..color = const Color(0xFF2D2D2D),
      );

      // 绘制表头
      double x = 0;
      for (int i = 0; i < colCount; i++) {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, colWidths[i], headerHeight),
          Paint()..color = Colors.grey.shade800,
        );
        _drawCell(canvas, header[i], x, 0, colWidths[i], headerHeight,
            const Color(0xFFFF9800), true);
        x += colWidths[i];
      }

      // 绘制数据行
      for (int r = 0; r < dataRows.length; r++) {
        final row = dataRows[r];
        final y = headerHeight + r * rowHeight;
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
      maxLines: 1,
      ellipsis: '…',
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
  /// 同时返回非表格内容供外部渲染
  Widget _buildMdTable(String rawContent, {required Function(String) onNonTableContent}) {
    final rows = _parseTable(rawContent);
    if (rows.isEmpty) {
      // 没有表格时，把全部内容当非表格内容处理
      onNonTableContent(rawContent);
      return const SizedBox.shrink();
    }

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

    const Color borderColor = Color(0xFF3D3D3D);
    const Color headerBg = Color(0xFF2D2D2D);
    const Color rowAlt = Color(0xFF252525);
    const Color rowBg = Color(0xFF1E1E1E);
    const Color headerText = Color(0xFFFF9800);
    const Color cellText = Color(0xFFB0B0B0);

    // 计算表格总宽度
    final tableWidth = colWidths.reduce((a, b) => a + b);

    // 提取表格部分的起始和结束位置
    final tableLines = <String>[];
    bool inTable = false;
    for (final line in rawContent.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // 检测是否是表格分隔行
      bool isSep = true;
      for (final cell in trimmed.split('|')) {
        final t = cell.trim();
        if (t.isNotEmpty && !RegExp(r'^[-:]+$').hasMatch(t)) {
          isSep = false;
          break;
        }
      }
      if (isSep) {
        if (!inTable) {
          inTable = true;
          tableLines.add(line);
        } else {
          tableLines.add(line);
        }
        continue;
      }
      if (inTable) {
        tableLines.add(line);
      } else {
        // 表格前的非表格内容
        final nonTablePart = tableLines.join('\n');
        if (nonTablePart.isNotEmpty) {
          onNonTableContent(nonTablePart);
        }
        tableLines.clear();
        tableLines.add(line);
        inTable = true;
      }
    }
    // 表格后的非表格内容
    if (tableLines.isNotEmpty && inTable) {
      final tableContent = tableLines.join('\n');
      final nonTablePart = _extractNonTableAfterTable(rawContent, tableContent);
      if (nonTablePart.isNotEmpty) {
        onNonTableContent(nonTablePart);
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      width: tableWidth,
      decoration: BoxDecoration(
        color: rowBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: SingleChildScrollView(
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
    );
  }

  /// 从原始内容中提取表格之后的非表格内容
  String _extractNonTableAfterTable(String rawContent, String tableContent) {
    final tableIndex = rawContent.indexOf(tableContent);
    if (tableIndex == -1) return '';
    final afterTable = rawContent.substring(tableIndex + tableContent.length);
    // 提取非表格内容（跳过空行）
    final lines = afterTable.split('\n');
    final nonTableLines = <String>[];
    bool foundContent = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (foundContent) nonTableLines.add(line);
        continue;
      }
      // 检查是否是表格分隔行
      bool isSep = true;
      for (final cell in trimmed.split('|')) {
        final t = cell.trim();
        if (t.isNotEmpty && !RegExp(r'^[-:]+$').hasMatch(t)) {
          isSep = false;
          break;
        }
      }
      if (isSep) continue;
      foundContent = true;
      nonTableLines.add(line);
    }
    return nonTableLines.join('\n').trim();
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _markdownView(String content, ScrollController scrollController) {
    if (content.trim().isEmpty) return const SizedBox.shrink();
    return Markdown(
      controller: scrollController,
      data: content,
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
    // 使用 experimentalCode 进行匹配（如果存在），否则使用 fileName
    // 注意：只有 experimentalCode 非空时才进行匹配，避免空字符串匹配所有配方
    final productCode = widget.product.experimentalCode;
    
    final matchedFormulas = widget.formulas.where((f) {
      if (productCode != null && productCode.isNotEmpty) {
        // 如果有 experimentalCode，精确匹配以该代码开头的配方
        return f.fileName.startsWith(productCode);
      }
      // 如果没有 experimentalCode，使用 fileName 匹配
      // 但要求配方文件名与产品文件名相同或以产品文件名开头
      return f.fileName == widget.product.fileName ||
          f.fileName.startsWith(widget.product.fileName + '-');
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
    // 非表格内容
    final List<String> nonTableContents = [];

    // 计算表格总宽度
    double tableWidth = 200;
    if (rows.isNotEmpty) {
      const double minColWidth = 60.0;
      const double maxColWidth = 300.0;
      const double cellHPadding = 12.0;
      final colCount = rows.first.length;
      List<double> colWidths = List.filled(colCount, minColWidth);
      for (final row in rows) {
        for (int i = 0; i < row.length && i < colCount; i++) {
          final w = _textWidth(row[i], 12) + cellHPadding * 2;
          colWidths[i] = w.clamp(minColWidth, maxColWidth);
        }
      }
      tableWidth = colWidths.reduce((a, b) => a + b);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 配方卡片
        Container(
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
                      onPressed: () => _shareTableAsImage(context, title, rows),
                    ),
                  ],
                ),
              ),
              _buildMdTable(rawContent, onNonTableContent: (content) {
                if (content.trim().isNotEmpty) {
                  nonTableContents.add(content);
                }
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
        // 非表格内容：直接写在配方下面，宽度与表格一致
        for (final content in nonTableContents)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            width: tableWidth,
            child: _markdownView(content, ScrollController()),
          ),
      ],
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

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.3, 0.5, 0.65, 0.8, 0.95],
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // 拖动条
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
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
              // 产品配方 section：文件名以当前产品牌号开头时显示
              if (widget.product.folder == '产品列表')
                _buildLinkedFormulas(),
              // MD 内容（不含 frontmatter）
              Flexible(
                child: _markdownView(bodyContent, scrollController),
              ),
            ],
          ),
        );
      },
    );
  }
}
