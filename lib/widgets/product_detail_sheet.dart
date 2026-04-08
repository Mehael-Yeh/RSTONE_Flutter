import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/product_item.dart';

/// 产品详情底部弹窗
class ProductDetailSheet extends StatelessWidget {
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

  /// 查找并渲染关联的产品配方（文件名以产品牌号开头，如 RS7767-银.md 对应 RS7767）
  List<Widget> _buildLinkedFormulas(ProductItem product) {
    final matchedFormulas = formulas.where((f) {
      return f.fileName.startsWith(product.fileName) ||
          f.fileName.startsWith(product.experimentalCode ?? '');
    }).toList();

    if (matchedFormulas.isEmpty) return [];

    return matchedFormulas.map((formula) {
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.science_outlined, color: Colors.cyan, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '配方：${formula.fileName.replaceAll('.md', '')}',
                      style: const TextStyle(
                        color: Colors.cyan,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildMdTable(formula.rawContent),
            const SizedBox(height: 8),
          ],
        ),
      );
    }).toList();
  }

  /// 从 frontmatter 提取配方相关字段，生成结构化表格
  Widget _buildFormulaTable() {
    final fields = <MapEntry<String, String>>[];

    void add(String label, String? value) {
      if (value != null && value.isNotEmpty) {
        fields.add(MapEntry(label, value));
      }
    }

    add('底漆', product.primer);
    add('中漆', product.midCoat);
    add('面漆', product.topCoat);
    add('基材', product.baseMaterial);

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

  /// 渲染配方 markdown 表格（无 frontmatter，内容即表格）
  Widget _buildMdTable(String rawContent) {
    final rows = <List<String>>[];
    for (final line in rawContent.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // 判断是否为分隔行（全是 -: 和空白）
      bool isSep = true;
      for (final cell in trimmed.split('|')) {
        final t = cell.trim();
        if (t.isNotEmpty && !RegExp(r'^[-:]+$').hasMatch(t)) {
          isSep = false;
          break;
        }
      }
      if (isSep) continue;
      // 解析表格行
      final cols = trimmed.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (cols.isNotEmpty) rows.add(cols);
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    // 首行为表头
    final header = rows.first;
    final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.grey.shade800),
          dataRowColor: WidgetStateProperty.resolveWith((_) => Colors.transparent),
          columns: header.map((h) => DataColumn(
            label: Text(h, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
          )).toList(),
          rows: dataRows.asMap().entries.map((e) {
            return DataRow(
              color: WidgetStateProperty.all(e.key.isOdd ? Colors.grey.shade900 : Colors.transparent),
              cells: e.value.map((cell) => DataCell(
                Text(cell, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              )).toList(),
            );
          }).toList(),
        ),
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

  @override
  Widget build(BuildContext context) {
    // 去掉 frontmatter 部分，只留 body
    String bodyContent = product.rawContent;
    final frontmatterEnd = bodyContent.indexOf('---', 4);
    if (frontmatterEnd != -1) {
      bodyContent = bodyContent.substring(frontmatterEnd + 3).trim();
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
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
                        color: product.folder == '产品列表'
                            ? Colors.blue.withOpacity(0.2)
                            : Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        product.folder,
                        style: TextStyle(
                          color: product.folder == '产品列表'
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
                        product.displayName,
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
              if (product.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: product.tags.map((tag) {
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
              if (product.folder == '产品应用') _buildFormulaTable(),
              // 产品配方 section：文件名以当前产品牌号开头时显示
              if (product.folder == '产品列表')
                ..._buildLinkedFormulas(product),
              // MD 内容（不含 frontmatter）
              Expanded(
                child: _markdownView(bodyContent, scrollController),
              ),
            ],
          ),
        );
      },
    );
  }
}
