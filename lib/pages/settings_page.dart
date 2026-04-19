import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
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
  static final Uri _projectUrl = Uri.parse('https://github.com/Mehael-Yeh/RSTONE_Flutter');
  static final Uri _webAppUrl = Uri.parse('https://mehael-yeh.github.io/RSTONE_Flutter/');
  static final Uri _releaseUrl = Uri.parse('https://github.com/Mehael-Yeh/RSTONE_Flutter/releases');
  String _appVersion = '...';
  String _appVersionName = '0.0.0';
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
        final maybeEpochMinutes = DateTime.fromMillisecondsSinceEpoch(asInt * 60 * 1000, isUtc: true).add(const Duration(hours: 8));
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
    const buildTimeFromDefine = String.fromEnvironment('APP_BUILD_TIME', defaultValue: '');
    final buildTime = buildTimeFromDefine.trim().isNotEmpty
        ? _formatBuildTimeLabel(buildTimeFromDefine)
        : pkg.buildNumber.trim();
    final normalizedBuildTime = buildTime
        .replaceAll('UTC+08', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final displayVersion = normalizedBuildTime.isNotEmpty
        ? 'v${pkg.version} ($normalizedBuildTime)'
        : 'v${pkg.version}';
    if (mounted) {
      setState(() {
        _appVersion = displayVersion;
        _appVersionName = pkg.version;
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
    final initialHex = workingColor.value.toRadixString(16).toUpperCase().padLeft(8, '0');
    final controller = TextEditingController(text: '#${initialHex.substring(2)}');
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
              final hex = workingColor.value.toRadixString(16).toUpperCase().padLeft(8, '0');
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
                      value: workingColor.red,
                      onChanged: (newValue) {
                        setDialogState(() {
                          workingColor = workingColor.withRed(newValue);
                          syncHexFromColor();
                        });
                      },
                    ),
                    buildChannelSlider(
                      label: 'G',
                      value: workingColor.green,
                      onChanged: (newValue) {
                        setDialogState(() {
                          workingColor = workingColor.withGreen(newValue);
                          syncHexFromColor();
                        });
                      },
                    ),
                    buildChannelSlider(
                      label: 'B',
                      value: workingColor.blue,
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
                ListTile(
                  leading: const Icon(Icons.inventory_2),
                  title: const Text('产品数量'),
                  trailing: Text(
                    '${widget.dataService.products.length}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.apps),
                  title: const Text('应用数量'),
                  trailing: Text(
                    '${widget.dataService.applications.length}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('TDS数量'),
                  trailing: Text(
                    '${widget.dataService.tdsByProduct.length}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.pie_chart),
                  title: const Text('TDS覆盖率'),
                  trailing: Text(
                    '$coveredProducts/$totalProducts ($coveragePercent%)',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
    final builtInRules = widget.dataService.builtInTagAliasRulesRaw;
    final controller = TextEditingController(text: widget.dataService.customTagAliasRulesRaw);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('标签同义词规则'),
        content: SizedBox(
          width: 680,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.72),
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
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          builtInRules.trim().isEmpty ? '（暂无内置规则）' : builtInRules,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
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
      [XFile(file.path)],
      subject: '产品笔记',
      text: '产品笔记导出文件（Markdown）',
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

class AboutDetailPage extends StatelessWidget {
  final String appVersion;
  final String appVersionName;
  final Uri projectUrl;
  final Uri webAppUrl;
  final Uri releaseUrl;

  const AboutDetailPage({
    super.key,
    required this.appVersion,
    required this.appVersionName,
    required this.projectUrl,
    required this.webAppUrl,
    required this.releaseUrl,
  });

  Future<void> _openExternalUrl(BuildContext context, Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开链接：$uri')),
      );
    }
  }

  Future<void> _confirmAndOpenUrl(BuildContext context, String title, Uri uri) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('打开$title'),
        content: Text('即将跳转到外部浏览器：\n$uri\n\n是否继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('继续')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _openExternalUrl(context, uri);
    }
  }

  List<int> _parseVersionParts(String raw) {
    final match = RegExp(r'(\d+(?:\.\d+)+)').firstMatch(raw);
    if (match == null) return [0];
    return match.group(1)!.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  }

  int _compareVersions(String a, String b) {
    final aParts = _parseVersionParts(a);
    final bParts = _parseVersionParts(b);
    final maxLength = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (int i = 0; i < maxLength; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  Future<Map<String, dynamic>?> _fetchLatestStableRelease() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://api.github.com/repos/Mehael-Yeh/RSTONE_Flutter/releases/latest'),
      );
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'RSTONE-Flutter-App');
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final body = await utf8.decoder.bind(resp).join();
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) return data;
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _checkForUpdate(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('正在检查更新...')),
          ],
        ),
      ),
    );
    final releaseData = await _fetchLatestStableRelease();
    if (context.mounted) Navigator.pop(context);
    if (releaseData == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('检查更新失败，请稍后重试')),
        );
      }
      return;
    }

    final latestTag = (releaseData['tag_name'] as String? ?? '').trim();
    final latestUrl = (releaseData['html_url'] as String? ?? '').trim();
    final latestName = (releaseData['name'] as String? ?? '').trim();
    final latestVersion = latestTag.isNotEmpty ? latestTag : latestName;
    final hasNewVersion = _compareVersions(latestVersion, appVersionName) > 0;

    if (!context.mounted) return;
    if (!hasNewVersion) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('检查更新'),
          content: Text('当前已是最新正式版。\n当前版本：v$appVersionName'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('知道了')),
          ],
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发现新版本'),
        content: Text(
          '当前版本：v$appVersionName\n最新正式版：$latestVersion\n\n是否前往下载页面？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final target = latestUrl.isNotEmpty ? Uri.parse(latestUrl) : releaseUrl;
              if (context.mounted) {
                await _openExternalUrl(context, target);
              }
            },
            child: const Text('前往下载'),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Uri uri,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _confirmAndOpenUrl(context, title, uri),
    );
  }

  Widget _buildSectionCard(BuildContext context, {required String title, required Widget child}) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildSectionCard(
            context,
            title: '应用信息',
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.diamond_outlined),
                  title: const Text('应用名称'),
                  trailing: const Text('锐石 / RSTONE'),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('当前版本'),
                  trailing: Text(appVersion),
                ),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('技术栈'),
                  trailing: const Text('Flutter'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            context,
            title: '更新与链接',
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.system_update_alt),
                  title: const Text('检查更新'),
                  subtitle: const Text('查看 GitHub 发布页获取最新版本'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _checkForUpdate(context),
                ),
                _buildLinkTile(
                  context,
                  icon: Icons.code_outlined,
                  title: '项目地址',
                  subtitle: projectUrl.toString(),
                  uri: projectUrl,
                ),
                _buildLinkTile(
                  context,
                  icon: Icons.language,
                  title: '网页版',
                  subtitle: webAppUrl.toString(),
                  uri: webAppUrl,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            context,
            title: '说明',
            child: Column(
              children: const [
                ListTile(
                  leading: Icon(Icons.lightbulb_outline),
                  title: Text('定位'),
                  subtitle: Text('聚焦锐石产品资料检索、应用场景查询与现场记录。'),
                ),
                ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text('使用建议'),
                  subtitle: Text('产品数据会随版本迭代，请在关键业务场景中以最新资料为准。'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
