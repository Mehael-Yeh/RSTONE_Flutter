/// 产品应用列表页面，按场景展示配方与说明。

import 'package:flutter/material.dart';
import '../models/product_item.dart';
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
  State<ProductApplicationsPage> createState() => _ProductApplicationsPageState();
}

class _ProductApplicationsPageState extends State<ProductApplicationsPage> {
  // 默认列（移动端）
  static const List<String> _mobileDefaultColumns = ['名称', '标签', '底漆', '中漆', '面漆'];
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

  @override
  void initState() {
    super.initState();
    // 不在这里调用MediaQuery，延迟到didChangeDependencies
    FocusManager.instance.addListener(_handleFocusLost);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusLost);
    super.dispose();
  }

  void _handleFocusLost() {
    if (FocusManager.instance.primaryFocus == null) {
      _closePullButtons();
    }
  }

  void _updatePullByOverscroll(double overscroll) {
    final next = (_pullExtent + overscroll).clamp(0.0, _pullButtonHeight * 1.3);
    if ((next - _pullExtent).abs() < 0.1) return;
    setState(() => _pullExtent = next);
  }

  void _finishPullGesture() {
    final shouldShow = _pullExtent >= _pullTriggerHeight;
    setState(() {
      _pullExtent = shouldShow ? _pullButtonHeight : 0;
    });
  }

  void _closePullButtons() {
    if (_pullExtent == 0) return;
    setState(() => _pullExtent = 0);
  }

  Future<void> _showAddFormulaDialog() async {
    _closePullButtons();
    final nameController = TextEditingController();
    final tableController = TextEditingController(
      text: '| 原料 | 百分比 |\n| --- | --- |\n| 示例原料A | |\n| 示例原料B | |',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          '新增产品配方',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '配方文件名',
                  labelStyle: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tableController,
                minLines: 8,
                maxLines: 14,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '配方 Markdown 表格',
                  labelStyle: TextStyle(fontSize: 12),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
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
      final markdown = widget.dataService.buildFormulaMarkdownTemplate(
        tableMarkdown: tableController.text,
      );
      await widget.dataService.addFormulaMarkdown(
        name: nameController.text.trim(),
        markdown: markdown,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('产品配方已新增')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('新增失败：$e')));
    }
  }

  Future<void> _showAddApplicationDialog() async {
    _closePullButtons();
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
                _buildTwoFieldRow(nameController, '名称', primerController, '底漆'),
                const SizedBox(height: 10),
                _buildTwoFieldRow(midController, '中漆', topController, '面漆'),
                const SizedBox(height: 10),
                TextField(
                  controller: tagsController,
                  style: const TextStyle(fontSize: 13),
                  decoration: _roundedInputDecoration(labelText: 'tags（英文逗号分隔）'),
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
          .split(RegExp(r'[,，]'))
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('产品应用已新增')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('新增失败：$e')));
    }
  }

  InputDecoration _roundedInputDecoration({required String labelText}) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: const TextStyle(fontSize: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除新增项目')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败：$e')));
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
    final fallbackColumn = _sortColumn ?? (_columns.isNotEmpty ? _columns.first : null);
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
    if (oldWidget.pageChangeSignal != widget.pageChangeSignal) {
      setState(() => _noteResetSignal++);
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
      
      final result = aVal.compareTo(bVal);
      return _sortDescending ? -result : result;
    });
    
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final items = _getSortedItems();

    return Scaffold(
      appBar: AppBar(
        title: const Text('产品应用'),
        actions: [
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
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                _closePullButtons();
              },
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: _pullExtent.clamp(0.0, _pullButtonHeight).toDouble(),
                    padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                    alignment: Alignment.center,
                    child: _pullExtent <= 0
                        ? const SizedBox.shrink()
                        : Card(
                            margin: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            clipBehavior: Clip.antiAlias,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Material(
                                    color: Theme.of(context).colorScheme.primaryContainer,
                                    child: InkWell(
                                      onTap: _showAddFormulaDialog,
                                      child: Center(
                                        child: Text(
                                          '新增产品配方',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const VerticalDivider(width: 1),
                                Expanded(
                                  child: Material(
                                    color: Theme.of(context).colorScheme.secondaryContainer,
                                    child: InkWell(
                                      onTap: _showAddApplicationDialog,
                                      child: Center(
                                        child: Text(
                                          '新增产品应用',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.onSecondaryContainer,
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
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.pixels > notification.metrics.minScrollExtent + 0.5) {
                          _closePullButtons();
                        }
                        if (notification is OverscrollNotification &&
                            notification.metrics.pixels <= notification.metrics.minScrollExtent &&
                            notification.overscroll < 0) {
                          _updatePullByOverscroll(-notification.overscroll);
                        } else if (notification is ScrollEndNotification) {
                          _finishPullGesture();
                        }
                        return false;
                      },
                      child: ObsidianTable(
                        items: items,
                        formulas: widget.dataService.formulas,
                        tdsByProduct: widget.dataService.tdsByProduct,
                        defaultColumns: _columns,
                        availableColumns: isMobile ? _mobileDefaultColumns : _desktopDefaultColumns,
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
  }
}
