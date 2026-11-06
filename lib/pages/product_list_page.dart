/// 产品列表主页，支持筛选、收藏与详情入口。
library;

import 'dart:convert';
import 'package:yaml/yaml.dart';
import 'package:flutter/material.dart';
import '../utils/compat_color.dart';
import '../models/product_item.dart';
import '../utils/obsidian_tag_validator.dart';
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

  int _dataRevision = 0;
  void _onDataChanged() {
    if (!mounted || _dataRevision == widget.dataService.revision) return;
    _dataRevision = widget.dataService.revision;
    ProductDetailSheet.hideIfOpen(context);
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _dataRevision = widget.dataService.revision;
    widget.dataService.addListener(_onDataChanged);
    // 不在这里调用MediaQuery，延迟到build中
    FocusManager.instance.addListener(_handleFocusLost);
  }

  @override
  void dispose() {
    widget.dataService.removeListener(_onDataChanged);
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
    final next = shouldShow ? _pullButtonHeight : 0.0;
    if (_pullExtent == next) return;
    setState(() {
      _pullExtent = next;
    });
  }

  void _closePullButton() {
    if (_pullExtent == 0) return;
    setState(() {
      _pullExtent = 0;
    });
  }

  Map<dynamic, dynamic> _editableProductMetadata(String frontmatter) {
    try {
      final parsed = loadYaml(frontmatter);
      return {
        if (parsed is YamlMap)
          for (final entry in parsed.entries) entry.key: entry.value,
      };
    } on YamlException {
      // Older add forms accepted literal scalars through the line-based model.
      // Recover each top-level field independently, preserving valid nested
      // metadata and quoting invalid legacy scalar text on the next save.
      final start = RegExp(r'^([^\s:#][^:]*):[ \t]*(.*)$');
      final blocks = <List<String>>[];
      for (final line in frontmatter.split('\n')) {
        if (start.hasMatch(line)) {
          blocks.add([line]);
        } else if (blocks.isNotEmpty) {
          blocks.last.add(line);
        }
      }
      final recovered = <dynamic, dynamic>{};
      for (final block in blocks) {
        try {
          final parsed = loadYaml(block.join('\n'));
          if (parsed is YamlMap) {
            for (final entry in parsed.entries) {
              recovered[entry.key] = entry.value;
            }
          }
        } on YamlException {
          final match = start.firstMatch(block.first)!;
          recovered[match.group(1)!.trim()] =
              [match.group(2)!, ...block.skip(1)].join('\n').trimRight();
        }
      }
      return recovered;
    }
  }

  String _yamlMetadataValue(dynamic value) {
    if (value is Map) {
      return '{${value.entries.map((e) => '? ${_yamlMetadataValue(e.key)} : ${_yamlMetadataValue(e.value)}').join(', ')}}';
    }
    if (value is List) {
      return '[${value.map(_yamlMetadataValue).join(', ')}]';
    }
    if (value is double && !value.isFinite) {
      return value.isNaN ? '.nan' : (value.isNegative ? '-.inf' : '.inf');
    }
    return jsonEncode(value);
  }

  ({String metadata, String body, String prefix})? _productFrontmatter(
      String content) {
    int? openingStart, metadataStart;
    var offset = 0;
    for (final line in content.split('\n')) {
      final lineEnd = offset + line.length;
      final next = lineEnd < content.length ? lineEnd + 1 : lineEnd;
      if (line.trim() == '---') {
        if (metadataStart == null) {
          openingStart = offset;
          metadataStart = next;
        } else {
          var prefix = content.substring(0, openingStart!);
          if (content.startsWith('\uFEFF') && !prefix.startsWith('\uFEFF')) {
            prefix = '\uFEFF$prefix';
          }
          return (
            metadata: content.substring(metadataStart, offset),
            body: content.substring(next),
            prefix: prefix,
          );
        }
      }
      offset = next;
    }
    return null;
  }

  Future<void> _showAddProductDialog([ProductItem? item]) async {
    _closePullButton();
    if (item != null && item.origin != DataOrigin.user) return;
    final front = item == null
        ? null
        : _productFrontmatter(item.rawContent);
    final original = front == null
        ? <dynamic, dynamic>{}
        : _editableProductMetadata(front.metadata);
    final initial = <String, String?>{
      '工程师': item?.engineer,
      '实验牌号': item?.experimentalCode,
      '固含': item?.solidContent,
      '羟值': item?.hydroxylValue,
      '官能度': item?.functionality,
      '硬度': item?.hardness,
      '光泽(60°)': item?.gloss60,
      '水煮': item?.boilResistance,
      '水接触角': item?.waterContactAngle,
      '技术源': item?.technologySource,
      '对标': item?.benchmark,
      '粘度': item?.viscosity,
    };
    for (final key in initial.keys.toList()) {
      final value = original[key];
      if (original.containsKey(key) &&
          (value == null || value is String || value is num || value is bool)) {
        initial[key] = value?.toString() ?? '';
      }
    }
    TextEditingController field(String key) =>
        TextEditingController(text: initial[key] ?? '');
    final codeController = TextEditingController(
        text: item == null
            ? ''
            : item.filePath.split('/').last.replaceFirst(RegExp(r'\.md$'), ''));
    final decodedTags = original['tags'];
    final tagsController = TextEditingController(
        text: decodedTags is List && decodedTags.every((tag) => tag is String)
            ? decodedTags.cast<String>().join(' ')
            : item?.tags.join(' ') ?? '');
    final engineerController = field('工程师');
    final expCodeController = field('实验牌号');
    final solidController = field('固含');
    final hydroxylController = field('羟值');
    final contactAngleController = field('水接触角');
    final functionalityController = field('官能度');
    final hardnessController = field('硬度');
    final glossController = field('光泽(60°)');
    final boilController = field('水煮');
    final sourceController = field('技术源');
    final benchmarkController = field('对标');
    final viscosityController = field('粘度');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          item == null ? '新增产品信息' : '编辑产品信息',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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
                  hint: '输入自定义产品名称',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tagsController,
                  style: const TextStyle(fontSize: 13),
                  decoration: _roundedInputDecoration(
                    labelText: 'tags',
                    hintText: '用空格分隔，例如 水性 高光',
                  ),
                ),
                const SizedBox(height: 10),
                _buildTwoFieldRow(
                    engineerController, '工程师', expCodeController, '实验牌号'),
                const SizedBox(height: 10),
                _buildTwoFieldRow(
                    solidController, '固含', hydroxylController, '羟值'),
                const SizedBox(height: 10),
                _buildTwoFieldRow(
                    functionalityController, '官能度', hardnessController, '硬度'),
                const SizedBox(height: 10),
                _buildTwoFieldRow(
                    glossController, '光泽(60°)', boilController, '水煮'),
                const SizedBox(height: 10),
                _buildTwoFieldRow(
                    contactAngleController, '水接触角', sourceController, '技术源'),
                const SizedBox(height: 10),
                _buildTwoFieldRow(
                    benchmarkController, '对标', viscosityController, '粘度'),
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
      final tags =
          ObsidianTagValidator.splitSpaceSeparated(tagsController.text);
      final normalizedTags =
          ObsidianTagValidator.validateAndNormalizeTags(tags);
      var markdown = widget.dataService.buildProductMarkdownTemplate(
        tags: normalizedTags,
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
      if (item == null) {
        await widget.dataService.addProductMarkdown(
            code: codeController.text.trim(), markdown: markdown);
      } else {
        // Preserve unknown YAML metadata (including typed map keys) and body.
        // Quote edited scalars so ':' or '#' never become YAML syntax.
        dynamic editedValue(String key, TextEditingController controller) =>
            original.containsKey(key) && controller.text == (initial[key] ?? '')
                ? original[key]
                : controller.text.trim();
        final metadata = <dynamic, dynamic>{
          ...original,
          'tags': normalizedTags,
          '工程师': editedValue('工程师', engineerController),
          '实验牌号': editedValue('实验牌号', expCodeController),
          '固含': editedValue('固含', solidController),
          '羟值': editedValue('羟值', hydroxylController),
          '官能度': editedValue('官能度', functionalityController),
          '硬度': editedValue('硬度', hardnessController),
          '光泽(60°)': editedValue('光泽(60°)', glossController),
          '水煮': editedValue('水煮', boilController),
          '水接触角': editedValue('水接触角', contactAngleController),
          '技术源': editedValue('技术源', sourceController),
          '对标': editedValue('对标', benchmarkController),
          '粘度': editedValue('粘度', viscosityController),
        };
        final hasBom = item.rawContent.startsWith('\uFEFF');
        final body = front?.body ??
            (hasBom ? item.rawContent.substring(1) : item.rawContent);
        // The line-oriented reader needs its fixed, safe field labels bare.
        // All other keys are literals, not YAML syntax or implicit scalars.
        const literalFieldLabels = {
          'tags', '工程师', '实验牌号', '固含', '羟值', '官能度', '硬度',
          '光泽(60°)', '水煮', '水接触角', '技术源', '对标', '粘度',
          '产品状态', '底漆', '中漆', '面漆', '基材',
        };
        final lines = metadata.entries.map((entry) {
          final key = entry.key;
          final renderedKey = literalFieldLabels.contains(key)
              ? key
              : key is Map || key is List
                  ? '? ${_yamlMetadataValue(key)}\n'
                  : _yamlMetadataValue(key);
          return '$renderedKey: ${_yamlMetadataValue(entry.value)}';
        });
        final prefix = front?.prefix ?? (hasBom ? '\uFEFF' : '');
        markdown = '$prefix---\n${lines.join('\n')}\n---\n$body';
        await widget.dataService.updateProductMarkdown(
            item: item, code: codeController.text.trim(), markdown: markdown);
      }
      if (!mounted) return;
      setState(() => _noteResetSignal++);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(item == null ? '产品信息已新增' : '产品信息已更新')));
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
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 1.6),
      ),
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
        Expanded(
            child: _buildRoundedField(
                controller: leftController, label: leftLabel)),
        const SizedBox(width: 10),
        Expanded(
            child: _buildRoundedField(
                controller: rightController, label: rightLabel)),
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
    final fallbackColumn =
        _sortColumn ?? (_columns.isNotEmpty ? _columns.first : null);
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
  void didUpdateWidget(covariant ProductListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataService != widget.dataService) {
      oldWidget.dataService.removeListener(_onDataChanged);
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

  List<ProductItem> _getFilteredItems() {
    final filtered = widget.dataService.products.where((item) {
      if (_typeFilter == '水性') {
        return item.tags.any((tag) => tag.contains('水性'));
      }
      if (_typeFilter == '油性') {
        return !item.tags.any((tag) => tag.contains('水性'));
      }
      return true;
    }).toList();

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final items = _getFilteredItems();

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
                  Icon(Icons.inventory_2_outlined,
                      size: 64, color: Colors.grey[700]),
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
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _showAddProductDialog,
                                child: Center(
                                  child: Text(
                                    '新增产品信息',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.pixels >
                            notification.metrics.minScrollExtent + 0.5) {
                          _closePullButton();
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
                        formulaAssociations:
                            widget.dataService.formulaAssociations,
                        tdsByProduct: widget.dataService.tdsByProduct,
                        tdsForProduct: widget.dataService.tdsForProduct,
                        onEditProduct: _showAddProductDialog,
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
                        preserveLegacyProductSortTies: true,
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
