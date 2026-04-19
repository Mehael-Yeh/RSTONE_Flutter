/// Obsidian 风格表格组件，支持多行头与横向滚动。

import 'package:flutter/material.dart';
import '../models/product_item.dart';
import '../services/preferences_service.dart';
import 'note_swipe_tile.dart';
import 'product_detail_sheet.dart';
import 'swipe_note_item_card.dart';

/// Obsidian 风格的表格组件，支持列拖拽重排和排序
class ObsidianTable extends StatefulWidget {
  final List<ProductItem> items;
  final List<ProductItem> formulas;
  final Map<String, String> tdsByProduct;
  final List<String> defaultColumns;
  final List<String> availableColumns;
  final bool isMobile;
  final Function(List<String>) onColumnsChanged;
  final Function(String?) onSortChanged;
  final Function(bool) onSortDirectionChanged;
  final String? currentSortColumn;
  final bool sortDescending;
  final PreferencesService preferencesService;
  final int noteResetSignal;

  const ObsidianTable({
    super.key,
    required this.items,
    required this.formulas,
    required this.tdsByProduct,
    required this.defaultColumns,
    required this.availableColumns,
    required this.isMobile,
    required this.onColumnsChanged,
    required this.onSortChanged,
    required this.onSortDirectionChanged,
    required this.preferencesService,
    this.noteResetSignal = 0,
    this.currentSortColumn,
    this.sortDescending = false,
  });

  @override
  State<ObsidianTable> createState() => _ObsidianTableState();
}

class _ObsidianTableState extends State<ObsidianTable> {
  /// 当前可见列顺序（可拖拽重排）。
  late List<String> _columns;
  /// 全部可配置列（用于编辑显示/隐藏）。
  late List<String> _columnOptions;
  /// 当前显示列集合。
  late Set<String> _visibleColumns;
  /// 桌面端各列宽。
  final Map<String, double> _columnWidths = {};
  /// 是否进入列编辑模式。
  bool _isEditingColumns = false;

  @override
  void initState() {
    super.initState();
    _initColumns();
  }

  @override
  void didUpdateWidget(covariant ObsidianTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.defaultColumns != widget.defaultColumns ||
        oldWidget.availableColumns != widget.availableColumns) {
      _initColumns();
    }
  }

  void _initColumns() {
    _columns = List.from(widget.defaultColumns);
    _columnOptions = List.from(widget.availableColumns);
    for (final col in _columns) {
      if (!_columnOptions.contains(col)) {
        _columnOptions.add(col);
      }
    }
    _visibleColumns = _columns.toSet();
    _columnWidths.clear();
  }

  void _showColumnEditor() {
    setState(() => _isEditingColumns = true);
  }

  void _saveColumnOrder(List<String> newColumns) {
    if (newColumns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一列显示')),
      );
      return;
    }
    setState(() {
      // 同步本地状态并通过回调持久化到偏好设置。
      _columns = newColumns;
      _visibleColumns = _columns.toSet();
      _isEditingColumns = false;
      _columnWidths.clear();
      widget.onColumnsChanged(newColumns);
    });
  }

  void _ensureDesktopWidths(double totalWidth) {
    if (widget.isMobile || _columns.isEmpty) return;
    final tableWidth = (totalWidth - 44).clamp(320.0, double.infinity);
    if (_columnWidths.length == _columns.length &&
        _columns.every(_columnWidths.containsKey)) {
      return;
    }
    final estimated = <String, double>{};
    for (final col in _columns) {
      final headerW = (col.length * 16.0) + 44;
      double maxCellW = headerW;
      for (final item in widget.items.take(40)) {
        final value = item.getTableFields()[col] ?? '';
        final estimate = (value.length * 8.0) + 28;
        if (estimate > maxCellW) maxCellW = estimate;
      }
      estimated[col] = maxCellW.clamp(90.0, 420.0);
    }
    final sum = estimated.values.fold<double>(0, (a, b) => a + b);
    final scale = sum == 0 ? 1.0 : tableWidth / sum;
    for (final col in _columns) {
      _columnWidths[col] = (estimated[col]! * scale).clamp(90.0, 420.0);
    }
    final adjustedSum = _columns.fold<double>(0, (a, c) => a + _columnWidths[c]!);
    final diff = tableWidth - adjustedSum;
    _columnWidths[_columns.last] = (_columnWidths[_columns.last]! + diff).clamp(90.0, 500.0);
  }

  void _resizeColumn(int index, double delta) {
    if (index >= _columns.length - 1) return;
    final currentCol = _columns[index];
    final nextCol = _columns[index + 1];
    final currentWidth = _columnWidths[currentCol] ?? 120;
    final nextWidth = _columnWidths[nextCol] ?? 120;
    final newCurrent = (currentWidth + delta).clamp(90.0, 500.0);
    final appliedDelta = newCurrent - currentWidth;
    final newNext = (nextWidth - appliedDelta).clamp(90.0, 500.0);
    final correctedDelta = nextWidth - newNext;
    setState(() {
      _columnWidths[currentCol] = currentWidth + correctedDelta;
      _columnWidths[nextCol] = newNext;
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

  List<String> _buildMobileSubtitleTokens(ProductItem item, Map<String, String> fields) {
    if (item.folder == '产品列表') {
      return item.tags;
    }

    if (item.folder == '产品应用') {
      return <String>[
        if ((item.primer ?? '').isNotEmpty) '底: ${item.primer}',
        if ((item.midCoat ?? '').isNotEmpty) '中: ${item.midCoat}',
        if ((item.topCoat ?? '').isNotEmpty) '面: ${item.topCoat}',
      ];
    }

    final tokens = <String>[];
    for (final col in _columns.skip(1).take(4)) {
      final val = fields[col];
      if (val == null || val.isEmpty) continue;
      if (col == '标签') {
        tokens.addAll(
          val
              .split(RegExp(r'\s*[,，]\s*'))
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty),
        );
        continue;
      }
      tokens.add('$col: $val');
    }
    return tokens;
  }

  String? _tdsOf(ProductItem item) {
    if (item.folder != '产品列表') return null;
    final direct = widget.tdsByProduct[item.fileName];
    if (direct != null) return direct;

    for (final candidate in _tdsLookupCandidates(item.fileName)) {
      for (final entry in widget.tdsByProduct.entries) {
        if (_normalizeProductKey(entry.key) == candidate) {
          return entry.value;
        }
      }
    }
    return null;
  }

  Iterable<String> _tdsLookupCandidates(String productName) sync* {
    final normalized = _normalizeProductKey(productName);
    if (normalized.isNotEmpty) yield normalized;

    final baseName = productName.split('-').first.trim();
    final normalizedBase = _normalizeProductKey(baseName);
    if (normalizedBase.isNotEmpty && normalizedBase != normalized) {
      yield normalizedBase;
    }

    if (normalized.startsWith('RS')) {
      yield 'RD${normalized.substring(2)}';
    } else if (normalized.startsWith('RD')) {
      yield 'RS${normalized.substring(2)}';
    }
  }

  String _normalizeProductKey(String raw) {
    return raw
        .toUpperCase()
        .replaceAll('.TDS.MD', '')
        .replaceAll('.MD', '')
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
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
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _columnOptions.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _columnOptions.removeAt(oldIndex);
                _columnOptions.insert(newIndex, item);
                _columns = _columnOptions.where(_visibleColumns.contains).toList();
              });
            },
            itemBuilder: (context, index) {
              final col = _columnOptions[index];
              final selected = _visibleColumns.contains(col);
              return Card(
                key: ValueKey(col),
                color: cs.surfaceContainerHigh,
                child: ListTile(
                  dense: true,
                  leading: Checkbox(
                    value: selected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _visibleColumns.add(col);
                        } else {
                          _visibleColumns.remove(col);
                        }
                        _columns = _columnOptions.where(_visibleColumns.contains).toList();
                      });
                    },
                  ),
                  title: Text(col, style: TextStyle(color: cs.onSurface)),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: Icon(Icons.drag_handle, color: cs.onSurfaceVariant),
                  ),
                ),
              );
            },
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

          return SwipeNoteItemCard(
            title: fields[_columns.first] ?? item.displayName,
            subtitleTokens: _columns.length > 1 ? _buildMobileSubtitleTokens(item, fields) : const [],
            indicatorColor: item.folder == '产品列表'
                ? (_isWaterBased(item) ? Colors.blue.shade400 : Colors.orange.shade400)
                : cs.primary,
            onTap: () => ProductDetailSheet.show(
              context,
              item,
              formulas: widget.formulas,
              tdsContent: _tdsOf(item),
            ),
            onNoteTap: () => _openNoteEditor(item),
            noteResetSignal: widget.noteResetSignal,
            titleStyle: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureDesktopWidths(constraints.maxWidth);
        const resizeHandleWidth = 16.0;
        return Column(
          children: [
            Container(
              color: cs.surfaceContainer,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  ..._columns.asMap().entries.map((entry) {
                    final index = entry.key;
                    final col = entry.value;
                    final isSorted = col == widget.currentSortColumn;
                    final width = _columnWidths[col] ?? 120;
                    return SizedBox(
                      width: width,
                      child: Stack(
                        children: [
                          InkWell(
                            onTap: () {
                              if (isSorted) {
                                widget.onSortDirectionChanged(!widget.sortDescending);
                              } else {
                                widget.onSortChanged(col);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      col,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isSorted ? cs.primary : cs.onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
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
                          ),
                          if (index < _columns.length - 1)
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              width: resizeHandleWidth,
                              child: IgnorePointer(
                                child: Center(
                                  child: Icon(
                                    Icons.drag_indicator,
                                    size: 14,
                                    color: cs.outline.withOpacity(0.7),
                                  ),
                                ),
                              ),
                            ),
                          if (index < _columns.length - 1)
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              width: resizeHandleWidth,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeColumn,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onHorizontalDragUpdate: (details) {
                                    _resizeColumn(index, details.delta.dx);
                                  },
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  SizedBox(
                    width: 44,
                    child: IconButton(
                      icon: Icon(Icons.edit, color: cs.onSurfaceVariant, size: 20),
                      onPressed: _showColumnEditor,
                      tooltip: '编辑列',
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: ListView.builder(
                itemCount: sortedItems.length,
                itemBuilder: (context, index) {
                  final item = sortedItems[index];
                  final fields = item.getTableFields();

                  return NoteSwipeTile(
                    onNoteTap: () => _openNoteEditor(item),
                    resetSignal: widget.noteResetSignal,
                    child: InkWell(
                      onTap: () => ProductDetailSheet.show(
                        context,
                        item,
                        formulas: widget.formulas,
                        tdsContent: _tdsOf(item),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        decoration: BoxDecoration(
                          color: index.isEven ? cs.surface : cs.surfaceContainerLowest,
                          border: Border(bottom: BorderSide(color: cs.outlineVariant)),
                        ),
                        child: Row(
                          children: [
                            ..._columns.map((col) {
                              final val = fields[col] ?? '';
                              return SizedBox(
                                width: _columnWidths[col] ?? 120,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Center(
                                    child: Text(
                                      val,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: val.isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(width: 44),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
