/// 关于页详情，展示版本信息、更新检查与项目链接。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 关于页详情内容，负责展示版本信息、更新检查和外部链接。
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
