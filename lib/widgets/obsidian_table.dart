import 'package:flutter/material.dart';
import 'package:reorderables/reorderables.dart';
import '../models/product_item.dart';
import '../services/preferences_service.dart';
import 'note_swipe_tile.dart';
import 'product_detail_sheet.dart';

/// Obsidian 风格的表格组件，支持列拖拽重排和排序
class ObsidianTable extends StatefulWidget {
  final List<ProductItem> items;
  final List<ProductItem> formulas;
  final List<String> defaultColumns;
  final bool isMobile;
  final Function(List<String>) onColumnsChanged;
  final Function(String?) onSortChanged;
  final Function(bool) onSortDirectionChanged;
  final String? currentSortColumn;
  final bool sortDescending;
  final PreferencesService preferencesService;

  const ObsidianTable({
    super.key,
    required this.items,
    required this.formulas,
    required this.defaultColumns,
    required this.isMobile,
    required this.onColumnsChanged,
    required this.onSortChanged,
    required this.onSortDirectionChanged,
    required this.preferencesService,
    this.currentSortColumn,
    this.sortDescending = false,
  });

  @override
  State<ObsidianTable> createState() => _ObsidianTableState();
}

class _ObsidianTableState extends State<ObsidianTable> {
  /// 当前可见列顺序（可拖拽重排）。
  late List<String> _columns;
  /// 是否进入列编辑模式。
  bool _isEditingColumns = false;

  @override
  void initState() {
    super.initState();
    _columns = List.from(widget.defaultColumns);
  }

  void _showColumnEditor() {
    setState(() => _isEditingColumns = true);
  }

  void _saveColumnOrder(List<String> newColumns) {
    setState(() {
      // 同步本地状态并通过回调持久化到偏好设置。
      _columns = newColumns;
      _isEditingColumns = false;
      widget.onColumnsChanged(newColumns);
    });
  }

  List<ProductItem> _getSortedItems() {
    // 无排序列时直接返回原始数据，避免额外拷贝。
    if (widget.currentSortColumn == null) return widget.items;

    final sortCol = widget.currentSortColumn!;
    final sorted = List<ProductItem>.from(widget.items);

    sorted.sort((a, b) {
      final aVal = a.getTableFields()[sortCol] ?? '';
      final bVal = b.getTableFields()[sortCol] ?? '';
      final result = aVal.compareTo(bVal);
      return widget.sortDescending ? -result : result;
    });

    return sorted;
  }

  bool _isWaterBased(ProductItem item) {
    return item.tags.any((t) => t.contains('水性'));
  }

  Future<void> _openNoteEditor(ProductItem item) async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => NoteEditorDialog(
        title: item.displayName,
        initialValue: widget.preferencesService.getProductNote(item.displayName),
      ),
    );
    if (note == null) return;
    await widget.preferencesService.saveProductNote(item.displayName, note);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditingColumns) {
      return _buildColumnEditor();
    }
    return _buildTable();
  }

  Widget _buildColumnEditor() {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: cs.surfaceContainer,
          child: Row(
            children: [
              Text(
                '拖动调整列顺序',
                style: TextStyle(color: cs.onSurface, fontSize: 16),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _isEditingColumns = false),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _saveColumnOrder(_columns),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
        Expanded(
          // ReorderableWrap 支持拖拽后自动换行，适合移动端窄屏。
          child: ReorderableWrap(
            spacing: 8,
            runSpacing: 8,
            padding: const EdgeInsets.all(16),
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _columns.removeAt(oldIndex);
                _columns.insert(newIndex, item);
              });
            },
            children: _columns.map((col) {
              return Container(
                key: ValueKey(col),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(col, style: TextStyle(color: cs.onSurface)),
                    const SizedBox(width: 8),
                    Icon(Icons.drag_handle, color: cs.onSurfaceVariant, size: 20),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTable() {
    final cs = Theme.of(context).colorScheme;
    final sortedItems = _getSortedItems();

    if (widget.isMobile) {
      // 移动端使用卡片化信息密度，提升触控可读性。
      return ListView.builder(
        itemCount: sortedItems.length,
        itemBuilder: (context, index) {
          final item = sortedItems[index];
          final fields = item.getTableFields();

          return NoteSwipeTile(
            onNoteTap: () => _openNoteEditor(item),
            noteButtonInsets: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            noteButtonBorderRadius: const BorderRadius.horizontal(
              left: Radius.circular(12),
            ),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: InkWell(
                onTap: () => ProductDetailSheet.show(context, item, formulas: widget.formulas),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 44,
                            decoration: BoxDecoration(
                              color: item.folder == '产品列表'
                                  ? (_isWaterBased(item)
                                      ? Colors.blue.shade400
                                      : Colors.orange.shade400)
                                  : cs.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              fields[_columns.first] ?? item.displayName,
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                        ],
                      ),
                      if (_columns.length > 1) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: _columns.skip(1).take(4).map((col) {
                            final val = fields[col];
                            if (val == null || val.isEmpty) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                col == '标签' ? val : '$col: $val',
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return Column(
      children: [
        // 桌面端表头：支持点击列名切换排序方向。
        Container(
          color: cs.surfaceContainer,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              ..._columns.map((col) {
                final isSorted = col == widget.currentSortColumn;
                return Expanded(
                  child: InkWell(
                    onTap: () {
                      if (isSorted) {
                        widget.onSortDirectionChanged(!widget.sortDescending);
                      } else {
                        widget.onSortChanged(col);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Text(
                            col,
                            style: TextStyle(
                              color: isSorted ? cs.primary : cs.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isSorted) ...[
                            const SizedBox(width: 4),
                            Icon(
                              widget.sortDescending
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                              size: 14,
                              color: cs.primary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
              IconButton(
                icon: Icon(Icons.edit, color: cs.onSurfaceVariant, size: 20),
                onPressed: _showColumnEditor,
                tooltip: '编辑列',
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          // 表格主体使用斑马纹分层，增强长列表扫描效率。
          child: ListView.builder(
            itemCount: sortedItems.length,
            itemBuilder: (context, index) {
              final item = sortedItems[index];
              final fields = item.getTableFields();

              return NoteSwipeTile(
                onNoteTap: () => _openNoteEditor(item),
                child: InkWell(
                  onTap: () => ProductDetailSheet.show(context, item, formulas: widget.formulas),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    decoration: BoxDecoration(
                      color: index.isEven ? cs.surface : cs.surfaceContainerLowest,
                      border: Border(bottom: BorderSide(color: cs.outlineVariant)),
                    ),
                    child: Row(
                      children: _columns.map((col) {
                        final val = fields[col] ?? '';
                        return Expanded(
                          child: Text(
                            val,
                            style: TextStyle(
                              color: val.isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
