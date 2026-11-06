/// 产品应用列表页面，按场景展示配方与说明。
library;

import 'package:flutter/material.dart';
import '../utils/app_shapes.dart';
import '../utils/compat_color.dart';
import '../models/product_item.dart';
import '../widgets/formula_editor_dialog.dart';
import '../widgets/formula_draft_list_dialog.dart';
import '../utils/natural_sort.dart';
import '../services/obsidian_data_service.dart';
import '../services/preferences_service.dart';
import '../widgets/obsidian_table.dart';
import '../widgets/product_detail_sheet.dart';

/// 产品应用页面
class ProductApplicationsPage extends StatefulWidget {
  final ObsidianDataService dataService;
  final PreferencesService preferencesService;
  final int pageChangeSignal;

  const ProductApplicationsPage({
    super.key,
    required this.dataService,
    required this.preferencesService,
    this.pageChangeSignal = 0,
  });

  @override
  State<ProductApplicationsPage> createState() =>
      _ProductApplicationsPageState();
}

class _ProductApplicationsPageState extends State<ProductApplicationsPage> {
  // 默认列（移动端）
  static const List<String> _mobileDefaultColumns = [
    '名称',
    '标签',
    '底漆',
    '中漆',
    '面漆'
  ];
  // 默认列（桌面端）
  static const List<String> _desktopDefaultColumns = [
    '名称',
    '标签',
    '底漆',
    '中漆',
    '面漆',
  ];

  List<String> _columns = [];
  String? _sortColumn;
  bool _sortDescending = false;
  int _noteResetSignal = 0;
  double _pullExtent = 0;
  static const double _pullButtonHeight = 58;
  static const double _pullTriggerHeight = 56;

  int _dataRevision = 0;
  void _onDataChanged() {
    if (!mounted || _dataRevision == widget.dataService.revision) return;
    _dataRevision = widget.dataService.revision;
    if (widget.dataService.applications.isEmpty) _pullExtent = 0;
    ProductDetailSheet.hideIfOpen(context);
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _dataRevision = widget.dataService.revision;
    widget.dataService.addListener(_onDataChanged);
    // 不在这里调用MediaQuery，延迟到didChangeDependencies
  }

  @override
  void dispose() {
    widget.dataService.removeListener(_onDataChanged);
    super.dispose();
  }

  void _updatePullByOverscroll(double overscroll) {
    final next = (_pullExtent + overscroll).clamp(0.0, _pullButtonHeight * 1.3);
    if ((next - _pullExtent).abs() < 0.1) return;
    setState(() => _pullExtent = next);
  }

  void _finishPullGesture() {
    final next = _pullExtent >= _pullTriggerHeight ? _pullButtonHeight : 0.0;
    if (_pullExtent == next) return;
    setState(() => _pullExtent = next);
  }

  void _closePullButtons() {
    if (_pullExtent == 0) return;
    setState(() => _pullExtent = 0);
  }

  Future<void> _showAddFormulaDialog() async {
    await showDialog<void>(
        context: context,
        builder: (_) => FormulaEditorDialog(dataService: widget.dataService));
  }

  Future<void> _showAddApplicationDialog() async {
    final nameController = TextEditingController();
    final tagsController = TextEditingController();
    final primerController = TextEditingController();
    final midController = TextEditingController();
    final topController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          '新增产品应用',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRoundedField(nameController, '名称'),
                ExpansionTile(
                  title: const Text('补充应用资料（可选）'),
                  children: [
                _buildRoundedField(primerController, '底漆（可选）'),
                const SizedBox(height: 10),
                _buildTwoFieldRow(midController, '中漆', topController, '面漆'),
                const SizedBox(height: 10),
                TextField(
                  controller: tagsController,
                  style: const TextStyle(fontSize: 13),
                  decoration: _roundedInputDecoration(
                    labelText: '标签（可选，空格分隔）',
                    hintText: '例如 水性 高光',
                  ),
                ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(fontSize: 13)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final tags = tagsController.text
          .split(RegExp(r'[\s,，]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final markdown = widget.dataService.buildApplicationMarkdownTemplate(
        tags: tags,
        primer: primerController.text.trim(),
        midCoat: midController.text.trim(),
        topCoat: topController.text.trim(),
      );
      await widget.dataService.addApplicationMarkdown(
        name: nameController.text.trim(),
        markdown: markdown,
      );
      if (!mounted) return;
      setState(() => _noteResetSignal++);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('产品应用已新增')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('新增失败：$e')));
    }
  }

  InputDecoration _roundedInputDecoration({
    required String labelText,
    String? hintText,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: cs.surfaceContainerHighest.withCompatOpacity(0.35),
      labelStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      hintStyle: TextStyle(
          fontSize: 12, color: cs.onSurfaceVariant.withCompatOpacity(0.85)),
      border: OutlineInputBorder(
        borderRadius: AppShapes.borderRadius,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppShapes.borderRadius,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppShapes.borderRadius,
        borderSide: BorderSide(color: cs.primary, width: 1.6),
      ),
      isDense: true,
    );
  }

  Widget _buildRoundedField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13),
      decoration: _roundedInputDecoration(labelText: label),
    );
  }

  Widget _buildTwoFieldRow(
    TextEditingController leftController,
    String leftLabel,
    TextEditingController rightController,
    String rightLabel,
  ) {
    return Row(
      children: [
        Expanded(child: _buildRoundedField(leftController, leftLabel)),
        const SizedBox(width: 10),
        Expanded(child: _buildRoundedField(rightController, rightLabel)),
      ],
    );
  }

  Future<void> _deleteManualItem(ProductItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除新增项目'),
        content: Text('确认删除“${item.displayName}”吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.dataService.deleteManualItem(item);
      if (!mounted) return;
      setState(() => _noteResetSignal++);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已删除新增项目')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initColumns();
  }

  void _initColumns() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final defaults = isMobile ? _mobileDefaultColumns : _desktopDefaultColumns;
    _columns = widget.preferencesService.getApplicationColumns(defaults);
    _columns = _columns.where(defaults.contains).toList();
    if (_columns.isEmpty) {
      _columns = List.from(defaults);
    }
    _sortColumn = widget.preferencesService.getApplicationSort();
    _sortDescending = widget.preferencesService.getApplicationSortDesc();
  }

  void _onColumnsChanged(List<String> columns) {
    ProductDetailSheet.hideIfOpen(context);
    widget.preferencesService.saveApplicationColumns(columns);
    setState(() {
      _columns = columns;
      _noteResetSignal++;
    });
  }

  void _onSortChanged(String? column) {
    ProductDetailSheet.hideIfOpen(context);
    widget.preferencesService.saveApplicationSort(column);
    widget.preferencesService.saveApplicationSortDesc(false);
    setState(() {
      _sortColumn = column;
      _sortDescending = false;
      _noteResetSignal++;
    });
  }

  void _onSortDirectionChanged(bool descending) {
    ProductDetailSheet.hideIfOpen(context);
    final fallbackColumn =
        _sortColumn ?? (_columns.isNotEmpty ? _columns.first : null);
    if (fallbackColumn != null && _sortColumn == null) {
      widget.preferencesService.saveApplicationSort(fallbackColumn);
    }
    widget.preferencesService.saveApplicationSortDesc(descending);
    setState(() {
      _sortColumn = fallbackColumn;
      _sortDescending = descending;
      _noteResetSignal++;
    });
  }

  @override
  void didUpdateWidget(covariant ProductApplicationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataService != widget.dataService) {
      oldWidget.dataService.removeListener(_onDataChanged);
      _pullExtent = 0;
      _dataRevision = widget.dataService.revision;
      widget.dataService.addListener(_onDataChanged);
      ProductDetailSheet.hideIfOpen(context);
    }
    if (oldWidget.pageChangeSignal != widget.pageChangeSignal) {
      setState(() {
        _noteResetSignal++;
        _pullExtent = 0;
      });
    }
  }

  List<ProductItem> _getSortedItems() {
    if (_sortColumn == null) return widget.dataService.applications;

    final sorted = List<ProductItem>.from(widget.dataService.applications);
    sorted.sort((a, b) {
      final aFields = a.getTableFields();
      final bFields = b.getTableFields();

      final aVal = aFields[_sortColumn] ?? '';
      final bVal = bFields[_sortColumn] ?? '';

      final result = compareNaturalText(aVal, bVal);
      return _sortDescending ? -result : result;
    });

    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final items = _getSortedItems();

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('产品应用'),
        bottom: widget.dataService.quarantinedFormulas.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(64),
                child: ListTile(
                  dense: true,
                  title: Text(
                      '${widget.dataService.quarantinedFormulas.length} 份个人配方已隔离；原文保留，可导出后修复。',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  trailing: IconButton(
                      tooltip: '查看隔离详情',
                      icon: const Icon(Icons.warning_amber),
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                                title: const Text('个人配方隔离详情'),
                                content: SingleChildScrollView(
                                    child: SelectableText(widget
                                        .dataService.quarantinedFormulas.entries
                                        .map((e) => '${e.key}：${e.value}')
                                        .join('\n\n'))),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext),
                                      child: const Text('关闭'))
                                ],
                              ))),
                )),
        actions: [
          IconButton(
              tooltip: '新增产品配方',
              icon: const Icon(Icons.add),
              onPressed: _showAddFormulaDialog),
          IconButton(
              tooltip: '待补充配方',
              icon: const Icon(Icons.edit_note),
              onPressed: () => showDialog<void>(context: context,
                  builder: (_) => FormulaDraftListDialog(dataService: widget.dataService))),
          PopupMenuButton<bool>(
            icon: const Icon(Icons.sort_by_alpha),
            onSelected: _onSortDirectionChanged,
            itemBuilder: (context) => const [
              PopupMenuItem<bool>(
                value: false,
                child: Text('A-Z'),
              ),
              PopupMenuItem<bool>(
                value: true,
                child: Text('Z-A'),
              ),
            ],
          ),
        ],
      ),
      body: widget.dataService.applications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.apps_outlined, size: 64, color: Colors.grey[700]),
                  const SizedBox(height: 16),
                  Text(
                    '暂无应用数据',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      widget.dataService.initialize().then((_) {
                        setState(() {});
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新'),
                  ),
                ],
              ),
            )
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              // Handles a deliberate upward drag on the module itself. The
              // table's own scrollable wins its descendant gesture arena.
              onVerticalDragUpdate: (details) {
                if (details.delta.dy < 0) _closePullButtons();
              },
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
              },
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height:
                        _pullExtent.clamp(0.0, _pullButtonHeight).toDouble(),
                    padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                    alignment: Alignment.center,
                    child: _pullExtent <= 0
                        ? const SizedBox.shrink()
                        : AnimatedOpacity(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOut,
                            opacity: (_pullExtent / _pullButtonHeight)
                                .clamp(0.0, 1.0),
                            child: Card(
                              margin: EdgeInsets.zero,
                              shape: AppShapes.rounded,
                              clipBehavior: Clip.antiAlias,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Material(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      child: InkWell(
                                        onTap: _showAddFormulaDialog,
                                        child: Center(
                                          child: Text(
                                            '新增产品配方',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onPrimaryContainer,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const VerticalDivider(width: 1),
                                  Expanded(
                                    child: Material(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer,
                                      child: InkWell(
                                        onTap: _showAddApplicationDialog,
                                        child: Center(
                                          child: Text(
                                            '新增产品应用',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSecondaryContainer,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.axis != Axis.vertical) {
                          return false;
                        }
                        if (notification is ScrollUpdateNotification &&
                            notification.dragDetails != null &&
                            (notification.scrollDelta ?? 0) > 0) {
                          _closePullButtons();
                        }
                        if (notification is OverscrollNotification &&
                            notification.dragDetails != null &&
                            notification.overscroll > 0) {
                          _closePullButtons();
                        }
                        if (notification is OverscrollNotification &&
                            notification.metrics.pixels <=
                                notification.metrics.minScrollExtent &&
                            notification.overscroll < 0) {
                          _updatePullByOverscroll(-notification.overscroll);
                        } else if (notification is ScrollEndNotification) {
                          _finishPullGesture();
                        }
                        return false;
                      },
                      child: ObsidianTable(
                        items: items,
                        productCatalog: widget.dataService.products,
                        formulas: widget.dataService.formulas,
                        tdsByProduct: widget.dataService.tdsByProduct,
                        tdsForProduct: widget.dataService.tdsForProduct,
                        defaultColumns: _columns,
                        availableColumns: isMobile
                            ? _mobileDefaultColumns
                            : _desktopDefaultColumns,
                        isMobile: isMobile,
                        onColumnsChanged: _onColumnsChanged,
                        onSortChanged: _onSortChanged,
                        onSortDirectionChanged: _onSortDirectionChanged,
                        preferencesService: widget.preferencesService,
                        currentSortColumn: _sortColumn,
                        sortDescending: _sortDescending,
                        noteResetSignal: _noteResetSignal,
                        isManualItem: widget.dataService.isManualItem,
                        onDeleteManualItem: _deleteManualItem,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
    return PopScope<Object?>(
      canPop: _pullExtent == 0,
      onPopInvokedWithResult: (didPop, result) {
        // Modal routes own their back events; never collapse behind a dialog.
        if (!didPop && (ModalRoute.of(context)?.isCurrent ?? false)) {
          _closePullButtons();
        }
      },
      child: scaffold,
    );
  }
}
