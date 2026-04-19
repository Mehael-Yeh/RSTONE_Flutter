import 'package:flutter/material.dart';
import '../models/product_item.dart';
import '../services/obsidian_data_service.dart';
import '../services/preferences_service.dart';
import '../widgets/note_swipe_tile.dart';
import '../widgets/product_detail_sheet.dart';
import 'settings_page.dart';

class SearchPage extends StatefulWidget {
  final ObsidianDataService dataService;
  final PreferencesService preferencesService;
  final Future<void> Function(ThemeMode) onThemeModeChanged;
  final Color themeSeedColor;
  final Future<void> Function(Color) onThemeSeedColorChanged;
  final ThemeMode themeMode;
  final int pageChangeSignal;

  const SearchPage({
    super.key,
    required this.dataService,
    required this.preferencesService,
    required this.onThemeModeChanged,
    required this.themeSeedColor,
    required this.onThemeSeedColorChanged,
    required this.themeMode,
    this.pageChangeSignal = 0,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with WidgetsBindingObserver {
  /// 搜索输入控制器。
  final TextEditingController _searchController = TextEditingController();
  /// 搜索框焦点控制（用于生命周期时主动收起键盘）。
  final FocusNode _searchFocusNode = FocusNode();
  /// 当前搜索结果集合。
  List<ProductItem> _results = [];
  /// 搜索框中是否存在关键词。
  bool _isSearching = false;
  /// 是否展示结果区域（仅在有输入时展示）。
  bool _showResults = false;
  int _noteResetSignal = 0;

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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _searchFocusNode.unfocus();
    }
  }

  void _onSearchChanged() {
    ProductDetailSheet.hideIfOpen(context);
    final query = _searchController.text.trim();
    // 输入非空时切换到“搜索态”。
    setState(() {
      _isSearching = query.isNotEmpty;
      _showResults = query.isNotEmpty;
      _noteResetSignal++;
    });

    if (query.isEmpty) {
      // 清空输入后立即清空结果，避免显示旧数据。
      setState(() => _results = []);
      return;
    }

    // 轻量防抖，降低频繁输入时的检索开销。
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
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageChangeSignal != widget.pageChangeSignal) {
      setState(() => _noteResetSignal++);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 统一使用语义色，避免硬编码颜色导致主题割裂。
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '锐石',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () {
                      _searchFocusNode.unfocus();
                      ProductDetailSheet.hideIfOpen(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SettingsPage(
                            dataService: widget.dataService,
                            preferencesService: widget.preferencesService,
                            themeMode: widget.themeMode,
                            onThemeModeChanged: widget.onThemeModeChanged,
                            themeSeedColor: widget.themeSeedColor,
                            onThemeSeedColorChanged: widget.onThemeSeedColorChanged,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SearchBar(
                controller: _searchController,
                focusNode: _searchFocusNode,
                hintText: '搜索产品、标签...',
                leading: const Icon(Icons.search),
                trailing: _isSearching
                    ? [
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _showResults = false;
                              _results = [];
                            });
                          },
                        )
                      ]
                    : null,
                elevation: WidgetStateProperty.all(0),
                // 使用容器高层级色强化输入控件与背景的层级关系。
                backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
                side: WidgetStatePropertyAll(
                  BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
                ),
              ),
            ),
            if (_isSearching && _results.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '找到 ${_results.length} 个结果',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ),
            Expanded(
              child: _showResults
                  ? _results.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _results.length,
                          itemBuilder: (context, index) => _buildResultItem(_results[index]),
                        )
                  : _buildIdleState(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleState() {
    final style = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Center(
      // 初始引导态：提示可搜索字段。
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.diamond_outlined, size: 64, color: cs.outline),
          const SizedBox(height: 16),
          Text('输入关键词搜索', style: style.titleMedium),
          const SizedBox(height: 6),
          Text('支持产品名称、标签等', style: style.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final style = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Center(
      // 搜索无结果态：给出明确反馈，减少误操作困惑。
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 56, color: cs.outline),
          const SizedBox(height: 12),
          Text('未找到相关结果', style: style.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildResultItem(ProductItem item) {
    final cs = Theme.of(context).colorScheme;
    final isProductList = item.folder == '产品列表';
    final tagColor = isProductList ? cs.primary : cs.tertiary;

    return NoteSwipeTile(
      onNoteTap: () => _openNoteEditor(item),
      resetSignal: _noteResetSignal,
      noteButtonInsets: const EdgeInsets.only(bottom: 10),
      noteButtonBorderRadius: const BorderRadius.horizontal(
        left: Radius.circular(16),
      ),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: InkWell(
          onTap: () {
            _searchFocusNode.unfocus();
            ProductDetailSheet.show(
              context,
              item,
              formulas: widget.dataService.formulas,
              tdsContent: widget.dataService.tdsForProduct(item.fileName),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Center(
                  child: Container(
                    // 左侧竖条作为信息类型视觉锚点（产品/应用）。
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tagColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.displayName,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(isProductList ? '产品' : '应用'),
                            labelStyle: Theme.of(context).textTheme.labelSmall,
                            backgroundColor: tagColor.withOpacity(0.14),
                            side: BorderSide(
                              color: tagColor.withOpacity(0.35),
                            ),
                          ),
                        ],
                      ),
                      if (_buildSubtitleParts(item).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _buildSubtitleChips(item),
                      ],
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<String> _buildSubtitleParts(ProductItem item) {
    if (item.folder == '产品应用') {
      return <String>[
        if ((item.primer ?? '').isNotEmpty) '底: ${item.primer}',
        if ((item.midCoat ?? '').isNotEmpty) '中: ${item.midCoat}',
        if ((item.topCoat ?? '').isNotEmpty) '面: ${item.topCoat}',
      ];
    }
    return item.tags.take(4).toList();
  }

  Widget _buildSubtitleChips(ProductItem item) {
    final parts = _buildSubtitleParts(item);
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: 22,
      child: Row(
        children: [
          for (int index = 0; index < parts.take(3).length; index++) ...[
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Text(
                  parts[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ),
            ),
            if (index < parts.take(3).length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

}
