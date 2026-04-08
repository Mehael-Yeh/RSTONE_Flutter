import 'package:flutter/material.dart';
import 'package:reorderables/reorderables.dart';
import '../models/product_item.dart';
import 'product_detail_sheet.dart';

/// Obsidian 风格的表格组件，支持列拖拽重排和排序
/// 
/// 支持两种视图模式：
/// - 移动端：卡片式列表展示
/// - 桌面端：完整表格展示
/// 
/// 用户可点击表头进行升序/降序切换，也可编辑列的显示顺序。
class ObsidianTable extends StatefulWidget {
  /// 数据项列表
  final List<ProductItem> items;
  /// 配方列表（用于详情弹窗）
  final List<ProductItem> formulas;
  /// 默认显示的列
  final List<String> defaultColumns;
  /// 是否为移动端视图
  final bool isMobile;
  /// 列顺序变更回调
  final Function(List<String>) onColumnsChanged;
  /// 排序列变更回调
  final Function(String?) onSortChanged;
  /// 排序方向变更回调
  final Function(bool) onSortDirectionChanged;
  /// 当前排序列
  final String? currentSortColumn;
  /// 是否降序
  final bool sortDescending;

  const ObsidianTable({
    super.key,
    required this.items,
    required this.formulas,
    required this.defaultColumns,
    required this.isMobile,
    required this.onColumnsChanged,
    required this.onSortChanged,
    required this.onSortDirectionChanged,
    this.currentSortColumn,
    this.sortDescending = false,
  });

  @override
  State<ObsidianTable> createState() => _ObsidianTableState();
}

class _ObsidianTableState extends State<ObsidianTable> {
  /// 当前显示的列顺序
  late List<String> _columns;
  /// 是否处于列编辑模式
  bool _isEditingColumns = false;

  @override
  void initState() {
    super.initState();
    _columns = List.from(widget.defaultColumns);
  }

  /// 显示排序选择底部弹窗
  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2D2D2D),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '选择排序列',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(color: Colors.grey),
              ..._columns.map((col) {
                final isSelected = col == widget.currentSortColumn;
                return ListTile(
                  title: Text(
                    col,
                    style: TextStyle(
                      color: isSelected ? Colors.orange : Colors.white,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(
                          widget.sortDescending
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                          color: Colors.orange,
                        )
                      : null,
                  onTap: () {
                    if (isSelected) {
                      // 已选中的列再次点击则切换排序方向
                      widget.onSortDirectionChanged(!widget.sortDescending);
                    } else {
                      widget.onSortChanged(col);
                    }
                    Navigator.pop(context);
                  },
                );
              }),
              if (widget.currentSortColumn != null)
                ListTile(
                  title: const Text(
                    '清除排序',
                    style: TextStyle(color: Colors.grey),
                  ),
                  onTap: () {
                    widget.onSortChanged(null);
                    Navigator.pop(context);
                  },
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  /// 进入列编辑模式
  void _showColumnEditor() {
    setState(() {
      _isEditingColumns = true;
    });
  }

  /// 保存新的列顺序
  void _saveColumnOrder(List<String> newColumns) {
    setState(() {
      _columns = newColumns;
      _isEditingColumns = false;
      widget.onColumnsChanged(newColumns);
    });
  }

  /// 获取排序后的数据列表
  List<ProductItem> _getSortedItems() {
    if (widget.currentSortColumn == null) return widget.items;
    
    final sortCol = widget.currentSortColumn!;
    final sorted = List<ProductItem>.from(widget.items);
    
    sorted.sort((a, b) {
      final aFields = a.getTableFields();
      final bFields = b.getTableFields();
      
      final aVal = aFields[sortCol] ?? '';
      final bVal = bFields[sortCol] ?? '';
      
      final result = aVal.compareTo(bVal);
      return widget.sortDescending ? -result : result;
    });
    
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    // 列编辑模式和表格展示模式二选一
    if (_isEditingColumns) {
      return _buildColumnEditor();
    }
    return _buildTable();
  }

  Widget _buildColumnEditor() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF2D2D2D),
          child: Row(
            children: [
              const Text(
                '拖动调整列顺序',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _isEditingColumns = false),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _saveColumnOrder(_columns),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
        Expanded(
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
                  color: const Color(0xFF3D3D3D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      col,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.drag_handle, color: Colors.grey, size: 20),
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
    final sortedItems = _getSortedItems();
    
    // 移动端简化显示
    if (widget.isMobile) {
      return ListView.builder(
        itemCount: sortedItems.length,
        itemBuilder: (context, index) {
          final item = sortedItems[index];
          final fields = item.getTableFields();
          
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: const Color(0xFF2D2D2D),
            child: InkWell(
              onTap: () => ProductDetailSheet.show(context, item, formulas: widget.formulas),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            fields[_columns.first] ?? item.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
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
                              color: Colors.grey[800],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$col: $val',
                              style: TextStyle(color: Colors.grey[400], fontSize: 12),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
    
    // 桌面端完整表格
    return Column(
      children: [
        // 表头
        Container(
          color: const Color(0xFF2D2D2D),
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
                              color: isSorted ? Colors.orange : Colors.white,
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
                              color: Colors.orange,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.grey, size: 20),
                onPressed: _showColumnEditor,
                tooltip: '编辑列',
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.grey),
        // 表格内容
        Expanded(
          child: ListView.builder(
            itemCount: sortedItems.length,
            itemBuilder: (context, index) {
              final item = sortedItems[index];
              final fields = item.getTableFields();
              
              return InkWell(
                onTap: () => ProductDetailSheet.show(context, item, formulas: widget.formulas),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  decoration: BoxDecoration(
                    color: index % 2 == 0
                        ? const Color(0xFF1E1E1E)
                        : const Color(0xFF252525),
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[800]!),
                    ),
                  ),
                  child: Row(
                    children: _columns.map((col) {
                      final val = fields[col] ?? '';
                      return Expanded(
                        child: Text(
                          val,
                          style: TextStyle(
                            color: val.isEmpty ? Colors.grey[600] : Colors.white70,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
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
