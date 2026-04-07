import 'package:flutter/material.dart';
import '../models/product_item.dart';
import '../services/obsidian_data_service.dart';
import '../widgets/product_detail_sheet.dart';
import 'settings_page.dart';

/// 搜索页面（主界面）
class SearchPage extends StatefulWidget {
  final ObsidianDataService dataService;

  const SearchPage({super.key, required this.dataService});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<ProductItem> _results = [];
  bool _isSearching = false;
  bool _showResults = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus && _searchController.text.isNotEmpty) {
        setState(() => _showResults = true);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    setState(() {
      _isSearching = query.isNotEmpty;
      _showResults = query.isNotEmpty;
    });
    
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    
    // 延迟搜索，避免频繁搜索
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_searchController.text.trim() == query) {
        final results = widget.dataService.search(query);
        if (mounted) {
          setState(() => _results = results);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部应用标题
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Row(
                children: [
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.orange[400]!, Colors.orange[700]!],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.diamond, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '锐石 RSTONE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white70),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SettingsPage(dataService: widget.dataService),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            // 搜索框区域
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              padding: EdgeInsets.symmetric(
                horizontal: 24,
                vertical: _isSearching ? 8 : 24,
              ),
              child: Column(
                children: [
                  // 搜索框
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: _isSearching ? 48 : 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: _isSearching
                          ? []
                          : [
                              BoxShadow(
                                color: Colors.orange.withOpacity(0.1),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: '搜索产品、标签...',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                        suffixIcon: _isSearching
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _showResults = false;
                                    _results = [];
                                  });
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                      onTap: () {
                        if (_searchController.text.isNotEmpty) {
                          setState(() => _showResults = true);
                        }
                      },
                    ),
                  ),
                  // 结果数量
                  if (_isSearching && _results.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '找到 ${_results.length} 个结果',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            // 结果列表
            Expanded(
              child: _showResults
                  ? _results.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Colors.grey[700]),
                              const SizedBox(height: 16),
                              Text(
                                '未找到相关结果',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final item = _results[index];
                            return _buildResultItem(item);
                          },
                        )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.diamond_outlined, size: 80, color: Colors.grey[800]),
                          const SizedBox(height: 16),
                          Text(
                            '输入关键词搜索',
                            style: TextStyle(color: Colors.grey[600], fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '支持产品名称、标签等',
                            style: TextStyle(color: Colors.grey[700], fontSize: 14),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultItem(ProductItem item) {
    final isProductList = item.folder == '产品列表';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF2D2D2D),
      child: InkWell(
        onTap: () => ProductDetailSheet.show(context, item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 类型标签
              Container(
                width: 4,
                height: 50,
                decoration: BoxDecoration(
                  color: isProductList ? Colors.blue : Colors.green,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 16),
              // 内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: (isProductList ? Colors.blue : Colors.green)
                                .withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isProductList ? '产品' : '应用',
                            style: TextStyle(
                              color: isProductList ? Colors.blue[300] : Colors.green[300],
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (item.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: item.tags.take(4).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 11,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
