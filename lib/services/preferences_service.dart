import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 用户偏好设置服务
/// 
/// 负责持久化用户的个性化设置，包括：
/// - 产品列表/产品应用的列显示顺序
/// - 排序列和排序方向
/// 
/// 使用 shared_preferences 进行本地存储，卸载应用后数据清除。
class PreferencesService {
  // ===== Storage Keys =====
  /// 产品列表列顺序存储键
  static const String _productListColumnsKey = 'product_list_columns';
  /// 产品列表排序列存储键
  static const String _productListSortKey = 'product_list_sort';
  /// 产品列表排序方向存储键
  static const String _productListSortDescKey = 'product_list_sort_desc';
  /// 产品应用列顺序存储键
  static const String _applicationColumnsKey = 'application_columns';
  /// 产品应用排序列存储键
  static const String _applicationSortKey = 'application_sort';
  /// 产品应用排序方向存储键
  static const String _applicationSortDescKey = 'application_sort_desc';
  /// 主题模式存储键（system/light/dark）
  static const String _themeModeKey = 'theme_mode';

  /// SharedPreferences 实例
  SharedPreferences? _prefs;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 获取产品列表的列顺序
  List<String> getProductListColumns(List<String> defaultColumns) {
    final saved = _prefs?.getString(_productListColumnsKey);
    if (saved == null) return defaultColumns;
    try {
      final List<dynamic> decoded = jsonDecode(saved);
      return decoded.cast<String>();
    } catch (e) {
      return defaultColumns;
    }
  }

  /// 保存产品列表的列顺序
  Future<void> saveProductListColumns(List<String> columns) async {
    await _prefs?.setString(_productListColumnsKey, jsonEncode(columns));
  }

  /// 获取产品列表的排序列
  String? getProductListSort() {
    return _prefs?.getString(_productListSortKey);
  }

  /// 保存产品列表的排序列
  Future<void> saveProductListSort(String? column) async {
    if (column == null) {
      await _prefs?.remove(_productListSortKey);
    } else {
      await _prefs?.setString(_productListSortKey, column);
    }
  }

  /// 获取产品列表排序方向
  bool getProductListSortDesc() {
    return _prefs?.getBool(_productListSortDescKey) ?? false;
  }

  /// 保存产品列表排序方向
  Future<void> saveProductListSortDesc(bool descending) async {
    await _prefs?.setBool(_productListSortDescKey, descending);
  }

  /// 获取产品应用的列顺序
  List<String> getApplicationColumns(List<String> defaultColumns) {
    final saved = _prefs?.getString(_applicationColumnsKey);
    if (saved == null) return defaultColumns;
    try {
      final List<dynamic> decoded = jsonDecode(saved);
      return decoded.cast<String>();
    } catch (e) {
      return defaultColumns;
    }
  }

  /// 保存产品应用的列顺序
  Future<void> saveApplicationColumns(List<String> columns) async {
    await _prefs?.setString(_applicationColumnsKey, jsonEncode(columns));
  }

  /// 获取产品应用的排序列
  String? getApplicationSort() {
    return _prefs?.getString(_applicationSortKey);
  }

  /// 保存产品应用的排序列
  Future<void> saveApplicationSort(String? column) async {
    if (column == null) {
      await _prefs?.remove(_applicationSortKey);
    } else {
      await _prefs?.setString(_applicationSortKey, column);
    }
  }

  /// 获取产品应用排序方向
  bool getApplicationSortDesc() {
    return _prefs?.getBool(_applicationSortDescKey) ?? false;
  }

  /// 保存产品应用排序方向
  Future<void> saveApplicationSortDesc(bool descending) async {
    await _prefs?.setBool(_applicationSortDescKey, descending);
  }

  /// 获取主题模式，默认跟随系统。
  String getThemeMode() {
    return _prefs?.getString(_themeModeKey) ?? 'system';
  }

  /// 保存主题模式（system/light/dark）。
  Future<void> saveThemeMode(String mode) async {
    await _prefs?.setString(_themeModeKey, mode);
  }
}
