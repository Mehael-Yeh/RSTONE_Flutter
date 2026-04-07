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

  List<ProductItem> get products => _products;
  List<ProductItem> get applications => _applications;
  bool get isInitialized => _initialized;

  /// 初始化
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      // 先尝试从私有目录加载
      final appDir = await getApplicationDocumentsDirectory();
      final dataDir = Directory('${appDir.path}/rst_data');
      
      bool hasData = false;
      
      // 检查私有目录是否有数据
      if (await dataDir.exists()) {
        final productsDir = Directory('${dataDir.path}/产品列表');
        final appsDir = Directory('${dataDir.path}/产品应用');
        
        final productFiles = await productsDir.list().toList();
        final appFiles = await appsDir.list().toList();
        
        if (productFiles.isNotEmpty || appFiles.isNotEmpty) {
          await _loadFromPrivateDir(dataDir);
          hasData = true;
        }
      }
      
      // 如果私有目录没有数据，从Asset加载
      if (!hasData) {
        await _loadFromAssets(dataDir);
      }
      
      _initialized = true;
    } catch (e) {
      // 确保至少加载了数据
      if (_products.isEmpty || _applications.isEmpty) {
        await _loadFromAssetsOnly();
      }
      _initialized = true;
    }
  }

  /// 从私有目录加载
  Future<void> _loadFromPrivateDir(Directory dataDir) async {
    // 加载产品列表
    final productsDir = Directory('${dataDir.path}/产品列表');
    if (await productsDir.exists()) {
      await for (var entity in productsDir.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          try {
            final content = await entity.readAsString();
            _products.add(ProductItem.fromMdContent(entity.path, content));
          } catch (e) {
            // 跳过
          }
        }
      }
    }
    
    // 加载产品应用
    final appsDir = Directory('${dataDir.path}/产品应用');
    if (await appsDir.exists()) {
      await for (var entity in appsDir.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          try {
            final content = await entity.readAsString();
            _applications.add(ProductItem.fromMdContent(entity.path, content));
          } catch (e) {
            // 跳过
          }
        }
      }
    }
  }

  /// 从Asset加载数据并保存到私有目录
  Future<void> _loadFromAssets(Directory dataDir) async {
    try {
      await dataDir.create(recursive: true);
      
      // 加载产品列表索引
      try {
        final indexContent = await rootBundle.loadString(_productsAssetIndex);
        final List<dynamic> productFiles = jsonDecode(indexContent);
        
        for (final fileName in productFiles) {
          try {
            final content = await rootBundle.loadString('$_productsAssetPath/$fileName');
            final file = File('${dataDir.path}/产品列表/$fileName');
            await file.parent.create(recursive: true);
            await file.writeAsString(content);
            _products.add(ProductItem.fromMdContent(file.path, content));
          } catch (e) {
            // 文件不存在，跳过
          }
        }
      } catch (e) {
        // 索引加载失败
      }
      
      // 加载产品应用索引
      try {
        final indexContent = await rootBundle.loadString(_applicationsAssetIndex);
        final List<dynamic> appFiles = jsonDecode(indexContent);
        
        for (final fileName in appFiles) {
          try {
            final content = await rootBundle.loadString('$_applicationsAssetPath/$fileName');
            final file = File('${dataDir.path}/产品应用/$fileName');
            await file.parent.create(recursive: true);
            await file.writeAsString(content);
            _applications.add(ProductItem.fromMdContent(file.path, content));
          } catch (e) {
            // 文件不存在，跳过
          }
        }
      } catch (e) {
        // 索引加载失败
      }
    } catch (e) {
      // 尝试只从Asset加载
      await _loadFromAssetsOnly();
    }
  }

  /// 只从Asset加载（不保存到私有目录）
  Future<void> _loadFromAssetsOnly() async {
    try {
      // 加载产品列表
      try {
        final indexContent = await rootBundle.loadString(_productsAssetIndex);
        final List<dynamic> productFiles = jsonDecode(indexContent);
        
        for (final fileName in productFiles) {
          try {
            final content = await rootBundle.loadString('$_productsAssetPath/$fileName');
            _products.add(ProductItem.fromMdContent('$_productsAssetPath/$fileName', content));
          } catch (e) {
            // 跳过
          }
        }
      } catch (e) {
        // 索引加载失败
      }
      
      // 加载产品应用
      try {
        final indexContent = await rootBundle.loadString(_applicationsAssetIndex);
        final List<dynamic> appFiles = jsonDecode(indexContent);
        
        for (final fileName in appFiles) {
          try {
            final content = await rootBundle.loadString('$_applicationsAssetPath/$fileName');
            _applications.add(ProductItem.fromMdContent('$_applicationsAssetPath/$fileName', content));
          } catch (e) {
            // 跳过
          }
        }
      } catch (e) {
        // 索引加载失败
      }
    } catch (e) {
      // 忽略
    }
  }

  /// 搜索产品和应用
  List<ProductItem> search(String query) {
    if (query.isEmpty) return [];
    
    final lowerQuery = query.toLowerCase();
    final results = <ProductItem>[];
    
    for (var product in _products) {
      if (product.searchText.contains(lowerQuery)) {
        results.add(product);
      }
    }
    
    for (var app in _applications) {
      if (app.searchText.contains(lowerQuery)) {
        results.add(app);
      }
    }
    
    return results;
  }

  /// 清除应用数据
  Future<void> clearData() async {
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
      // 忽略
    }
  }
}
