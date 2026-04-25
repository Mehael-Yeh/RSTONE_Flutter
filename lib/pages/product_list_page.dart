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
  bool _pullPinned = false;
  static const double _pullButtonHeight = 72;
  static const double _pullTriggerHeight = 56;

  @override
  void initState() {
    super.initState();
    // 不在这里调用MediaQuery，延迟到build中
  }

  void _updatePullByOverscroll(double overscroll) {
    final next = (_pullExtent + overscroll).clamp(0.0, _pullButtonHeight * 1.3);
    if ((next - _pullExtent).abs() < 0.1) return;
    setState(() => _pullExtent = next);
  }

  void _finishPullGesture() {
    final shouldPin = _pullExtent >= _pullTriggerHeight;
    setState(() {
      _pullPinned = shouldPin;
      _pullExtent = shouldPin ? _pullButtonHeight : 0;
    });
  }

  void _closePullButton() {
    if (_pullExtent == 0 && !_pullPinned) return;
    setState(() {
      _pullExtent = 0;
      _pullPinned = false;
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
    final sourceController = TextEditingController();
    final benchmarkController = TextEditingController();
    final viscosityController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增产品信息'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: '文件名',
                    hintText: 'RD001 或 RS001',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: tagsController,
                  decoration: const InputDecoration(
                    labelText: 'tags',
                    hintText: '用英文逗号分隔，例如 水性, 高光',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(controller: engineerController, decoration: const InputDecoration(labelText: '工程师')),
                const SizedBox(height: 8),
                TextField(controller: expCodeController, decoration: const InputDecoration(labelText: '实验牌号')),
                const SizedBox(height: 8),
                TextField(controller: solidController, decoration: const InputDecoration(labelText: '固含')),
                const SizedBox(height: 8),
                TextField(controller: hydroxylController, decoration: const InputDecoration(labelText: '羟值')),
                const SizedBox(height: 8),
                TextField(controller: contactAngleController, decoration: const InputDecoration(labelText: '水接触角')),
                const SizedBox(height: 8),
                TextField(controller: sourceController, decoration: const InputDecoration(labelText: '技术源')),
                const SizedBox(height: 8),
                TextField(controller: benchmarkController, decoration: const InputDecoration(labelText: '对标')),
                const SizedBox(height: 8),
                TextField(controller: viscosityController, decoration: const InputDecoration(labelText: '粘度')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
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
          : Stack(
              children: [
                NotificationListener<ScrollNotification>(
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
                if (_pullExtent > 0)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 12,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: _pullExtent.clamp(0.0, _pullButtonHeight).toDouble(),
                      child: Material(
                        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _showAddProductDialog,
                          child: const Center(
                            child: Text(
                              '新增产品信息',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
