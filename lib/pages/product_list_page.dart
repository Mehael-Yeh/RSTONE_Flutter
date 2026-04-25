/// 产品列表主页，支持筛选、收藏与详情入口。

import 'package:flutter/material.dart';
import '../models/product_item.dart';
import '../services/obsidian_data_service.dart';
import '../services/preferences_service.dart';
import '../widgets/obsidian_table.dart';
import '../widgets/product_detail_sheet.dart';

/// 产品列表页面
class ProductListPage extends StatefulWidget {
  final ObsidianDataService dataService;
  final PreferencesService preferencesService;
  final int pageChangeSignal;

  const ProductListPage({
    super.key,
    required this.dataService,
    required this.preferencesService,
    this.pageChangeSignal = 0,
  });

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  // 默认列（移动端）
  static const List<String> _mobileDefaultColumns = ['牌号', '标签'];
  // 默认列（桌面端）
  static const List<String> _desktopDefaultColumns = [
    '牌号',
    '标签',
    '实验牌号',
    '工程师',
    '固含',
    '羟值',
    '官能度',
    '硬度',
    '光泽(60°)',
    '水煮',
    '水接触角',
    '技术源',
    '对标',
    '粘度',
  ];

  List<String> _columns = [];
  String? _sortColumn;
  bool _sortDescending = false;
  String _typeFilter = '全部';
  int _noteResetSignal = 0;
  double _pullExtent = 0;
  static const double _pullButtonHeight = 58;
  static const double _pullTriggerHeight = 56;

  @override
  void initState() {
    super.initState();
    // 不在这里调用MediaQuery，延迟到build中
    FocusManager.instance.addListener(_handleFocusLost);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusLost);
    super.dispose();
  }

  void _handleFocusLost() {
    if (FocusManager.instance.primaryFocus == null) {
      _closePullButton();
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

  void _closePullButton() {
    if (_pullExtent == 0) return;
    setState(() {
      _pullExtent = 0;
    });
  }

  Future<void> _showAddProductDialog() async {
    _closePullButton();
    final codeController = TextEditingController();
    final tagsController = TextEditingController();
    final engineerController = TextEditingController();
    final expCodeController = TextEditingController();
    final solidController = TextEditingController();
    final hydroxylController = TextEditingController();
    final contactAngleController = TextEditingController();
    final functionalityController = TextEditingController();
    final hardnessController = TextEditingController();
    final glossController = TextEditingController();
    final boilController = TextEditingController();
    final sourceController = TextEditingController();
    final benchmarkController = TextEditingController();
    final viscosityController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          '新增产品信息',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRoundedField(
                  controller: codeController,
                  label: '文件名',
                  hint: 'RD001 或 RS001',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tagsController,
                  style: const TextStyle(fontSize: 13),
                  decoration: _roundedInputDecoration(
                    labelText: 'tags',
                    hintText: '用英文逗号分隔，例如 水性, 高光',
                  ),
                ),
                const SizedBox(height: 10),
                _buildTwoFieldRow(engineerController, '工程师', expCodeController, '实验牌号'),
                const SizedBox(height: 10),
                _buildTwoFieldRow(solidController, '固含', hydroxylController, '羟值'),
                const SizedBox(height: 10),
                _buildTwoFieldRow(functionalityController, '官能度', hardnessController, '硬度'),
                const SizedBox(height: 10),
                _buildTwoFieldRow(glossController, '光泽(60°)', boilController, '水煮'),
                const SizedBox(height: 10),
                _buildTwoFieldRow(contactAngleController, '水接触角', sourceController, '技术源'),
                const SizedBox(height: 10),
                _buildTwoFieldRow(benchmarkController, '对标', viscosityController, '粘度'),
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
      final markdown = widget.dataService.buildProductMarkdownTemplate(
        tags: tags,
        engineer: engineerController.text.trim(),
        experimentalCode: expCodeController.text.trim(),
        solidContent: solidController.text.trim(),
        hydroxylValue: hydroxylController.text.trim(),
        functionality: functionalityController.text.trim(),
        hardness: hardnessController.text.trim(),
        gloss60: glossController.text.trim(),
        boilResistance: boilController.text.trim(),
        waterContactAngle: contactAngleController.text.trim(),
        technologySource: sourceController.text.trim(),
        benchmark: benchmarkController.text.trim(),
        viscosity: viscosityController.text.trim(),
      );
      await widget.dataService.addProductMarkdown(
        code: codeController.text.trim(),
        markdown: markdown,
      );
      if (!mounted) return;
      setState(() => _noteResetSignal++);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('产品信息已新增')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('新增失败：$e')));
    }
  }

  InputDecoration _roundedInputDecoration({
    required String labelText,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      labelStyle: const TextStyle(fontSize: 12),
      hintStyle: const TextStyle(fontSize: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      isDense: true,
    );
  }

  Widget _buildRoundedField({
    required TextEditingController controller,
    required String label,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13),
      decoration: _roundedInputDecoration(labelText: label, hintText: hint),
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
        Expanded(child: _buildRoundedField(controller: leftController, label: leftLabel)),
        const SizedBox(width: 10),
        Expanded(child: _buildRoundedField(controller: rightController, label: rightLabel)),
      ],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initColumns();
  }

  void _initColumns() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final defaults = isMobile ? _mobileDefaultColumns : _desktopDefaultColumns;
    _columns = widget.preferencesService.getProductListColumns(defaults);
    _sortColumn = widget.preferencesService.getProductListSort();
    _sortDescending = widget.preferencesService.getProductListSortDesc();
  }

  void _onColumnsChanged(List<String> columns) {
    ProductDetailSheet.hideIfOpen(context);
    widget.preferencesService.saveProductListColumns(columns);
    setState(() {
      _columns = columns;
      _noteResetSignal++;
    });
  }

  void _onSortChanged(String? column) {
    ProductDetailSheet.hideIfOpen(context);
    widget.preferencesService.saveProductListSort(column);
    widget.preferencesService.saveProductListSortDesc(false);
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
      widget.preferencesService.saveProductListSort(fallbackColumn);
    }
    widget.preferencesService.saveProductListSortDesc(descending);
    setState(() {
      _sortColumn = fallbackColumn;
      _sortDescending = descending;
      _noteResetSignal++;
    });
  }

  @override
  void didUpdateWidget(covariant ProductListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageChangeSignal != widget.pageChangeSignal) {
      setState(() => _noteResetSignal++);
    }
  }

  List<ProductItem> _getSortedItems() {
    final filtered = widget.dataService.products.where((item) {
      if (_typeFilter == '水性') {
        return item.tags.any((tag) => tag.contains('水性'));
      }
      if (_typeFilter == '油性') {
        return !item.tags.any((tag) => tag.contains('水性'));
      }
      return true;
    }).toList();

    if (_sortColumn == null) return filtered;

    final sorted = List<ProductItem>.from(filtered);
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
        title: const Text('产品列表'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_alt_outlined),
            tooltip: '筛选',
            onSelected: (value) {
              ProductDetailSheet.hideIfOpen(context);
              setState(() {
                _typeFilter = value;
                _noteResetSignal++;
              });
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem<String>(
                value: '全部',
                checked: _typeFilter == '全部',
                child: const Text('全部'),
              ),
              CheckedPopupMenuItem<String>(
                value: '水性',
                checked: _typeFilter == '水性',
                child: const Text('水性'),
              ),
              CheckedPopupMenuItem<String>(
                value: '油性',
                checked: _typeFilter == '油性',
                child: const Text('油性'),
              ),
            ],
          ),
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
      body: widget.dataService.products.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[700]),
                  const SizedBox(height: 16),
                  Text(
                    '暂无产品数据',
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
                _closePullButton();
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
                            color: Theme.of(context).colorScheme.secondaryContainer,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: _showAddProductDialog,
                              child: Center(
                                child: Text(
                                  '新增产品信息',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.pixels > notification.metrics.minScrollExtent + 0.5) {
                          _closePullButton();
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
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
