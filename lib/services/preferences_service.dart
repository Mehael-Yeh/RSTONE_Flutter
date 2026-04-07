import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 用户偏好设置服务
class PreferencesService {
  static const String _productListColumnsKey = 'product_list_columns';
  static const String _productListSortKey = 'product_list_sort';
  static const String _applicationColumnsKey = 'application_columns';
  static const String _applicationSortKey = 'application_sort';
  static const String _productListSortDescKey = 'product_list_sort_desc';
  static const String _applicationSortDescKey = 'application_sort_desc';

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
}
