import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/obsidian_data_service.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  final ObsidianDataService dataService;

  const SettingsPage({super.key, required this.dataService});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _appVersion = '...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final pkg = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = 'v${pkg.version}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text(
          '设置',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          // 数据统计
          _buildSection(
            title: '数据统计',
            children: [
              _buildInfoTile(
                icon: Icons.inventory_2,
                title: '产品数量',
                value: '${dataService.products.length}',
              ),
              _buildInfoTile(
                icon: Icons.apps,
                title: '应用数量',
                value: '${dataService.applications.length}',
              ),
              _buildInfoTile(
                icon: Icons.check_circle,
                title: '初始化状态',
                value: dataService.isInitialized ? '已完成' : '未完成',
              ),
            ],
          ),
          
          // 日志功能
          _buildSection(
            title: '日志',
            children: [
              ListTile(
                leading: const Icon(Icons.list_alt, color: Colors.orange),
                title: const Text(
                  '查看日志',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${dataService.logs.length} 条日志',
                  style: TextStyle(color: Colors.grey[500]),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LogViewerPage(dataService: dataService),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.orange),
                title: const Text(
                  '复制日志',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '复制所有日志到剪贴板',
                  style: TextStyle(color: Colors.grey[500]),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  final logs = dataService.logs.join('\n');
                  Clipboard.setData(ClipboardData(text: logs));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('日志已复制到剪贴板'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  '清除日志',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '清空所有日志记录',
                  style: TextStyle(color: Colors.grey[500]),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF2D2D2D),
                      title: const Text(
                        '确认清除',
                        style: TextStyle(color: Colors.white),
                      ),
                      content: const Text(
                        '确定要清除所有日志吗？',
                        style: TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            dataService.clearLogs();
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('日志已清除'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('清除'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          
          // 数据管理
          _buildSection(
            title: '数据管理',
            children: [
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.orange),
                title: const Text(
                  '重新加载数据',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '从内置资源重新加载产品数据',
                  style: TextStyle(color: Colors.grey[500]),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () async {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const AlertDialog(
                      backgroundColor: Color(0xFF2D2D2D),
                      content: Row(
                        children: [
                          CircularProgressIndicator(color: Colors.orange),
                          SizedBox(width: 20),
                          Text(
                            '正在重新加载...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  );
                  
                  await dataService.clearData();
                  await dataService.initialize();
                  
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('重新加载完成！产品: ${dataService.products.length}, 应用: ${dataService.applications.length}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          
          // 关于
          _buildSection(
            title: '关于',
            children: [
              _buildInfoTile(
                icon: Icons.info_outline,
                title: '版本',
                value: _appVersion,
              ),
              _buildInfoTile(
                icon: Icons.diamond,
                title: '应用名称',
                value: '锐石 / RSTONE',
              ),
              _buildInfoTile(
                icon: Icons.code,
                title: '技术栈',
                value: 'Flutter 3.24',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.orange[300],
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          color: const Color(0xFF2D2D2D),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.orange),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      trailing: Text(
        value,
        style: TextStyle(color: Colors.grey[400]),
      ),
    );
  }
}

/// 日志查看页面
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
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text(
          '日志',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
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
                const SnackBar(
                  content: Text('日志已复制'),
                  backgroundColor: Colors.green,
                ),
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
                  Icon(Icons.article_outlined, size: 64, color: Colors.grey[700]),
                  const SizedBox(height: 16),
                  Text(
                    '暂无日志',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
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
                Color textColor = Colors.white70;
                
                if (log.contains('ERROR')) {
                  textColor = Colors.red[300]!;
                } else if (log.contains('complete') || log.contains('成功')) {
                  textColor = Colors.green[300]!;
                } else if (log.contains('Starting') || log.contains('Loading')) {
                  textColor = Colors.blue[300]!;
                } else if (log.contains('Warning') || log.contains('failed')) {
                  textColor = Colors.orange[300]!;
                }
                
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: textColor,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
