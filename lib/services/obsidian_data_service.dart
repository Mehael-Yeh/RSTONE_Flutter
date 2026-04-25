/// Obsidian 数据聚合服务，负责索引、搜索与缓存管理。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
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
  /// 标签同义词规则（代码内置，不依赖可替换 Asset 文件）
  static const String _builtInTagAliasRulesDefault = '''
# 标签同义词规则：格式 `左侧标签 -> 右侧扩展词`
# 支持 `->` 或 `→`，左侧可用 `、` / `,` / `，` 分隔多个标签

PVD -> 真空镀
PVD -> 镀膜
PVD -> 物理气相沉积
PU -> 羟丙
PU -> 羟基丙烯酸
PUD -> 自干
PUD -> 聚氨酯分散体
PC -> 聚碳酸酯
ABS -> 丙烯腈-丁二烯-苯乙烯共聚物
PA、PA6、PA66、TR90 -> 尼龙
PMMA -> 亚克力
TPEE -> 热塑性弹性体
PET -> 聚对苯二甲酸乙二醇酯
PS -> 聚苯乙烯
PE -> 聚乙烯
PP -> 聚丙烯
PPS -> 聚苯硫醚
PEEK -> 聚醚醚酮
''';
  /// 标签同义词规则文档（用户新增，仅存储在应用私有目录）
  static const String _tagAliasCustomRulesFileName = 'tag_alias_rules.custom.txt';
  
  /// 产品列表数据
  List<ProductItem> _products = [];
  /// 产品应用数据
  List<ProductItem> _applications = [];
  /// 产品配方数据
  List<ProductItem> _formulas = [];
  /// 内置标签同义词规则（来自 assets，不允许外部修改）
  String _builtInTagAliasRulesRaw = '';
  /// 用户自定义新增规则（来自应用私有目录）
  String _customTagAliasRulesRaw = '';
  /// 合并后的规则文本（用于展示）
  String _combinedTagAliasRulesRaw = '';
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
  String get builtInTagAliasRulesRaw => _builtInTagAliasRulesRaw;
  String get customTagAliasRulesRaw => _customTagAliasRulesRaw;
  String get tagAliasRulesRaw => _combinedTagAliasRulesRaw;
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

  Future<Directory?> _getPrivateDataDirectory() async {
    if (kIsWeb) return null;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      return Directory('${appDir.path}/rst_data');
    } on MissingPluginException catch (e) {
      _addLog('DataService: Private dir plugin unavailable: $e');
      return null;
    } catch (e) {
      _addLog('DataService: Failed to resolve private dir: $e');
      return null;
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
        final dataDir = await _getPrivateDataDirectory();
        if (dataDir != null) {
          await _loadFromPrivateDir(dataDir);
        }
        _addLog('DataService: Private dir load complete. Products: ${_products.length}, Applications: ${_applications.length}');
      }
      
      // 第三步：如果还是空的，从Asset复制到私有目录
      if (_products.isEmpty && _applications.isEmpty) {
        _addLog('DataService: All loads failed, product list is empty!');
      } else {
        // 复制到私有目录以便后续使用
        _addLog('DataService: Copying data to private directory...');
        final dataDir = await _getPrivateDataDirectory();
        if (dataDir != null) {
          await _copyAssetsToPrivateDir(dataDir);
        }
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

  /// 加载标签同义词规则（内置规则 + 用户新增规则）。
  Future<void> _loadTagAliasRules() async {
    _builtInTagAliasRulesRaw = '';
    _customTagAliasRulesRaw = '';

    _builtInTagAliasRulesRaw = _builtInTagAliasRulesDefault;
    _addLog('DataService: Loaded built-in tag alias rules from source code');

    final dataDir = await _getPrivateDataDirectory();
    if (dataDir != null) {
      final customRuleFile = File('${dataDir.path}/$_tagAliasCustomRulesFileName');

      if (await customRuleFile.exists()) {
        try {
          _customTagAliasRulesRaw = await customRuleFile.readAsString();
          _addLog('DataService: Loaded custom tag alias rules from private dir');
        } catch (e) {
          _addLog('DataService: Failed to read custom tag alias rules: $e');
        }
      }
    } else {
      _addLog('DataService: Private dir unavailable for custom tag alias rules');
    }

    _tagAliasRules = _parseTagAliasRules(_builtInTagAliasRulesRaw);
    final customMap = _parseTagAliasRules(_customTagAliasRulesRaw);
    _mergeTagAliasRules(customMap);
    _combinedTagAliasRulesRaw = _composeCombinedTagAliasRulesText();
    _addLog('DataService: Parsed ${_tagAliasRules.length} tag alias keys');
  }

  /// 保存用户新增标签同义词规则到私有目录，并更新内存映射。
  Future<void> saveTagAliasRules(String rawContent) async {
    final dataDir = await _getPrivateDataDirectory();
    if (dataDir == null) {
      _addLog('DataService: Skip saving custom tag alias rules on this platform');
      return;
    }
    await dataDir.create(recursive: true);
    final customRuleFile = File('${dataDir.path}/$_tagAliasCustomRulesFileName');
    await customRuleFile.writeAsString(rawContent);
    _customTagAliasRulesRaw = rawContent;
    _tagAliasRules = _parseTagAliasRules(_builtInTagAliasRulesRaw);
    final customMap = _parseTagAliasRules(_customTagAliasRulesRaw);
    _mergeTagAliasRules(customMap);
    _combinedTagAliasRulesRaw = _composeCombinedTagAliasRulesText();
    _addLog('DataService: Saved custom tag alias rules');
  }

  void _mergeTagAliasRules(Map<String, Set<String>> additionalRules) {
    for (final entry in additionalRules.entries) {
      _tagAliasRules.putIfAbsent(entry.key, () => <String>{}).addAll(entry.value);
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

      // 复制产品配方
      try {
        final formulaIndexContent = await rootBundle.loadString('assets/产品配方.json');
        final List<dynamic> formulaFiles = jsonDecode(formulaIndexContent);
        final formulasDir = Directory('${dataDir.path}/产品配方');
        await formulasDir.create(recursive: true);
        for (final fileName in formulaFiles) {
          try {
            final content = await rootBundle.loadString('assets/产品配方/$fileName');
            final file = File('${formulasDir.path}/$fileName');
            await file.writeAsString(content);
          } catch (_) {}
        }
        _addLog('DataService: Copied ${formulaFiles.length} formulas to private dir');
      } catch (e) {
        _addLog('DataService: Error copying formulas: $e');
      }
    } catch (e) {
      _addLog('DataService: Error in _copyAssetsToPrivateDir: $e');
    }
  }

  String _joinTagsToYamlList(List<String> tags) {
    final normalized = tags.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
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
水接触角: $waterContactAngle
技术源: $technologySource
对标: $benchmark
粘度: $viscosity
---
'''.trim();
  }

  String buildApplicationMarkdownTemplate({
    required List<String> tags,
    String primer = '',
    String midCoat = '',
    String topCoat = '',
    String baseMaterial = '',
  }) {
    return '''
---
${_joinTagsToYamlList(tags)}
基材: $baseMaterial
底漆: $primer
中漆: $midCoat
面漆: $topCoat
---
'''.trim();
  }

  String buildFormulaMarkdownTemplate({required String tableMarkdown}) {
    return tableMarkdown.trim().isEmpty
        ? '| 项目 | 数值 |\n| --- | --- |\n| 示例 | 0 |'
        : tableMarkdown.trim();
  }

  Future<void> addProductMarkdown({
    required String code,
    required String markdown,
  }) async {
    final normalizedCode = code.trim().toUpperCase();
    if (!RegExp(r'^R[DS]\d{3,}$').hasMatch(normalizedCode)) {
      throw ArgumentError('文件名需符合 RDXXX 或 RSXXX 格式');
    }
    final dataDir = await _getPrivateDataDirectory();
    if (dataDir == null) {
      throw StateError('当前平台不支持写入本地 Markdown 数据');
    }
    final productDir = Directory('${dataDir.path}/产品列表');
    await productDir.create(recursive: true);
    final file = File('${productDir.path}/$normalizedCode.md');
    await file.writeAsString(markdown.trim());
    _products.removeWhere((item) => item.fileName.toUpperCase() == normalizedCode);
    _products.add(ProductItem.fromMdContent(file.path, markdown));
    _products.sort((a, b) => a.fileName.compareTo(b.fileName));
    _addLog('DataService: Saved manual product file $normalizedCode.md');
  }

  Future<void> addApplicationMarkdown({
    required String name,
    required String markdown,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('产品应用名称不能为空');
    }
    final dataDir = await _getPrivateDataDirectory();
    if (dataDir == null) {
      throw StateError('当前平台不支持写入本地 Markdown 数据');
    }
    final appDir = Directory('${dataDir.path}/产品应用');
    await appDir.create(recursive: true);
    final file = File('${appDir.path}/$normalizedName.md');
    await file.writeAsString(markdown.trim());
    _applications.removeWhere((item) => item.fileName == normalizedName);
    _applications.add(ProductItem.fromMdContent(file.path, markdown));
    _applications.sort((a, b) => a.fileName.compareTo(b.fileName));
    _addLog('DataService: Saved manual application file $normalizedName.md');
  }

  Future<void> addFormulaMarkdown({
    required String name,
    required String markdown,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('产品配方名称不能为空');
    }
    final dataDir = await _getPrivateDataDirectory();
    if (dataDir == null) {
      throw StateError('当前平台不支持写入本地 Markdown 数据');
    }
    final formulaDir = Directory('${dataDir.path}/产品配方');
    await formulaDir.create(recursive: true);
    final file = File('${formulaDir.path}/$normalizedName.md');
    await file.writeAsString(markdown.trim());
    _formulas.removeWhere((item) => item.fileName == normalizedName);
    _formulas.add(ProductItem.fromMdContent(file.path, markdown));
    _formulas.sort((a, b) => a.fileName.compareTo(b.fileName));
    _addLog('DataService: Saved manual formula file $normalizedName.md');
  }

  Future<File?> exportMarkdownArchive() async {
    if (kIsWeb) {
      _addLog('DataService: Export archive skipped on web platform');
      return null;
    }
    final dataDir = await _getPrivateDataDirectory();
    if (dataDir == null) return null;

    final archive = Archive();
    Future<void> addMdFiles(String folderName) async {
      final folder = Directory('${dataDir.path}/$folderName');
      if (!await folder.exists()) return;
      await for (final entity in folder.list(recursive: false)) {
        if (entity is! File || !entity.path.endsWith('.md')) continue;
        final content = await entity.readAsString();
        final bytes = utf8.encode(content);
        final entryName = '$folderName/${entity.uri.pathSegments.last}';
        archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
      }
    }

    await addMdFiles('产品列表');
    await addMdFiles('产品应用');
    await addMdFiles('产品配方');

    if (archive.isEmpty) {
      _addLog('DataService: Export archive skipped because no markdown file found');
      return null;
    }

    final tmpDir = await getTemporaryDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll('.', '')
        .substring(0, 15);
    final file = File('${tmpDir.path}/RSTONE_Obsidian_MD_$timestamp.zip');
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      _addLog('DataService: Export archive failed due to zip encoder returning null');
      return null;
    }
    await file.writeAsBytes(Uint8List.fromList(zipBytes), flush: true);
    _addLog('DataService: Exported markdown archive at ${file.path}');
    return file;
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

    bool _shouldExcludePudResults(List<String> segmentedKeywords) {
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
    
    final excludePudResults = _shouldExcludePudResults(keywords);
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
      if (excludePudResults && _containsAnyTerm(searchableTags, pudTerms)) {
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
      return expanded.any(singleKeywordSearchText.contains);
    }

    bool matchesMixedKeywordsInTagsOnly(ProductItem item) {
      final searchableTags = _buildSearchableTags(item);
      if (excludePudResults && _containsAnyTerm(searchableTags, pudTerms)) {
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
      final dataDir = await _getPrivateDataDirectory();
      if (dataDir != null && await dataDir.exists()) {
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
