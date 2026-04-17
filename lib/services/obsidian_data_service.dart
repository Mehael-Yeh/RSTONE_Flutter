import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/product_item.dart';

/// Obsidian 数据服务
/// 
/// 负责从 Flutter Asset 加载产品列表、产品应用、产品配方三类数据。
/// 数据来源为内置的 assets 目录下的 JSON 索引文件和 Markdown 文件。
/// 同时提供搜索功能和日志记录。
class ObsidianDataService {
  /// 产品列表 Asset 索引文件路径
  static const String _productsAssetIndex = 'assets/产品列表.json';
  /// 产品应用 Asset 索引文件路径
  static const String _applicationsAssetIndex = 'assets/产品应用.json';
  /// 产品列表 Asset 目录路径
  static const String _productsAssetPath = 'assets/产品列表';
  /// 产品应用 Asset 目录路径
  static const String _applicationsAssetPath = 'assets/产品应用';
  /// TDS Asset 索引文件路径
  static const String _tdsAssetIndex = 'assets/产品TDS.json';
  /// TDS Asset 目录路径（文件名格式：产品名称.TDS.md）
  static const String _tdsAssetPath = 'assets/产品TDS';
  /// 标签同义词规则文档（默认内置）
  static const String _tagAliasRulesAssetPath = 'assets/tag_alias_rules.txt';
  /// 标签同义词规则文档（用户可编辑）
  static const String _tagAliasRulesFileName = 'tag_alias_rules.txt';
  
  /// 产品列表数据
  List<ProductItem> _products = [];
  /// 产品应用数据
  List<ProductItem> _applications = [];
  /// 产品配方数据
  List<ProductItem> _formulas = [];
  /// 标签同义词规则文本（可被设置页展示/编辑）
  String _tagAliasRulesRaw = '';
  /// TDS 文档缓存（key: 产品名称，value: 对应 .TDS.md 文本）
  Map<String, String> _tdsByProduct = {};
  /// 归一化索引（key: 归一化产品名，value: 对应 .TDS.md 文本）
  Map<String, String> _tdsByNormalizedProduct = {};
  /// 标签同义词映射（key -> 可匹配词）
  Map<String, Set<String>> _tagAliasRules = {};
  /// 是否已完成初始化
  bool _initialized = false;
  
  /// 日志记录（最近 100 条）
  final List<String> _logs = [];
  
  List<ProductItem> get products => _products;
  List<ProductItem> get applications => _applications;
  List<ProductItem> get formulas => _formulas;
  String get tagAliasRulesRaw => _tagAliasRulesRaw;
  Map<String, Set<String>> get tagAliasRules => _tagAliasRules;
  Map<String, String> get tdsByProduct => Map.unmodifiable(_tdsByProduct);
  bool get isInitialized => _initialized;
  List<String> get logs => List.unmodifiable(_logs);
  String? tdsForProduct(String productName) {
    final direct = _tdsByProduct[productName];
    if (direct != null) return direct;

    for (final candidate in _tdsLookupCandidates(productName)) {
      final hit = _tdsByNormalizedProduct[candidate];
      if (hit != null) return hit;
    }
    return null;
  }

  Iterable<String> _tdsLookupCandidates(String productName) sync* {
    final normalized = _normalizeProductKey(productName);
    if (normalized.isNotEmpty) yield normalized;

    final baseName = productName.split('-').first.trim();
    final normalizedBase = _normalizeProductKey(baseName);
    if (normalizedBase.isNotEmpty && normalizedBase != normalized) {
      yield normalizedBase;
    }

    if (normalized.startsWith('RS')) {
      yield 'RD${normalized.substring(2)}';
    } else if (normalized.startsWith('RD')) {
      yield 'RS${normalized.substring(2)}';
    }
  }

  String _normalizeProductKey(String raw) {
    return raw
        .toUpperCase()
        .replaceAll('.TDS.MD', '')
        .replaceAll('.MD', '')
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    _logs.insert(0, '[$timestamp] $message');
    // 只保留最近100条日志
    if (_logs.length > 100) {
      _logs.removeLast();
    }
  }

  /// 初始化数据加载
  /// 
  /// 加载顺序：
  /// 1. 直接从 Asset 加载（最可靠的内置数据）
  /// 2. 如果 Asset 为空，从私有目录加载（备用方案）
  /// 3. 如果数据存在，复制 Asset 到私有目录（供后续使用）
  Future<void> initialize() async {
    if (_initialized) {
      _addLog('DataService: Already initialized, skipping');
      return;
    }
    
    _addLog('DataService: Starting initialization');
    
    try {
      // 第一步：直接从Asset加载（最可靠）
      _addLog('DataService: Loading from assets...');
      await _loadFromAssetsOnly();
      await _loadTagAliasRules();
      _addLog('DataService: Asset load complete. Products: ${_products.length}, Applications: ${_applications.length}');
      
      // 第二步：如果Asset加载失败，从私有目录加载
      if (_products.isEmpty && _applications.isEmpty) {
        _addLog('DataService: Asset load failed, trying private directory...');
        final appDir = await getApplicationDocumentsDirectory();
        final dataDir = Directory('${appDir.path}/rst_data');
        await _loadFromPrivateDir(dataDir);
        _addLog('DataService: Private dir load complete. Products: ${_products.length}, Applications: ${_applications.length}');
      }
      
      // 第三步：如果还是空的，从Asset复制到私有目录
      if (_products.isEmpty && _applications.isEmpty) {
        _addLog('DataService: All loads failed, product list is empty!');
      } else {
        // 复制到私有目录以便后续使用
        _addLog('DataService: Copying data to private directory...');
        final appDir = await getApplicationDocumentsDirectory();
        final dataDir = Directory('${appDir.path}/rst_data');
        await _copyAssetsToPrivateDir(dataDir);
      }
      
      _initialized = true;
      _addLog('DataService: Initialization complete. Total: ${_products.length + _applications.length} items');
    } catch (e, stack) {
      _addLog('DataService: ERROR during initialization: $e');
      _addLog('DataService: Stack trace: $stack');
      _initialized = true; // 标记为已初始化，避免无限重试
    }
  }

  /// 从私有目录加载
  Future<void> _loadFromPrivateDir(Directory dataDir) async {
    try {
      // 加载产品列表
      final productsDir = Directory('${dataDir.path}/产品列表');
      if (await productsDir.exists()) {
        final files = await productsDir.list().toList();
        _addLog('DataService: Found ${files.length} product files in private dir');
        for (var entity in files) {
          if (entity is File && entity.path.endsWith('.md')) {
            try {
              final content = await entity.readAsString();
              _products.add(ProductItem.fromMdContent(entity.path, content));
            } catch (e) {
              _addLog('DataService: Error reading product file: ${entity.path}');
            }
          }
        }
      }
      
      // 加载产品应用
      final appsDir = Directory('${dataDir.path}/产品应用');
      if (await appsDir.exists()) {
        final files = await appsDir.list().toList();
        _addLog('DataService: Found ${files.length} application files in private dir');
        for (var entity in files) {
          if (entity is File && entity.path.endsWith('.md')) {
            try {
              final content = await entity.readAsString();
              _applications.add(ProductItem.fromMdContent(entity.path, content));
            } catch (e) {
              _addLog('DataService: Error reading application file: ${entity.path}');
            }
          }
        }
      }
    } catch (e) {
      _addLog('DataService: Error loading from private dir: $e');
    }
  }

  /// 只从Asset加载（不保存到私有目录）
  Future<void> _loadFromAssetsOnly() async {
    _addLog('DataService: Loading products from assets...');
    
    // 加载产品列表索引
    try {
      final indexContent = await rootBundle.loadString(_productsAssetIndex);
      final List<dynamic> productFiles = jsonDecode(indexContent);
      _addLog('DataService: Found ${productFiles.length} product files in index');
      
      for (final fileName in productFiles) {
        try {
          final content = await rootBundle.loadString('$_productsAssetPath/$fileName');
          _products.add(ProductItem.fromMdContent('$_productsAssetPath/$fileName', content));
        } catch (e) {
          _addLog('DataService: Error loading product $fileName: $e');
        }
      }
    } catch (e) {
      _addLog('DataService: Error loading product index: $e');
    }
    
    // 加载产品应用索引
    _addLog('DataService: Loading applications from assets...');
    try {
      final indexContent = await rootBundle.loadString(_applicationsAssetIndex);
      final List<dynamic> appFiles = jsonDecode(indexContent);
      _addLog('DataService: Found ${appFiles.length} application files in index');
      
      for (final fileName in appFiles) {
        try {
          final content = await rootBundle.loadString('$_applicationsAssetPath/$fileName');
          _applications.add(ProductItem.fromMdContent('$_applicationsAssetPath/$fileName', content));
        } catch (e) {
          _addLog('DataService: Error loading application $fileName: $e');
        }
      }
    } catch (e) {
      _addLog('DataService: Error loading application index: $e');
    }
    
    // 加载产品配方（通过 assets/产品配方.json 索引逐个加载）
    _addLog('DataService: Loading formulas from assets...');
    try {
      final formulaAssetPath = 'assets/产品配方';
      // 配方文件无 frontmatter，直接用文件名作为配方名称，body 即为 markdown 表格
      final formulaContent = await rootBundle.loadString('assets/产品配方.json');
      final List<dynamic> formulaFiles = jsonDecode(formulaContent);
      _addLog('DataService: Found ${formulaFiles.length} formula files');
      
      for (final fileName in formulaFiles) {
        try {
          final content = await rootBundle.loadString('$formulaAssetPath/$fileName');
          _formulas.add(ProductItem.fromMdContent('$formulaAssetPath/$fileName', content));
        } catch (e) {
          _addLog('DataService: Error loading formula $fileName: $e');
        }
      }
    } catch (e) {
      _addLog('DataService: Error loading formulas: $e');
    }

    // 加载 TDS 文档（通过 assets/产品TDS.json 索引逐个加载）
    _addLog('DataService: Loading TDS from assets...');
    try {
      final tdsIndexContent = await rootBundle.loadString(_tdsAssetIndex);
      final List<dynamic> tdsFiles = jsonDecode(tdsIndexContent);
      _addLog('DataService: Found ${tdsFiles.length} TDS files');

      for (final fileNameDynamic in tdsFiles) {
        final fileName = fileNameDynamic.toString();
        try {
          final content = await rootBundle.loadString('$_tdsAssetPath/$fileName');
          final productName = fileName.replaceAll('.TDS.md', '');
          _tdsByProduct[productName] = content;
          final normalized = _normalizeProductKey(productName);
          if (normalized.isNotEmpty) {
            _tdsByNormalizedProduct[normalized] = content;
          }
        } catch (e) {
          _addLog('DataService: Error loading TDS $fileName: $e');
        }
      }
    } catch (e) {
      _addLog('DataService: TDS index not found or failed to parse: $e');
    }
  }

  /// 加载标签同义词规则（优先用户私有目录，其次内置 Asset）。
  Future<void> _loadTagAliasRules() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory('${appDir.path}/rst_data');
    final customRuleFile = File('${dataDir.path}/$_tagAliasRulesFileName');
    String rawContent = '';

    if (await customRuleFile.exists()) {
      try {
        rawContent = await customRuleFile.readAsString();
        _addLog('DataService: Loaded custom tag alias rules from private dir');
      } catch (e) {
        _addLog('DataService: Failed to read custom tag alias rules: $e');
      }
    }

    if (rawContent.trim().isEmpty) {
      try {
        rawContent = await rootBundle.loadString(_tagAliasRulesAssetPath);
        _addLog('DataService: Loaded default tag alias rules from assets');
      } catch (e) {
        _addLog('DataService: Failed to load asset tag alias rules: $e');
        rawContent = '';
      }
    }

    _tagAliasRulesRaw = rawContent;
    _tagAliasRules = _parseTagAliasRules(rawContent);
    _addLog('DataService: Parsed ${_tagAliasRules.length} tag alias keys');
  }

  /// 保存标签同义词规则到私有目录，并更新内存映射。
  Future<void> saveTagAliasRules(String rawContent) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory('${appDir.path}/rst_data');
    await dataDir.create(recursive: true);
    final customRuleFile = File('${dataDir.path}/$_tagAliasRulesFileName');
    await customRuleFile.writeAsString(rawContent);
    _tagAliasRulesRaw = rawContent;
    _tagAliasRules = _parseTagAliasRules(rawContent);
    _addLog('DataService: Saved custom tag alias rules');
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

  /// 扩展关键词，包含自身以及同义词规则中的正向/反向映射。
  Set<String> _expandedKeywords(String keyword) {
    final normalized = keyword.toLowerCase().trim();
    if (normalized.isEmpty) return <String>{};

    final expanded = <String>{normalized};
    final queue = <String>[normalized];
    final visited = <String>{};

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (!visited.add(current)) continue;

      for (final alias in _tagAliasRules[current] ?? const <String>{}) {
        if (expanded.add(alias)) {
          queue.add(alias);
        }
      }

      for (final entry in _tagAliasRules.entries) {
        if (entry.value.contains(current) && expanded.add(entry.key)) {
          queue.add(entry.key);
        }
      }
    }

    return expanded;
  }

  /// 从Asset复制数据到私有目录
  Future<void> _copyAssetsToPrivateDir(Directory dataDir) async {
    try {
      await dataDir.create(recursive: true);
      
      // 复制产品列表
      try {
        final indexContent = await rootBundle.loadString(_productsAssetIndex);
        final List<dynamic> productFiles = jsonDecode(indexContent);
        
        final productsDir = Directory('${dataDir.path}/产品列表');
        await productsDir.create(recursive: true);
        
        for (final fileName in productFiles) {
          try {
            final content = await rootBundle.loadString('$_productsAssetPath/$fileName');
            final file = File('${productsDir.path}/$fileName');
            await file.writeAsString(content);
          } catch (e) {
            // 忽略单个文件错误
          }
        }
        _addLog('DataService: Copied ${productFiles.length} products to private dir');
      } catch (e) {
        _addLog('DataService: Error copying products: $e');
      }
      
      // 复制产品应用
      try {
        final indexContent = await rootBundle.loadString(_applicationsAssetIndex);
        final List<dynamic> appFiles = jsonDecode(indexContent);
        
        final appsDir = Directory('${dataDir.path}/产品应用');
        await appsDir.create(recursive: true);
        
        for (final fileName in appFiles) {
          try {
            final content = await rootBundle.loadString('$_applicationsAssetPath/$fileName');
            final file = File('${appsDir.path}/$fileName');
            await file.writeAsString(content);
          } catch (e) {
            // 忽略单个文件错误
          }
        }
        _addLog('DataService: Copied ${appFiles.length} applications to private dir');
      } catch (e) {
        _addLog('DataService: Error copying applications: $e');
      }
    } catch (e) {
      _addLog('DataService: Error in _copyAssetsToPrivateDir: $e');
    }
  }

  /// 搜索产品和应用
  /// 
  /// 搜索规则：
  /// 1) 单关键词：搜索范围包括文件名（产品牌号/应用名称）、实验牌号、标签。
  /// 2) 混合关键词（空格分词或自动分段后>=2个关键词）：仅在标签内进行 AND 匹配。
  /// 
  /// [query] 搜索关键词，支持空格分隔多个关键词
  /// 返回匹配的产品和应用列表
  List<ProductItem> search(String query) {
    if (query.isEmpty) return [];
    final normalizedQuery = query.toLowerCase().trim();

    Set<String> _buildSearchableTags(ProductItem item) {
      final searchable = <String>{};
      for (final rawTag in item.tags) {
        final normalizedTag = rawTag.toLowerCase();
        if (normalizedTag.isEmpty) continue;
        searchable.add(normalizedTag);
        searchable.addAll(_tagAliasRules[normalizedTag] ?? {});
      }
      return searchable;
    }

    bool _isExplicitPuFamilyQuery(List<String> segmentedKeywords) {
      const puFamilyTerms = <String>{'pu', '羟丙', '羟基丙烯酸'};
      final compact = normalizedQuery.replaceAll(RegExp(r'\s+'), '');
      if (compact.contains('pud')) return false;
      if (compact == 'pu') return false;
      if (!segmentedKeywords.any(puFamilyTerms.contains)) return false;
      if (segmentedKeywords.length <= 1) return false;
      if (segmentedKeywords.length == 2 && puFamilyTerms.contains(segmentedKeywords.last)) {
        return false;
      }
      return true;
    }

    bool _containsAnyTerm(Set<String> searchableTags, Set<String> terms) {
      return searchableTags.any((tag) => terms.contains(tag));
    }

    Set<String> _buildKnownTagTerms() {
      final knownTerms = <String>{};

      void addFromItem(ProductItem item) {
        knownTerms.addAll(_buildSearchableTags(item));
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

    List<String> _segmentByKnownTerms(String input, Set<String> knownTerms) {
      final source = input.toLowerCase().trim();
      if (source.isEmpty) return const <String>[];

      final matchesAt = List<List<String>>.generate(source.length + 1, (_) => <String>[]);
      for (final term in knownTerms) {
        if (term.isEmpty || term == source || term.length > source.length) continue;
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
      final knownTerms = _buildKnownTagTerms();
      final segmentedByKnownTerms = _segmentByKnownTerms(normalizedQuery, knownTerms);
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
      final knownTerms = _buildKnownTagTerms();
      final segmented = _segmentByKnownTerms(keywords.first, knownTerms);
      if (segmented.length > 1) {
        keywords
          ..clear()
          ..addAll(segmented);
      }
    }
    
    if (keywords.isEmpty) return [];
    
    final strictPuFamily = _isExplicitPuFamilyQuery(keywords);
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

    bool containsKeyword(ProductItem item, String keyword) {
      final searchableTags = _buildSearchableTags(item);
      if (strictPuFamily && _containsAnyTerm(searchableTags, pudTerms)) {
        return false;
      }
      final searchableTagsText = searchableTags.join(' ');
      final singleKeywordSearchText =
          '${item.fileName} ${item.experimentalCode ?? ''} $searchableTagsText'
              .toLowerCase();
      final expanded = _expandedKeywords(keyword);
      if (isDigitsOnly(keyword)) {
        final numericKeyword = keyword.toLowerCase();
        return startsWithNumericBody(item.fileName, numericKeyword) ||
            startsWithNumericBody(item.experimentalCode, numericKeyword);
      }
      return expanded.any(singleKeywordSearchText.contains);
    }

    bool matchesMixedKeywordsInTagsOnly(ProductItem item) {
      final searchableTags = _buildSearchableTags(item);
      if (strictPuFamily && _containsAnyTerm(searchableTags, pudTerms)) {
        return false;
      }
      final tagsText = searchableTags.join(' ').toLowerCase();
      return keywords.every((keyword) {
        final expanded = _expandedKeywords(keyword);
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

  /// 清除应用数据
  Future<void> clearData() async {
    _addLog('DataService: Clearing data');
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dataDir = Directory('${appDir.path}/rst_data');
      if (await dataDir.exists()) {
        await dataDir.delete(recursive: true);
      }
      _products.clear();
      _applications.clear();
      _initialized = false;
    } catch (e) {
      _addLog('DataService: Error clearing data: $e');
    }
  }
  
  /// 清除日志
  void clearLogs() {
    _logs.clear();
    _addLog('DataService: Logs cleared');
  }
}
