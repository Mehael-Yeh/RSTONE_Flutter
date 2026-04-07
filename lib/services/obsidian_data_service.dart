import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/product_item.dart';

/// Obsidian数据服务
class ObsidianDataService {
  static const String _sourcePath = '/vol2/1000/Obsidian/锐石';
  static const String _productsFolder = '产品列表';
  static const String _applicationsFolder = '产品应用';
  
  List<ProductItem> _products = [];
  List<ProductItem> _applications = [];
  bool _initialized = false;

  List<ProductItem> get products => _products;
  List<ProductItem> get applications => _applications;
  bool get isInitialized => _initialized;

  /// 初始化：复制数据到应用私有目录并解析
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      // 获取应用文档目录
      final appDir = await getApplicationDocumentsDirectory();
      final dataDir = Directory('${appDir.path}/rst_data');
      
      // 如果数据目录不存在，先复制数据
      if (!await dataDir.exists()) {
        await dataDir.create(recursive: true);
        await _copyData(dataDir);
      }
      
      // 读取并解析MD文件
      await _loadProducts(dataDir);
      await _loadApplications(dataDir);
      
      _initialized = true;
    } catch (e) {
      // 如果无法访问Obsidian源，直接从源路径读取
      await _loadFromSource();
      _initialized = true;
    }
  }

  /// 从Obsidian源路径复制数据到应用私有目录
  Future<void> _copyData(Directory dataDir) async {
    try {
      final productsSource = Directory('$_sourcePath/$_productsFolder');
      final appsSource = Directory('$_sourcePath/$_applicationsFolder');
      
      if (await productsSource.exists()) {
        final productsDest = Directory('${dataDir.path}/$_productsFolder');
        await productsDest.create(recursive: true);
        await for (var entity in productsSource.list()) {
          if (entity is File && entity.path.endsWith('.md')) {
            await entity.copy('${productsDest.path}/${entity.path.split('/').last}');
          }
        }
      }
      
      if (await appsSource.exists()) {
        final appsDest = Directory('${dataDir.path}/$_applicationsFolder');
        await appsDest.create(recursive: true);
        await for (var entity in appsSource.list()) {
          if (entity is File && entity.path.endsWith('.md')) {
            await entity.copy('${appsDest.path}/${entity.path.split('/').last}');
          }
        }
      }
    } catch (e) {
      // 复制失败，后续会尝试直接从源路径读取
    }
  }

  /// 从应用数据目录加载产品列表
  Future<void> _loadProducts(Directory dataDir) async {
    final productsDir = Directory('${dataDir.path}/$_productsFolder');
    
    if (await productsDir.exists()) {
      await for (var entity in productsDir.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          try {
            final content = await entity.readAsString();
            _products.add(ProductItem.fromMdContent(entity.path, content));
          } catch (e) {
            // 跳过无法读取的文件
          }
        }
      }
    }
  }

  /// 从应用数据目录加载产品应用
  Future<void> _loadApplications(Directory dataDir) async {
    final appsDir = Directory('${dataDir.path}/$_applicationsFolder');
    
    if (await appsDir.exists()) {
      await for (var entity in appsDir.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          try {
            final content = await entity.readAsString();
            _applications.add(ProductItem.fromMdContent(entity.path, content));
          } catch (e) {
            // 跳过无法读取的文件
          }
        }
      }
    }
  }

  /// 直接从Obsidian源路径加载数据（备用方案）
  Future<void> _loadFromSource() async {
    try {
      final productsSource = Directory('$_sourcePath/$_productsFolder');
      final appsSource = Directory('$_sourcePath/$_applicationsFolder');
      
      if (await productsSource.exists()) {
        await for (var entity in productsSource.list()) {
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
      
      if (await appsSource.exists()) {
        await for (var entity in appsSource.list()) {
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
    } catch (e) {
      // 加载失败，数据列表为空
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

  /// 清除应用数据（卸载时调用）
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
      // 忽略错误
    }
  }
}
