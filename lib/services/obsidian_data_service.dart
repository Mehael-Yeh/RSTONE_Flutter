import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/product_item.dart';

/// Obsidian数据服务
class ObsidianDataService {
  static const String _productsAssetIndex = 'assets/产品列表.json';
  static const String _applicationsAssetIndex = 'assets/产品应用.json';
  static const String _productsAssetPath = 'assets/产品列表';
  static const String _applicationsAssetPath = 'assets/产品应用';
  
  List<ProductItem> _products = [];
  List<ProductItem> _applications = [];
  bool _initialized = false;
  
  /// 日志记录
  final List<String> _logs = [];
  
  List<ProductItem> get products => _products;
  List<ProductItem> get applications => _applications;
  bool get isInitialized => _initialized;
  List<String> get logs => List.unmodifiable(_logs);

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    _logs.insert(0, '[$timestamp] $message');
    // 只保留最近100条日志
    if (_logs.length > 100) {
      _logs.removeLast();
    }
  }

  /// 初始化
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

  /// 搜索产品和应用（分词 AND 匹配：所有关键词都出现在 searchText 中即匹配）
  List<ProductItem> search(String query) {
    if (query.isEmpty) return [];
    
    final keywords = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((k) => k.isNotEmpty)
        .toList();
    
    if (keywords.isEmpty) return [];
    
    final results = <ProductItem>[];
    
    _addLog('DataService: Searching for keywords: $keywords');
    
    bool matchesAllKeywords(String searchText) {
      return keywords.every((keyword) => searchText.contains(keyword));
    }
    
    for (var product in _products) {
      if (matchesAllKeywords(product.searchText)) {
        results.add(product);
      }
    }
    
    for (var app in _applications) {
      if (matchesAllKeywords(app.searchText)) {
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
