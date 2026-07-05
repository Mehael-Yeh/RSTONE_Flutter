/// 本地偏好与轻量数据持久化服务。
library;

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
  /// 主题色种子值存储键（Color.value）
  static const String _themeSeedColorValueKey = 'theme_seed_color_value';
  /// 产品笔记存储键（Map<项目名称, 笔记内容>）
  static const String _productNotesKey = 'product_notes';

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

  /// 获取主题色种子值，默认使用品牌橙色。
  int getThemeSeedColorValue() {
    return _prefs?.getInt(_themeSeedColorValueKey) ?? 0xFFFF8A00;
  }

  /// 保存主题色种子值（Color.value）。
  Future<void> saveThemeSeedColorValue(int colorValue) async {
    await _prefs?.setInt(_themeSeedColorValueKey, colorValue);
  }

  /// 获取全部产品笔记。
  Map<String, String> getAllProductNotes() {
    final saved = _prefs?.getString(_productNotesKey);
    if (saved == null || saved.isEmpty) return {};
    try {
      final decoded = jsonDecode(saved);
      if (decoded is! Map) return {};
      final result = <String, String>{};
      decoded.forEach((key, value) {
        final noteKey = key.toString().trim();
        final noteValue = value?.toString() ?? '';
        if (noteKey.isNotEmpty && noteValue.isNotEmpty) {
          result[noteKey] = noteValue;
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  /// 获取单个项目的笔记。
  String getProductNote(String itemName) {
    return getAllProductNotes()[itemName] ?? '';
  }

  /// 保存单个项目笔记。空内容会移除对应项目。
  Future<void> saveProductNote(String itemName, String note) async {
    final normalizedName = itemName.trim();
    if (normalizedName.isEmpty) return;

    final notes = getAllProductNotes();
    final normalizedNote = note.trim();
    if (normalizedNote.isEmpty) {
      notes.remove(normalizedName);
    } else {
      notes[normalizedName] = normalizedNote;
    }
    await _prefs?.setString(_productNotesKey, jsonEncode(notes));
  }

  /// 清除所有产品笔记。
  Future<void> clearAllProductNotes() async {
    await _prefs?.remove(_productNotesKey);
  }
}
