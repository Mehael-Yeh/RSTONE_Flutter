import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
    for (final line in rawContent.split('
')) {
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

  /// 用 PictureRecorder 绘制完整配方卡片（不受屏幕裁剪限制）
  Future<void> _shareCardAsImage(String title, String rawContent) async {
    try {
      // 解析配方内容
      final metrics = _measureTable(rawContent);
      if (metrics == null || metrics.rows.isEmpty) return;

      final header = metrics.rows.first;
      final dataRows = metrics.rows.length > 1 ? metrics.rows.sublist(1) : <List<String>>[];
      final colWidths = metrics.colWidths;
      final totalW = colWidths.reduce((a, b) => a + b);
      const double scale = 2.0;
      const double rowH = 36.0;
      const double headerH = 38.0;
      const double cellHP = 12.0;
      const double cardPadding = 16.0;
      const double headerBarH = 44.0;
      const double preH = 30.0;
      const double postH = 40.0;

      // 计算各部分高度
      double titleH = headerBarH;
      double preContentH = metrics.preContent.isNotEmpty ? preH : 0;
      double tableH = headerH + dataRows.length * rowH;
      double postContentH = metrics.postContent.isNotEmpty ? postH : 0;
      double totalH = titleH + preContentH + tableH + postContentH + cardPadding * 2;

      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder);
      c.scale(scale, scale);

      // 背景
      c.drawRect(Rect.fromLTWH(0, 0, totalW + cardPadding * 2, totalH),
          Paint()..color = const Color(0xFF2D2D2D));

      // 卡片边框
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, totalW + cardPadding * 2, totalH),
              const Radius.circular(12)),
          Paint()
            ..color = Colors.grey.shade800
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);

      // === 标题栏 ===
      double y = cardPadding;
      c.drawRect(Rect.fromLTWH(0, y, totalW + cardPadding * 2, titleH),
          Paint()..color = const Color(0xFF2D2D2D));
      _drawText(c, title, 13, const Color(0xFF00BCD4),
          Rect.fromLTWH(cardPadding + 20, y + 12, totalW, 20), bold: true);
      // 标题栏左侧图标装饰
      c.drawCircle(Offset(cardPadding + 8, y + titleH / 2), 4,
          Paint()..color = const Color(0xFF00BCD4));
      // 分享按钮装饰
      c.drawRect(Rect.fromLTWH(totalW + cardPadding - 40, y + 10, 24, 24),
          Paint()..color = Colors.grey.shade700);

      y += titleH;

      // === preContent ===
      if (preContentH > 0) {
        _drawText(c, metrics.preContent, 12, Colors.white70,
            Rect.fromLTWH(cardPadding, y, totalW, preContentH),
            height: 1.5);
        y += preContentH;
      }

      // === 表格 ===
      // 表头
      double tx = cardPadding;
      c.drawRect(Rect.fromLTWH(tx, y, totalW, headerH),
          Paint()..color = const Color(0xFF2D2D2D));
      for (int i = 0; i < colWidths.length; i++) {
        c.drawRect(Rect.fromLTWH(tx, y, colWidths[i], headerH),
            Paint()..color = Colors.grey.shade800);
        _drawCell(c, header[i], tx, y, colWidths[i], headerH,
            const Color(0xFFFF9800), cellHP, bold: true);
        tx += colWidths[i];
      }
      c.drawRect(Rect.fromLTWH(tx, y, totalW, headerH),
          Paint()
            ..color = Colors.grey.shade700
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5);
      y += headerH;

      // 数据行
      for (int ri = 0; ri < dataRows.length; ri++) {
        final row = dataRows[ri];
        if (ri.isOdd) {
          c.drawRect(Rect.fromLTWH(cardPadding, y, totalW, rowH),
              Paint()..color = const Color(0xFF252525));
        }
        tx = cardPadding;
        for (int i = 0; i < colWidths.length; i++) {
          _drawCell(c, i < row.length ? row[i] : '', tx, y,
              colWidths[i], rowH, const Color(0xFFB0B0B0), cellHP);
          tx += colWidths[i];
        }
        // 底边框
        c.drawLine(Offset(cardPadding, y + rowH),
            Offset(cardPadding + totalW, y + rowH),
            Paint()..color = const Color(0xFF3D3D3D)..strokeWidth = 0.5);
        y += rowH;
      }

      // 整个表格边框
      c.drawRect(Rect.fromLTWH(cardPadding, y - tableH, totalW, tableH),
          Paint()
            ..color = Colors.grey.shade700
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);

      // === postContent ===
      if (postContentH > 0) {
        y += 8;
        _drawText(c, metrics.postContent, 12, Colors.white70,
            Rect.fromLTWH(cardPadding, y, totalW, postContentH),
            height: 1.5);
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage(
          ((totalW + cardPadding * 2) * scale).toInt(),
          (totalH * scale).toInt());
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 绘制单元格文字
  void _drawCell(Canvas c, String text, double x, double y,
      double w, double h, Color color, double padding,
      {bool bold = false}) {
    if (text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: w - padding * 2);
    tp.paint(c, Offset(x + padding, y + (h - tp.height) / 2));
  }

  /// 绘制多行文字
  void _drawText(Canvas c, String text, double fontSize, Color color,
      Rect rect, {bool bold = false, double height = 1.0}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            height: height),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: rect.width);
    tp.paint(c, Offset(rect.left, rect.top));
  }

  double _textWidth(String text, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    return tp.width;
  }


  /// 配方表格测量数据结构
  class _TableMetrics {
    final List<List<String>> rows;      // 所有行（含表头）
    final List<double> colWidths;        // 每列宽度
    final double totalWidth;            // 表格总宽
    final String preContent;            // 表格前内容
    final String postContent;           // 表格后内容（如施工比例）
    _TableMetrics(this.rows, this.colWidths, this.totalWidth,
        this.preContent, this.postContent);
  }

  /// 解析配方内容，测量列宽，返回 TableMetrics
  /// 解析逻辑与 _buildMdTable 完全一致，确保分享绘制与界面渲染的列宽相同
  _TableMetrics? _measureTable(String rawContent) {
    final preLines = <String>[];
    final postLines = <String>[];
    bool foundTable = false;
    bool inFrontmatter = false;
    bool frontmatterEnded = false;

    for (final line in rawContent.split('
')) {
      final trimmed = line.trim();
      if (trimmed == '---') {
        if (!inFrontmatter) { inFrontmatter = true; }
        else { frontmatterEnded = true; inFrontmatter = false; }
        continue;
      }
      if (inFrontmatter) continue;
      if (frontmatterEnded && trimmed.startsWith('[[')) continue;
      if (trimmed.startsWith('|')) { foundTable = true; continue; }
      if (trimmed.isEmpty) continue;
      var clean = trimmed.startsWith('> ')
          ? trimmed.substring(2).trim()
          : trimmed;
      clean = clean.replaceAllMapped(RegExp(r'\[\[([^\]]+)\]\]'),
          (m) => m.group(1) ?? clean);
      if (foundTable) { postLines.add(clean); }
      else { preLines.add(clean); }
    }

    final preContent = preLines.join('
');
    final postContent = postLines.join('
');

    // 去掉 frontmatter
    String body = rawContent;
    final fmEnd = body.indexOf('---', 4);
    if (fmEnd != -1) body = body.substring(fmEnd + 3).trim();

    final rows = _parseTable(body);
    if (rows.isEmpty) return null;

    final header = rows.first;
    final colCount = header.length;
    final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];

    const double minW = 60.0, maxW = 300.0, cellHP = 12.0;
    List<double> colWidths = List.filled(colCount, minW);
    void measureCol(int col, String text) {
      final w = _textWidth(text, 12) + cellHP * 2;
      if (w > colWidths[col]) colWidths[col] = w.clamp(minW, maxW);
    }
    for (int i = 0; i < colCount; i++) measureCol(i, header[i]);
    for (final row in dataRows) {
      for (int i = 0; i < row.length; i++) measureCol(i, row[i]);
    }
    while (colWidths.length < colCount) colWidths.add(minW);
    final totalWidth = colWidths.reduce((a, b) => a + b);

    return _TableMetrics(rows, colWidths, totalWidth, preContent, postContent);
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
      return _buildFormulaCard(title, formula.rawContent);
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
        _buildFormulaCard(title, selectedFormula.rawContent),
      ],
    );
  }

  Widget _buildFormulaCard(String title, String rawContent) {
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

    for (final line in rawContent.split('
')) {
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

    final preContent = preTableLines.join('
');
    final postContent = postTableLines.join('
');

    // 去掉 frontmatter，只保留 body（表格和表格外内容）
    String bodyContent = rawContent;
    final fmEnd = bodyContent.indexOf('---', 4);
    if (fmEnd != -1) bodyContent = bodyContent.substring(fmEnd + 3).trim();

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
                  onPressed: () => _shareCardAsImage(title, rawContent),
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
          _buildMdTable(bodyContent),
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
