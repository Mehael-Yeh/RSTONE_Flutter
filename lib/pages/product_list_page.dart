import 'package:flutter/material.dart';
import '../models/product_item.dart';
import '../services/obsidian_data_service.dart';
import '../services/preferences_service.dart';
import '../widgets/obsidian_table.dart';

/// 产品列表页面
class ProductListPage extends StatefulWidget {
  final ObsidianDataService dataService;
  final PreferencesService preferencesService;

  const ProductListPage({
    super.key,
    required this.dataService,
    required this.preferencesService,
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
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initColumns();
  }

  void _initColumns() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final defaults = isMobile ? _mobileDefaultColumns : _desktopDefaultColumns;
    _columns = widget.preferencesService.getProductListColumns(defaults);
    _sortColumn = widget.preferencesService.getProductListSort();
    _sortDescending = widget.preferencesService.getProductListSortDesc();
    _isInitialized = true;
  }

  void _onColumnsChanged(List<String> columns) {
    widget.preferencesService.saveProductListColumns(columns);
    setState(() => _columns = columns);
  }

  void _onSortChanged(String? column) {
    widget.preferencesService.saveProductListSort(column);
    widget.preferencesService.saveProductListSortDesc(false);
    setState(() {
      _sortColumn = column;
      _sortDescending = false;
    });
  }

  void _onSortDirectionChanged(bool descending) {
    widget.preferencesService.saveProductListSortDesc(descending);
    setState(() => _sortDescending = descending);
  }

  List<ProductItem> _getSortedItems() {
    if (_sortColumn == null) return widget.dataService.products;
    
    final sorted = List<ProductItem>.from(widget.dataService.products);
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
    if (!_isInitialized) {
      _initColumns();
    }

    final isMobile = MediaQuery.of(context).size.width < 600;
    final items = _getSortedItems();

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text(
          '产品列表',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              widget.dataService.initialize().then((_) {
                setState(() {});
              });
            },
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
          : ObsidianTable(
              items: items,
              defaultColumns: _columns,
              isMobile: isMobile,
              onColumnsChanged: _onColumnsChanged,
              onSortChanged: _onSortChanged,
              onSortDirectionChanged: _onSortDirectionChanged,
              currentSortColumn: _sortColumn,
              sortDescending: _sortDescending,
            ),
    );
  }
}
