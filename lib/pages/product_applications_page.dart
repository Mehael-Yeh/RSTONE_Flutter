import 'package:flutter/material.dart';
import '../models/product_item.dart';
import '../services/obsidian_data_service.dart';
import '../services/preferences_service.dart';
import '../widgets/obsidian_table.dart';

/// 产品应用页面
class ProductApplicationsPage extends StatefulWidget {
  final ObsidianDataService dataService;
  final PreferencesService preferencesService;

  const ProductApplicationsPage({
    super.key,
    required this.dataService,
    required this.preferencesService,
  });

  @override
  State<ProductApplicationsPage> createState() => _ProductApplicationsPageState();
}

class _ProductApplicationsPageState extends State<ProductApplicationsPage> {
  // 默认列（移动端）
  static const List<String> _mobileDefaultColumns = ['名称', '基材', '底漆', '中漆', '面漆'];
  // 默认列（桌面端）
  static const List<String> _desktopDefaultColumns = [
    '名称',
    '基材',
    '底漆',
    '中漆',
    '面漆',
    '标签',
  ];

  List<String> _columns = [];
  String? _sortColumn;
  bool _sortDescending = false;
  static const String _nameSortColumn = '名称';

  @override
  void initState() {
    super.initState();
    // 不在这里调用MediaQuery，延迟到didChangeDependencies
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
    _sortColumn = widget.preferencesService.getApplicationSort();
    _sortDescending = widget.preferencesService.getApplicationSortDesc();
  }

  void _onColumnsChanged(List<String> columns) {
    widget.preferencesService.saveApplicationColumns(columns);
    setState(() => _columns = columns);
  }

  void _onSortChanged(String? column) {
    widget.preferencesService.saveApplicationSort(column);
    widget.preferencesService.saveApplicationSortDesc(false);
    setState(() {
      _sortColumn = column;
      _sortDescending = false;
    });
  }

  void _onSortDirectionChanged(bool descending) {
    widget.preferencesService.saveApplicationSortDesc(descending);
    setState(() => _sortDescending = descending);
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
            tooltip: '排序',
            icon: const Icon(Icons.sort_by_alpha),
            onSelected: (descending) {
              _onSortChanged(_nameSortColumn);
              _onSortDirectionChanged(descending);
            },
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
          : ObsidianTable(
              items: items,
              formulas: widget.dataService.formulas,
              defaultColumns: _columns,
              isMobile: isMobile,
              onColumnsChanged: _onColumnsChanged,
              onSortChanged: _onSortChanged,
              onSortDirectionChanged: _onSortDirectionChanged,
              preferencesService: widget.preferencesService,
              currentSortColumn: _sortColumn,
              sortDescending: _sortDescending,
            ),
    );
  }
}
