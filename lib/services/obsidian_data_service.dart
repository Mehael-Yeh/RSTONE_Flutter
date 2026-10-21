/// Official signed generations and an independent user overlay feed the existing UI.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import '../data_sync/data_sync_service.dart';
import '../data_sync/protocol/rstone_protocol.dart';
import '../data_sync/protocol/src/casefold.dart';
import '../data_sync/services/index_manager.dart';
import '../data_sync/services/source_manager.dart';
import '../data_sync/storage/storage_adapter.dart';
import '../data_sync/storage/storage_factory.dart';
import '../data_sync/storage/legacy_migration.dart';
import '../models/product_item.dart';
import '../utils/natural_sort.dart';

class ObsidianDataService extends ChangeNotifier {
  DataSyncService? sync;
  StorageAdapter? _storage;
  final String appVersion;
  final String? bootstrapRules;
  final bool migrateLegacy;
  ObsidianDataService(
      {DataSyncService? syncService,
      this.appVersion = '2.0.1',
      this.migrateLegacy = true,
      this.bootstrapRules})
      : sync = syncService,
        _storage = syncService?.storage;

  List<ProductItem> _products = [], _applications = [], _formulas = [];
  final Map<String, ProductItem> _userItems = {};
  DataSnapshot _official = const DataSnapshot();
  final Map<String, String> _tdsByProduct = {}, _tdsByNormalizedProduct = {};
  final Map<String, List<String>> _missingReferences = {};
  String _defaultRules = '',
      _builtInTagAliasRulesRaw = '',
      _customTagAliasRulesRaw = '',
      _combinedTagAliasRulesRaw = '';
  Map<String, Set<String>> _tagAliasRules = {};
  bool _initialized = false;
  Future<void>? _initializing;
  final List<String> _logs = [];
  int revision = 0;
  String? initializationError;
  List<ProductItem> get products => List.unmodifiable(_products);
  List<ProductItem> get applications => List.unmodifiable(_applications);
  List<ProductItem> get formulas => List.unmodifiable(_formulas);
  String get builtInTagAliasRulesRaw => _builtInTagAliasRulesRaw;
  String get customTagAliasRulesRaw => _customTagAliasRulesRaw;
  String get tagAliasRulesRaw => _combinedTagAliasRulesRaw;
  Map<String, Set<String>> get tagAliasRules =>
      Map.unmodifiable(_tagAliasRules);
  Map<String, String> get tdsByProduct => Map.unmodifiable(_tdsByProduct);
  bool get isInitialized => _initialized;
  List<String> get logs => List.unmodifiable(_logs);
  List<String> unresolvedReferencesFor(ProductItem item) =>
      _missingReferences[item.filePath] ?? const [];
  StorageAdapter get _store => _storage ?? (throw StateError('本地存储不可用'));

  @visibleForTesting
  void setItemsForTesting(
      {List<ProductItem> products = const [],
      List<ProductItem> applications = const [],
      List<ProductItem> formulas = const []}) {
    _products = [...products];
    _applications = [...applications];
    _formulas = [...formulas];
  }

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      _defaultRules = bootstrapRules ??
          await rootBundle.loadString('assets/tag_alias_rules.default.txt');
      _rebuildRules();
      if (sync == null) {
        final config = jsonDecode(
                await rootBundle.loadString('assets/data_sync_config.json'))
            as Map<String, dynamic>;
        _storage = await openStorage();
        sync = DataSyncService(
            storage: _store,
            appVersion: appVersion,
            sources: SourceManager(
                sources: (config['sources'] as List)
                    .map((v) =>
                        DataSource(v['name'] as String, v['url'] as String))
                    .toList(),
                trustedKeys: Map<String, String>.from(config['keys'] as Map)));
      }
      if (migrateLegacy) await migrateLegacyData(_store);
      _customTagAliasRulesRaw = await _store
              .readText('user/custom_rules/tag_alias_rules.custom.txt') ??
          '';
      await _loadUserItems();
      await sync!.initialize();
      _official = sync!.snapshot;
      _composeSnapshot();
      sync!.addListener(_onSyncChanged);
      _addLog('本地资料已加载；官方版本：${sync!.databaseVersion}');
    } catch (e) {
      initializationError = '本地官方资料暂不可用，个人资料已保留。请检查存储或恢复有效备份。';
      _addLog('$initializationError $e');
      // Official-state failure must not hide an already preserved user layer.
      _composeSnapshot();
    }
    _initialized = true;
  }

  void _onSyncChanged() {
    if (!identical(_official, sync!.snapshot)) {
      _official = sync!.snapshot;
      _composeSnapshot();
      _addLog(sync!.lastLog ?? '资料版本已切换');
    }
    if (sync!.failureDetails != null &&
        !_logs.any((line) => line.endsWith(sync!.failureDetails!))) {
      _addLog(sync!.failureDetails!);
    }
    notifyListeners();
  }

  void _composeSnapshot() {
    List<ProductItem> merge(List<ProductItem> official, String folder) {
      final byPath = {
        for (final item in official) protocolCaseFold(item.filePath): item
      };
      for (final entry in _userItems.entries) {
        if (entry.key.startsWith('$folder/')) {
          byPath[protocolCaseFold(entry.key)] = entry.value;
        }
      }
      return byPath.values.toList()
        ..sort((a, b) => compareNaturalText(a.filePath, b.filePath));
    }

    _products = merge(_official.products, '产品列表');
    _applications = merge(_official.applications, '产品应用');
    _formulas = merge(_official.formulas, '产品配方');
    _tdsByProduct.clear();
    _tdsByNormalizedProduct.clear();
    _tdsByProduct.addAll(_official.tds);
    final candidates = <String, List<String>>{};
    for (final entry in _official.tds.entries) {
      final key = _normalizeProductKey(entry.key.split('/').last);
      candidates.putIfAbsent(key, () => []).add(entry.value);
    }
    for (final entry in candidates.entries) {
      if (entry.value.length == 1) {
        _tdsByNormalizedProduct[entry.key] = entry.value.single;
      }
    }
    _missingReferences.clear();
    final known = {
      ..._products.map((p) => p.fileName.toLowerCase()),
      ..._formulas.map((p) => p.fileName.toLowerCase())
    };
    for (final app in _applications) {
      final missing = app.linkedWikiReferences
          .where((r) =>
              RegExp(r'^R[DS]', caseSensitive: false).hasMatch(r) &&
              !known.contains(r.toLowerCase()))
          .toList();
      if (missing.isNotEmpty) _missingReferences[app.filePath] = missing;
    }
    _applications = _applications
        .map((app) => ProductItem.fromMdContent(app.filePath, app.rawContent,
            origin: app.origin,
            unresolvedProductReferences:
                _missingReferences[app.filePath] ?? const []))
        .toList();
    _rebuildRules();
    revision++;
  }

  void _rebuildRules() {
    _builtInTagAliasRulesRaw = _official.rules ?? _defaultRules;
    _tagAliasRules = _parseTagAliasRules(_builtInTagAliasRulesRaw);
    _mergeTagAliasRules(_parseTagAliasRules(_customTagAliasRulesRaw));
    _combinedTagAliasRulesRaw = _composeCombinedTagAliasRulesText();
  }

  Future<void> saveTagAliasRules(String rawContent) async {
    await _store.writeText(
        'user/custom_rules/tag_alias_rules.custom.txt', rawContent);
    _customTagAliasRulesRaw = rawContent;
    _rebuildRules();
    revision++;
    notifyListeners();
  }

  String? tdsForProduct(String productName) {
    if (_tdsByProduct.containsKey(productName)) {
      return _tdsByProduct[productName];
    }
    for (final key in _tdsLookupCandidates(productName)) {
      if (_tdsByNormalizedProduct.containsKey(key)) {
        return _tdsByNormalizedProduct[key];
      }
    }
    return null;
  }

  Iterable<String> _tdsLookupCandidates(String name) sync* {
    final normalized = _normalizeProductKey(name);
    if (normalized.isNotEmpty) yield normalized;
    final base = _normalizeProductKey(name.split('-').first.trim());
    if (base.isNotEmpty && base != normalized) yield base;
    if (normalized.startsWith('RS')) yield 'RD${normalized.substring(2)}';
    if (normalized.startsWith('RD')) yield 'RS${normalized.substring(2)}';
  }

  String _normalizeProductKey(String raw) => raw
      .toUpperCase()
      .replaceAll('.TDS.MD', '')
      .replaceAll('.MD', '')
      .replaceAll(RegExp(r'[^A-Z0-9]'), '');
  void _addLog(String message) {
    _logs.insert(0, '[${DateTime.now().toIso8601String()}] $message');
    if (_logs.length > 100) _logs.removeLast();
  }

  void _mergeTagAliasRules(Map<String, Set<String>> additionalRules) {
    for (final entry in additionalRules.entries) {
      _tagAliasRules
          .putIfAbsent(entry.key, () => <String>{})
          .addAll(entry.value);
    }
  }

  String _composeCombinedTagAliasRulesText() {
    final builtIn = _builtInTagAliasRulesRaw.trim();
    final custom = _customTagAliasRulesRaw.trim();
    if (builtIn.isEmpty) return custom;
    if (custom.isEmpty) return builtIn;
    return '$builtIn\n\n# ===== 以下为用户新增规则 =====\n$custom';
  }

  /// 解析规则文档：支持 `A->B` 与 `A→B`，并支持左侧多 key（逗号分隔）。
  Map<String, Set<String>> _parseTagAliasRules(String rawContent) {
    final map = <String, Set<String>>{};
    final lines = rawContent.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final parts = trimmed.split(RegExp(r'\s*(?:->|→)\s*'));
      if (parts.length != 2) continue;
      final keysPart = parts[0].trim();
      final value = parts[1].trim().toLowerCase();
      if (keysPart.isEmpty || value.isEmpty) continue;

      final keys = keysPart
          .split(RegExp(r'[、,，]'))
          .map((k) => k.trim().toLowerCase())
          .where((k) => k.isNotEmpty);
      for (final key in keys) {
        map.putIfAbsent(key, () => <String>{}).add(value);
      }
    }
    return map;
  }

  /// 扩展关键词，包含自身以及同义词规则中的一层正向/反向映射。
  ///
  /// 这里刻意不做递归扩展：例如 `UV -> 双固化 -> PU` 的传递会导致
  /// 搜索 UV 时误命中仅带 PU 标签的产品，反之亦然。
  Set<String> _expandedKeywords(String keyword) {
    final normalized = keyword.toLowerCase().trim();
    if (normalized.isEmpty) return <String>{};

    // “双固化”本身应作为独立固化方式标签检索；它可以被 PU/UV 反向命中，
    // 但搜索“双固化”不应放宽为所有 PU 或 UV 产品。
    if (normalized == '双固化') return <String>{normalized};

    final expanded = <String>{normalized};
    expanded.addAll(_tagAliasRules[normalized] ?? const <String>{});

    for (final entry in _tagAliasRules.entries) {
      if (entry.value.contains(normalized)) {
        expanded.add(entry.key);
      }
    }

    return expanded;
  }

  String _joinTagsToYamlList(List<String> tags) {
    final normalized =
        tags.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (normalized.isEmpty) return 'tags: []';
    final lines = normalized.map((tag) => '  - $tag').join('\n');
    return 'tags:\n$lines';
  }

  String buildProductMarkdownTemplate({
    required List<String> tags,
    String engineer = '',
    String experimentalCode = '',
    String solidContent = '',
    String hydroxylValue = '',
    String functionality = '',
    String hardness = '',
    String gloss60 = '',
    String boilResistance = '',
    String waterContactAngle = '',
    String technologySource = '',
    String benchmark = '',
    String viscosity = '',
  }) {
    return '''
---
${_joinTagsToYamlList(tags)}
工程师: $engineer
实验牌号: $experimentalCode
固含: $solidContent
羟值: $hydroxylValue
官能度: $functionality
硬度: $hardness
光泽(60°): $gloss60
水煮: $boilResistance
水接触角: $waterContactAngle
技术源: $technologySource
对标: $benchmark
粘度: $viscosity
---
'''
        .trim();
  }

  String buildApplicationMarkdownTemplate({
    required List<String> tags,
    String primer = '',
    String midCoat = '',
    String topCoat = '',
  }) {
    return '''
---
${_joinTagsToYamlList(tags)}
底漆: $primer
中漆: $midCoat
面漆: $topCoat
---
'''
        .trim();
  }

  String buildFormulaMarkdownTemplate({required String tableMarkdown}) {
    return tableMarkdown.trim().isEmpty
        ? '| 项目 | 数值 |\n| --- | --- |\n| 示例 | 0 |'
        : tableMarkdown.trim();
  }

  /// 搜索产品和应用
  ///
  /// 搜索规则：
  /// 1) 单关键词：搜索范围包括文件名（产品牌号/应用名称）、实验牌号、标签、引用。
  /// 2) 混合关键词（空格分词或自动分段后>=2个关键词）：仅在标签内进行 AND 匹配。
  ///
  /// 空格仅作为分词符；标签匹配按 Obsidian“标签不含空格”的约定处理：
  /// - 关键词本身是完整标签（含一层同义词）时，只做整词命中，
  ///   因此“聚碳”不命中“聚碳酸酯”（PC），“耐水”不命中“耐水煮”；
  /// - 否则按子串匹配，输入途中的片段（如“聚”“P”）也能命中更长的标签。
  ///
  /// [query] 搜索关键词，支持空格分隔多个关键词
  /// 返回匹配的产品和应用列表
  List<ProductItem> search(String query) {
    if (query.isEmpty) return [];
    final normalizedQuery = query.toLowerCase().trim();

    Set<String> buildSearchableTags(ProductItem item) {
      final searchable = <String>{};
      for (final rawTag in item.tags) {
        final normalizedTag = rawTag.toLowerCase();
        if (normalizedTag.isEmpty) continue;
        searchable.add(normalizedTag);
        searchable.addAll(_tagAliasRules[normalizedTag] ?? {});
      }
      return searchable;
    }

    bool shouldExcludePudResults(List<String> segmentedKeywords) {
      final rawLowerQuery = query.toLowerCase();
      final compact = normalizedQuery.replaceAll(RegExp(r'\s+'), '');
      if (compact.contains('pud')) return false;

      // 仅在“PU 后续已明确不是 D”时排除 PUD：
      // 1) PU 后还有其他字符（如“pu油性”“pu面漆”）；
      // 2) 输入以“pu + 空白”结束（如“底漆 pu ”）。
      final puRegex = RegExp(r'pu');
      for (final match in puRegex.allMatches(rawLowerQuery)) {
        final nextIndex = match.end;
        if (nextIndex < rawLowerQuery.length) {
          final nextChar = rawLowerQuery[nextIndex];
          if (nextChar != 'd') {
            return true;
          }
          continue;
        }
        if (RegExp(r'pu\s+$').hasMatch(rawLowerQuery)) {
          return true;
        }
      }

      // 兼容历史“PU 同义词”分段（羟丙 / 羟基丙烯酸）的兜底逻辑。
      // 纯中文检索也需要生效，以避免“羟丙 / 羟基丙烯酸”误命中 PUD。
      const puLockedTerms = <String>{'羟丙', '羟基丙烯酸'};
      return segmentedKeywords.any(puLockedTerms.contains);
    }

    bool containsAnyTerm(Set<String> searchableTags, Set<String> terms) {
      return searchableTags.any((tag) => terms.contains(tag));
    }

    Set<String> buildKnownTagTerms() {
      final knownTerms = <String>{};

      void addFromItem(ProductItem item) {
        knownTerms.addAll(buildSearchableTags(item));
      }

      for (final product in _products) {
        addFromItem(product);
      }
      for (final app in _applications) {
        addFromItem(app);
      }

      for (final entry in _tagAliasRules.entries) {
        knownTerms.add(entry.key);
        knownTerms.addAll(entry.value);
      }

      return knownTerms.where((term) => term.isNotEmpty).toSet();
    }

    List<String> segmentByKnownTerms(String input, Set<String> knownTerms) {
      final source = input.toLowerCase().trim();
      if (source.isEmpty) return const <String>[];

      final matchesAt =
          List<List<String>>.generate(source.length + 1, (_) => <String>[]);
      for (final term in knownTerms) {
        if (term.isEmpty || term == source || term.length > source.length) {
          continue;
        }
        var start = source.indexOf(term);
        while (start != -1) {
          matchesAt[start].add(term);
          start = source.indexOf(term, start + 1);
        }
      }

      final best = List<List<String>?>.filled(source.length + 1, null);
      best[0] = <String>[];
      for (var i = 0; i < source.length; i++) {
        final prefix = best[i];
        if (prefix == null) continue;
        for (final term in matchesAt[i]) {
          final next = i + term.length;
          final candidate = [...prefix, term];
          final existing = best[next];
          if (existing == null || candidate.length > existing.length) {
            best[next] = candidate;
          }
        }
      }

      final segmented = best[source.length];
      if (segmented != null && segmented.length > 1) {
        return segmented;
      }
      return <String>[source];
    }

    final keywords = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((k) => k.isNotEmpty)
        .toList();

    if (keywords.length <= 1) {
      final knownTerms = buildKnownTagTerms();
      final segmentedByKnownTerms =
          segmentByKnownTerms(normalizedQuery, knownTerms);
      if (segmentedByKnownTerms.length > 1) {
        keywords
          ..clear()
          ..addAll(segmentedByKnownTerms);
      }
    }

    if (keywords.length <= 1) {
      // 未使用空格时，额外按“中文片段 + 英文数字片段”拆分，
      // 例如：水性PU / PU水性 → [水性, pu]
      final segmented = RegExp(r'[\u4e00-\u9fff]+|[a-z0-9-]+')
          .allMatches(normalizedQuery)
          .map((m) => m.group(0) ?? '')
          .where((k) => k.isNotEmpty)
          .toList();
      if (segmented.length > 1) {
        keywords
          ..clear()
          ..addAll(segmented);
      }
    }

    if (keywords.length == 1) {
      final knownTerms = buildKnownTagTerms();
      final segmented = segmentByKnownTerms(keywords.first, knownTerms);
      if (segmented.length > 1) {
        keywords
          ..clear()
          ..addAll(segmented);
      }
    }

    if (keywords.isEmpty) return [];

    // 已知完整标签（含同义词）集合：关键词命中它时按整词匹配标签，
    // 否则视为输入途中或普通文本，保持子串匹配。
    final knownTagTerms = buildKnownTagTerms();
    final excludePudResults = shouldExcludePudResults(keywords);
    final pudTerms = _expandedKeywords('pud');
    final results = <ProductItem>[];

    _addLog('DataService: Searching for keywords: $keywords');

    bool isDigitsOnly(String keyword) => RegExp(r'^\d+$').hasMatch(keyword);

    bool startsWithNumericBody(String? code, String numericKeyword) {
      if (code == null || code.isEmpty) return false;
      final normalizedCode = code.toLowerCase().trim();
      final normalizedKeyword = numericKeyword.toLowerCase().trim();
      if (normalizedKeyword.isEmpty) return false;

      final firstDigitIndex = normalizedCode.indexOf(RegExp(r'\d'));
      if (firstDigitIndex == -1) return false;
      final numericBody = normalizedCode.substring(firstDigitIndex);
      return numericBody.startsWith(normalizedKeyword);
    }

    /// 判断 [keyword] 是否整词命中条目的某个标签。
    ///
    /// [searchableTags] 已包含条目标签的一层正向同义词扩展；
    /// 额外检查条目原始标签是否落在 [expanded]（关键词的一层正/反向扩展）内，
    /// 以覆盖条目直接使用同义词作标签的场景（如标注“聚氨酯”，搜“PU”）。
    bool matchesExactTag(
      ProductItem item,
      Set<String> searchableTags,
      String keyword,
      Set<String> expanded,
    ) {
      if (searchableTags.contains(keyword)) return true;
      return item.tags.any((rawTag) => expanded.contains(rawTag.toLowerCase()));
    }

    bool containsKeyword(ProductItem item, String keyword) {
      final searchableTags = buildSearchableTags(item);
      if (excludePudResults && containsAnyTerm(searchableTags, pudTerms)) {
        return false;
      }
      final linkedRefText = item.linkedWikiReferences.join(' ');
      final searchableTagsText = searchableTags.join(' ');
      final singleKeywordSearchText =
          '${item.fileName} ${item.experimentalCode ?? ''} $searchableTagsText $linkedRefText'
              .toLowerCase();
      final expanded = _expandedKeywords(keyword);
      if (isDigitsOnly(keyword)) {
        final numericKeyword = keyword.toLowerCase();
        return startsWithNumericBody(item.fileName, numericKeyword) ||
            startsWithNumericBody(item.experimentalCode, numericKeyword) ||
            item.linkedWikiReferences
                .any((ref) => startsWithNumericBody(ref, numericKeyword));
      }
      if (knownTagTerms.contains(keyword)) {
        // 关键词本身是完整标签（Obsidian 标签不含空格，词边界即标签边界）：
        // 标签只做整词命中，因此“聚碳”不命中“聚碳酸酯”（PC）、
        // “耐水”不命中“耐水煮”；文件名、实验牌号和引用仍保持子串匹配。
        final nonTagSearchText =
            '${item.fileName} ${item.experimentalCode ?? ''} $linkedRefText'
                .toLowerCase();
        return matchesExactTag(item, searchableTags, keyword, expanded) ||
            expanded.any(nonTagSearchText.contains);
      }
      // 非完整标签（输入途中或普通文本）：保持子串匹配，
      // 例如“聚”可命中“聚碳酸酯”（PC），“P”可命中“PC”。
      return expanded.any(singleKeywordSearchText.contains);
    }

    bool matchesMixedKeywordsInTagsOnly(ProductItem item) {
      final searchableTags = buildSearchableTags(item);
      if (excludePudResults && containsAnyTerm(searchableTags, pudTerms)) {
        return false;
      }
      final tagsText = searchableTags.join(' ').toLowerCase();
      return keywords.every((keyword) {
        final expanded = _expandedKeywords(keyword);
        // 完整标签整词命中（“聚碳”不带出“聚碳酸酯”）；
        // 非完整标签的片段保持子串匹配（“水性 聚”可命中带 PC 标签的产品）。
        if (knownTagTerms.contains(keyword)) {
          return matchesExactTag(item, searchableTags, keyword, expanded);
        }
        return expanded.any(tagsText.contains);
      });
    }

    for (var product in _products) {
      final matched = keywords.length == 1
          ? containsKeyword(product, keywords.first)
          : matchesMixedKeywordsInTagsOnly(product);
      if (matched) {
        results.add(product);
      }
    }

    for (var app in _applications) {
      final matched = keywords.length == 1
          ? containsKeyword(app, keywords.first)
          : matchesMixedKeywordsInTagsOnly(app);
      if (matched) {
        results.add(app);
      }
    }

    _addLog('DataService: Search found ${results.length} results');
    return results;
  }

  Future<void> _saveUserItem(
      String folder, String name, String markdown) async {
    final path = '$folder/$name.md';
    validateLogicalPath(path);
    final parsed = ProductItem.fromMdContent('user/$path', markdown,
        origin: DataOrigin.user);
    await _store.writeText('user/$path', markdown);
    _userItems[path] = parsed;
    _composeSnapshot();
    notifyListeners();
  }

  Future<void> addProductMarkdown(
      {required String code, required String markdown}) async {
    final name = code.trim().toUpperCase();
    if (!name.startsWith('RD') && !name.startsWith('RS')) {
      throw ArgumentError('文件名需以 RD 或 RS 开头');
    }
    await _saveUserItem('产品列表', name, markdown);
  }

  Future<void> addApplicationMarkdown(
      {required String name, required String markdown}) async {
    if (name.trim().isEmpty) throw ArgumentError('产品应用名称不能为空');
    await _saveUserItem('产品应用', name.trim(), markdown);
  }

  Future<void> addFormulaMarkdown(
      {required String name, required String markdown}) async {
    if (name.trim().isEmpty) throw ArgumentError('产品配方名称不能为空');
    await _saveUserItem('产品配方', name.trim(), markdown);
  }

  bool isManualItem(ProductItem item) => item.origin == DataOrigin.user;
  Future<void> deleteManualItem(ProductItem item) async {
    if (!isManualItem(item)) throw StateError('仅支持删除用户新增资料');
    final path = item.filePath.substring('user/'.length);
    await _store.remove('user/$path');
    _userItems.remove(path);
    // Only the CURRENT official mapping can reappear underneath an overlay.
    _composeSnapshot();
    notifyListeners();
  }

  Future<int> clearAllManualMarkdownData() async {
    final paths = _userItems.keys.toList();
    for (final path in paths) {
      await _store.remove('user/$path');
      _userItems.remove(path);
    }
    _composeSnapshot();
    notifyListeners();
    return paths.length;
  }

  Future<void> _loadUserItems() async {
    _userItems.clear();
    for (final key in await _store.keys('user/')) {
      if (!key.endsWith('.md')) continue;
      final path = key.substring('user/'.length);
      validateLogicalPath(path);
      final content = await _store.readText(key);
      if (content != null) {
        _userItems[path] =
            ProductItem.fromMdContent(key, content, origin: DataOrigin.user);
      }
    }
  }

  Future<Uint8List?> exportMarkdownArchive() async {
    final archive = Archive();
    for (final entry in _userItems.entries) {
      final bytes = utf8.encode(entry.value.rawContent);
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    if (archive.isEmpty) return null;
    final bytes = ZipEncoder().encode(archive);
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  /// Clearing user Markdown does not clear the official replay watermark.
  Future<void> clearData() async => clearAllManualMarkdownData();
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    sync?.removeListener(_onSyncChanged);
    super.dispose();
  }
}
