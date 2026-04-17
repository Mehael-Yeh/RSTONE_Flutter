import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../services/obsidian_data_service.dart';
import '../services/preferences_service.dart';

/// 设置页面（MD3）
class SettingsPage extends StatefulWidget {
  final ObsidianDataService dataService;
  final PreferencesService preferencesService;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeModeChanged;
  final Color themeSeedColor;
  final Future<void> Function(Color) onThemeSeedColorChanged;

  const SettingsPage({
    super.key,
    required this.dataService,
    required this.preferencesService,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.themeSeedColor,
    required this.onThemeSeedColorChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _appVersion = '...';
  late ThemeMode _selectedThemeMode;
  late Color _selectedThemeSeedColor;
  static const List<Color> _presetThemeColors = <Color>[
    Color(0xFFFF8A00),
    Color(0xFFE53935),
    Color(0xFF8E24AA),
    Color(0xFF3949AB),
    Color(0xFF00897B),
    Color(0xFF43A047),
  ];

  @override
  void initState() {
    super.initState();
    _selectedThemeMode = widget.themeMode;
    _selectedThemeSeedColor = widget.themeSeedColor;
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final pkg = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = 'v${pkg.version}');
  }

  Future<void> _onThemeChanged(ThemeMode mode) async {
    setState(() => _selectedThemeMode = mode);
    await widget.onThemeModeChanged(mode);
  }

  Future<void> _onThemeSeedColorChanged(Color color) async {
    setState(() => _selectedThemeSeedColor = color);
    await widget.onThemeSeedColorChanged(color);
  }

  Future<void> _pickCustomThemeColor() async {
    final initialHex = _selectedThemeSeedColor.value.toRadixString(16).toUpperCase().padLeft(8, '0');
    final controller = TextEditingController(text: '#${initialHex.substring(2)}');
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义主题色'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'HEX 颜色值',
            hintText: '#FF8A00',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final raw = controller.text.trim().replaceAll('#', '');
              final normalized = raw.length == 6 ? 'FF$raw' : raw;
              if (!RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(normalized)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入 6 位或 8 位十六进制颜色值')),
                );
                return;
              }
              Navigator.pop(context, Color(int.parse(normalized, radix: 16)));
            },
            child: const Text('应用'),
          ),
        ],
      ),
    );
    if (picked != null) {
      await _onThemeSeedColorChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalProducts = widget.dataService.products.length;
    final coveredProducts = widget.dataService.products
        .where((product) => widget.dataService.tdsForProduct(product.fileName) != null)
        .length;
    final coveragePercent = totalProducts == 0
        ? 0
        : ((coveredProducts / totalProducts) * 100).round();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildSectionCard(
            title: '外观',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '主题模式',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      label: Text('自动'),
                      icon: Icon(Icons.brightness_auto),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      label: Text('浅色'),
                      icon: Icon(Icons.light_mode),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      label: Text('深色'),
                      icon: Icon(Icons.dark_mode),
                    ),
                  ],
                  selected: {_selectedThemeMode},
                  onSelectionChanged: (selection) {
                    if (selection.isNotEmpty) {
                      _onThemeChanged(selection.first);
                    }
                  },
                  showSelectedIcon: false,
                ),
                const SizedBox(height: 18),
                Text(
                  '主题色',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ..._presetThemeColors.map(
                      (color) => _buildColorSwatch(
                        color: color,
                        selected: _selectedThemeSeedColor.value == color.value,
                        onTap: () => _onThemeSeedColorChanged(color),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickCustomThemeColor,
                      icon: const Icon(Icons.palette_outlined),
                      label: const Text('自定义'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            title: '数据统计',
            child: Column(
              children: [
                _buildInfoTile(icon: Icons.inventory_2, title: '产品数量', value: '${widget.dataService.products.length}'),
                _buildInfoTile(icon: Icons.apps, title: '应用数量', value: '${widget.dataService.applications.length}'),
                _buildInfoTile(icon: Icons.description, title: 'TDS数量', value: '${widget.dataService.tdsByProduct.length}'),
                _buildInfoTile(
                  icon: Icons.pie_chart,
                  title: 'TDS覆盖率',
                  value: '$coveredProducts/$totalProducts ($coveragePercent%)',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            title: '标签搜索规则',
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.rule_folder_outlined),
                  title: const Text('查看/编辑规则文档'),
                  subtitle: const Text('用于搜索同义词扩展，例如 PA6 → 尼龙'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openTagAliasRuleEditor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            title: '日志',
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.list_alt),
                  title: const Text('查看日志'),
                  subtitle: Text('${widget.dataService.logs.length} 条日志'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LogViewerPage(dataService: widget.dataService),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_all),
                  title: const Text('复制日志'),
                  subtitle: const Text('复制所有日志到剪贴板'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    final logs = widget.dataService.logs.join('\n');
                    Clipboard.setData(ClipboardData(text: logs));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('日志已复制到剪贴板')),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: cs.error),
                  title: const Text('清除日志'),
                  subtitle: const Text('清空所有日志记录'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _confirmClearLogs,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            title: '产品笔记',
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('导出产品笔记'),
                  subtitle: const Text('导出 Markdown 文件用于提报'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _exportProductNotes,
                ),
                ListTile(
                  leading: Icon(Icons.delete_sweep_outlined, color: cs.error),
                  title: const Text('清除所有产品笔记'),
                  subtitle: const Text('清空全部项目反馈记录'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _confirmClearAllProductNotes,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            title: '关于',
            child: Column(
              children: [
                _buildInfoTile(icon: Icons.info_outline, title: '版本', value: _appVersion),
                _buildInfoTile(icon: Icons.diamond, title: '应用名称', value: '锐石 / RSTONE'),
                _buildInfoTile(icon: Icons.code, title: '技术栈', value: 'Flutter 3.24'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorSwatch({
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? cs.onSurface : cs.outlineVariant,
            width: selected ? 2.2 : 1.1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : null,
      ),
    );
  }

  Future<void> _openTagAliasRuleEditor() async {
    final controller = TextEditingController(text: widget.dataService.tagAliasRulesRaw);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('标签同义词规则'),
        content: SizedBox(
          width: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '每行一条规则：左侧是可匹配标签（可用“、”分隔多个），右侧是扩展词。\n格式示例：PA、PA6、PA66 -> 尼龙',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 18,
                minLines: 12,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '# 支持注释行\nPA、PA6、PA66 -> 尼龙',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;

    await widget.dataService.saveTagAliasRules(controller.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('标签规则已保存，搜索将立即生效')),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Text(
        value,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  Future<void> _confirmClearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('确定要清除所有日志吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清除')),
        ],
      ),
    );

    if (confirmed == true) {
      widget.dataService.clearLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日志已清除')));
      }
    }
  }

  Future<void> _exportProductNotes() async {
    final notes = widget.preferencesService.getAllProductNotes();
    if (notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可导出的笔记')),
      );
      return;
    }

    final buffer = StringBuffer();
    final sortedKeys = notes.keys.toList()..sort();
    for (final key in sortedKeys) {
      final content = notes[key]?.trim() ?? '';
      if (content.isEmpty) continue;
      buffer.writeln('# $key');
      buffer.writeln(content);
      buffer.writeln();
    }
    final markdownContent = buffer.toString().trim();
    if (markdownContent.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可导出的笔记')),
      );
      return;
    }

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/产品笔记.md');
    await file.writeAsString(markdownContent);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: '产品笔记',
      text: '产品笔记导出文件（Markdown）',
    );
  }

  Future<void> _confirmClearAllProductNotes() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清除笔记'),
        content: const Text('该操作将删除所有产品笔记，是否继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('继续')),
        ],
      ),
    );
    if (confirmed != true) return;

    final reconfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('二次确认'),
        content: const Text('请再次确认：清除后不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('返回')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认清除')),
        ],
      ),
    );
    if (reconfirmed != true) return;

    await widget.preferencesService.clearAllProductNotes();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清除所有产品笔记')));
    }
  }

}

class LogViewerPage extends StatefulWidget {
  final ObsidianDataService dataService;

  const LogViewerPage({super.key, required this.dataService});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_downward),
            onPressed: _scrollToBottom,
            tooltip: '滚动到底部',
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              final logs = widget.dataService.logs.join('\n');
              Clipboard.setData(ClipboardData(text: logs));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已复制')),
              );
            },
            tooltip: '复制日志',
          ),
        ],
      ),
      body: widget.dataService.logs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.article_outlined, size: 64, color: cs.outline),
                  const SizedBox(height: 16),
                  Text('暂无日志', style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              reverse: true,
              padding: const EdgeInsets.all(8),
              itemCount: widget.dataService.logs.length,
              itemBuilder: (context, index) {
                final log = widget.dataService.logs[index];
                Color textColor = cs.onSurface;

                if (log.contains('ERROR')) {
                  textColor = cs.error;
                } else if (log.contains('complete') || log.contains('成功')) {
                  textColor = Colors.green.shade400;
                } else if (log.contains('Starting') || log.contains('Loading')) {
                  textColor = Colors.blue.shade400;
                } else if (log.contains('Warning') || log.contains('failed')) {
                  textColor = Colors.orange.shade400;
                }

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      log,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: textColor,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
