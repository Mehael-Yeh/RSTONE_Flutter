import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/obsidian_data_service.dart';
import '../services/preferences_service.dart';

/// 设置页面（MD3）
class SettingsPage extends StatefulWidget {
  final ObsidianDataService dataService;
  final PreferencesService preferencesService;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeModeChanged;

  const SettingsPage({
    super.key,
    required this.dataService,
    required this.preferencesService,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _appVersion = '...';
  late ThemeMode _selectedThemeMode;

  @override
  void initState() {
    super.initState();
    _selectedThemeMode = widget.themeMode;
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
                _buildInfoTile(
                  icon: Icons.check_circle,
                  title: '初始化状态',
                  value: widget.dataService.isInitialized ? '已完成' : '未完成',
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
            title: '数据管理',
            child: ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('重新加载数据'),
              subtitle: const Text('从内置资源重新加载产品数据'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _reloadData,
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

  Future<void> _reloadData() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('正在重新加载...'),
          ],
        ),
      ),
    );

    await widget.dataService.clearData();
    await widget.dataService.initialize();

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('重新加载完成！产品: ${widget.dataService.products.length}, 应用: ${widget.dataService.applications.length}'),
        ),
      );
      setState(() {});
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
