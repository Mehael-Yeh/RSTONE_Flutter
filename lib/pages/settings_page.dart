/// 设置中心页面：主题、数据同步、备份恢复与入口导航。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import '../utils/compat_color.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/obsidian_data_service.dart';
import '../services/preferences_service.dart';
import 'about_detail_page.dart';
import 'log_viewer_page.dart';

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
  static const bool _isLiteBuild = bool.fromEnvironment('RSTONE_LITE');
  static final Uri _projectUrl =
      Uri.parse('https://github.com/Mehael-Yeh/RSTONE_Flutter');
  static final Uri _webAppUrl =
      Uri.parse('https://mehael-yeh.github.io/RSTONE_Flutter/');
  static final Uri _releaseUrl =
      Uri.parse('https://github.com/Mehael-Yeh/RSTONE_Flutter/releases');
  String _appVersion = '...';
  String _appVersionName = '0.0.0';
  String _databaseVersion = '未注入';
  late ThemeMode _selectedThemeMode;
  late Color _selectedThemeSeedColor;
  static const List<Color> _presetThemeColors = <Color>[
    Color(0xFFFF8A00),
    Color(0xFFFFB300),
    Color(0xFFE53935),
    Color(0xFFD81B60),
    Color(0xFF8E24AA),
    Color(0xFF5E35B1),
    Color(0xFF3949AB),
    Color(0xFF1E88E5),
    Color(0xFF039BE5),
    Color(0xFF00ACC1),
    Color(0xFF00897B),
    Color(0xFF7CB342),
    Color(0xFF43A047),
    Color(0xFFF4511E),
    Color(0xFF6D4C41),
    Color(0xFF546E7A),
  ];

  @override
  void initState() {
    super.initState();
    _selectedThemeMode = widget.themeMode;
    _selectedThemeSeedColor = widget.themeSeedColor;
    _loadVersion();
  }

  String _formatBuildTimeLabel(String raw) {
    final value = raw.trim();

    // CI 注入的标准格式：YYYYMMDDHHMM
    if (RegExp(r'^\d{12}$').hasMatch(value)) {
      return '${value.substring(0, 8)} ${value.substring(8, 10)}:${value.substring(10, 12)}';
    }

    // 兼容纯日期：YYYYMMDD
    if (RegExp(r'^\d{8}$').hasMatch(value)) {
      return value;
    }

    // 兼容 CI 构建号（epoch minutes）。
    final asInt = int.tryParse(value);
    if (asInt != null && asInt > 0) {
      try {
        final maybeEpochMinutes =
            DateTime.fromMillisecondsSinceEpoch(asInt * 60 * 1000, isUtc: true)
                .add(const Duration(hours: 8));
        if (maybeEpochMinutes.year >= 2020 && maybeEpochMinutes.year <= 2100) {
          final y = maybeEpochMinutes.year.toString().padLeft(4, '0');
          final m = maybeEpochMinutes.month.toString().padLeft(2, '0');
          final d = maybeEpochMinutes.day.toString().padLeft(2, '0');
          final hh = maybeEpochMinutes.hour.toString().padLeft(2, '0');
          final mm = maybeEpochMinutes.minute.toString().padLeft(2, '0');
          return '$y$m$d $hh:$mm';
        }
      } catch (_) {
        // Ignore and continue to legacy parsing.
      }
    }
    return value;
  }

  Future<void> _loadVersion() async {
    final pkg = await PackageInfo.fromPlatform();
    const databaseVersionFromDefine =
        String.fromEnvironment('DB_VERSION', defaultValue: '');
    const buildTimeFromDefine =
        String.fromEnvironment('APP_BUILD_TIME', defaultValue: '');
    final buildTime = buildTimeFromDefine.trim().isNotEmpty
        ? _formatBuildTimeLabel(buildTimeFromDefine)
        : pkg.buildNumber.trim();
    final normalizedBuildTime = buildTime
        .replaceAll('UTC+08', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final versionLabel = _isLiteBuild ? '${pkg.version}-Lite' : pkg.version;
    final displayVersion = normalizedBuildTime.isNotEmpty
        ? 'v$versionLabel ($normalizedBuildTime)'
        : 'v$versionLabel';
    if (mounted) {
      setState(() {
        _appVersion = displayVersion;
        _appVersionName = pkg.version;
        _databaseVersion = databaseVersionFromDefine.trim().isEmpty
            ? '未注入'
            : databaseVersionFromDefine.trim();
      });
    }
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
    Color workingColor = _selectedThemeSeedColor;
    final initialHex = workingColor.compatArgb32
        .toRadixString(16)
        .toUpperCase()
        .padLeft(8, '0');
    final controller =
        TextEditingController(text: '#${initialHex.substring(2)}');
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义主题色'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            Widget buildChannelSlider({
              required String label,
              required int value,
              required ValueChanged<int> onChanged,
            }) {
              return Row(
                children: [
                  SizedBox(width: 24, child: Text(label)),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 255,
                      divisions: 255,
                      value: value.toDouble(),
                      onChanged: (v) => onChanged(v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(
                      value.toString(),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              );
            }

            void syncHexFromColor() {
              final hex = workingColor.compatArgb32
                  .toRadixString(16)
                  .toUpperCase()
                  .padLeft(8, '0');
              controller.text = '#${hex.substring(2)}';
            }

            return SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 64,
                      decoration: BoxDecoration(
                        color: workingColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    buildChannelSlider(
                      label: 'R',
                      value: workingColor.compatRed,
                      onChanged: (newValue) {
                        setDialogState(() {
                          workingColor = workingColor.withRed(newValue);
                          syncHexFromColor();
                        });
                      },
                    ),
                    buildChannelSlider(
                      label: 'G',
                      value: workingColor.compatGreen,
                      onChanged: (newValue) {
                        setDialogState(() {
                          workingColor = workingColor.withGreen(newValue);
                          syncHexFromColor();
                        });
                      },
                    ),
                    buildChannelSlider(
                      label: 'B',
                      value: workingColor.compatBlue,
                      onChanged: (newValue) {
                        setDialogState(() {
                          workingColor = workingColor.withBlue(newValue);
                          syncHexFromColor();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'HEX 颜色值',
                        hintText: '#FF8A00',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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
        .where((product) =>
            widget.dataService.tdsForProduct(product.fileName) != null)
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
                        selected: _selectedThemeSeedColor.compatArgb32 ==
                            color.compatArgb32,
                        onTap: () => _onThemeSeedColorChanged(color),
                      ),
                    ),
                    _buildColorSwatch(
                      color: _selectedThemeSeedColor,
                      selected: !_presetThemeColors.any((c) =>
                          c.compatArgb32 ==
                          _selectedThemeSeedColor.compatArgb32),
                      onTap: _pickCustomThemeColor,
                      icon: Icons.palette_outlined,
                      tooltip: '自定义主题色',
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
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('数据库版本'),
                  trailing: Text(
                    _databaseVersion,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2),
                  title: const Text('产品数量'),
                  trailing: Text(
                    '${widget.dataService.products.length}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.apps),
                  title: const Text('应用数量'),
                  trailing: Text(
                    '${widget.dataService.applications.length}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('TDS数量'),
                  trailing: Text(
                    '${widget.dataService.tdsByProduct.length}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.pie_chart),
                  title: const Text('TDS覆盖率'),
                  trailing: Text(
                    '$coveredProducts/$totalProducts ($coveragePercent%)',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
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
                  subtitle: const Text('用于搜索同义词扩展'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openTagAliasRuleEditor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            title: '产品笔记与新增',
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('导出产品笔记'),
                  subtitle: const Text('导出文件用于反馈（长按可复制）'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _exportProductNotes,
                  onLongPress: _copyProductNotesMarkdownToClipboard,
                ),
                ListTile(
                  leading: Icon(Icons.delete_sweep_outlined, color: cs.error),
                  title: const Text('清除所有产品笔记'),
                  subtitle: const Text('清空全部项目反馈记录'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _confirmClearAllProductNotes,
                ),
                const Divider(height: 8),
                ListTile(
                  leading: const Icon(Icons.folder_zip_outlined),
                  title: const Text('导出产品 Markdown 数据包'),
                  subtitle: const Text('仅导出通过“新增”按钮创建的产品列表/应用/配方'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _exportMarkdownArchive,
                ),
                ListTile(
                  leading: Icon(Icons.delete_forever_outlined, color: cs.error),
                  title: const Text('删除所有新增 Markdown 数据'),
                  subtitle: const Text('清空通过“新增”按钮写入的产品列表/应用/配方'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _confirmClearAllManualMarkdownData,
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
                        builder: (context) =>
                            LogViewerPage(dataService: widget.dataService),
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
            title: '关于',
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于锐石 RSTONE'),
                  subtitle: Text('版本 $_appVersion'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AboutDetailPage(
                          appVersion: _appVersion,
                          appVersionName: _appVersionName,
                          projectUrl: _projectUrl,
                          webAppUrl: _webAppUrl,
                          releaseUrl: _releaseUrl,
                        ),
                      ),
                    );
                  },
                ),
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
    IconData? icon,
    String? tooltip,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip ?? '主题色',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
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
              : icon != null
                  ? Icon(icon,
                      size: 16, color: Colors.white.withCompatOpacity(0.95))
                  : null,
        ),
      ),
    );
  }

  Future<void> _openTagAliasRuleEditor() async {
    final builtInRules = widget.dataService.builtInTagAliasRulesRaw;
    final controller =
        TextEditingController(text: widget.dataService.customTagAliasRulesRaw);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('标签同义词规则'),
        content: SizedBox(
          width: 680,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.72),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '内置规则已写入应用，不再接受软件外部文件修改。\n你可以在这里新增规则（会持久化保存）。\n每行一条规则：左侧是可匹配标签（可用“、”分隔多个），右侧是扩展词。\n格式示例：PA、PA6、PA66 -> 尼龙',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('查看内置规则（只读）'),
                  children: [
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 180),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color:
                                Theme.of(context).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          builtInRules.trim().isEmpty
                              ? '（暂无内置规则）'
                              : builtInRules,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: controller,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '新增自定义规则',
                      hintText: '# 支持注释行\nPA、PA6、PA66 -> 尼龙',
                    ),
                  ),
                ),
              ],
            ),
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
      const SnackBar(content: Text('新增标签规则已保存，搜索将立即生效')),
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

  Future<void> _confirmClearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('确定要清除所有日志吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清除')),
        ],
      ),
    );

    if (confirmed == true) {
      widget.dataService.clearLogs();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('日志已清除')));
      }
    }
  }

  Future<void> _exportProductNotes() async {
    final markdownContent = _buildProductNotesMarkdown();
    if (markdownContent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可导出的笔记')),
      );
      return;
    }

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/产品笔记.md');
    await file.writeAsString(markdownContent);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/markdown', name: '产品笔记.md')],
      subject: '产品笔记',
    );
  }

  Future<void> _copyProductNotesMarkdownToClipboard() async {
    final markdownContent = _buildProductNotesMarkdown();
    if (markdownContent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可复制的笔记')),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: markdownContent));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Markdown 内容已复制到剪贴板')),
    );
  }

  Future<void> _exportMarkdownArchive() async {
    final archive = await widget.dataService.exportMarkdownArchive();
    if (archive == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可导出的 Markdown 文件')),
      );
      return;
    }

    await Share.shareXFiles(
      [XFile(archive.path)],
      subject: 'RSTONE Markdown 数据包',
      text: '产品列表/产品应用/产品配方 Markdown 导出包',
    );
  }

  Future<void> _confirmClearAllManualMarkdownData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除新增 Markdown'),
        content: const Text('将删除所有通过“新增产品信息/新增产品配方/新增产品应用”创建的数据，是否继续？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final reconfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('二次确认'),
        content: const Text('请再次确认：删除后不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认删除')),
        ],
      ),
    );
    if (reconfirmed != true) return;

    try {
      final count = await widget.dataService.clearAllManualMarkdownData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(count == 0
                ? '暂无新增 Markdown 数据'
                : '已删除 $count 条新增 Markdown 数据')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  String? _buildProductNotesMarkdown() {
    final notes = widget.preferencesService.getAllProductNotes();
    if (notes.isEmpty) return null;

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
    return markdownContent.isEmpty ? null : markdownContent;
  }

  Future<void> _confirmClearAllProductNotes() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清除笔记'),
        content: const Text('该操作将删除所有产品笔记，是否继续？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final reconfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('二次确认'),
        content: const Text('请再次确认：清除后不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认清除')),
        ],
      ),
    );
    if (reconfirmed != true) return;

    await widget.preferencesService.clearAllProductNotes();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清除所有产品笔记')));
    }
  }
}
