/// 本地偏好与轻量数据持久化服务。
library;

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Exact product_notes value before and after a single guarded key move.
class ProductNoteChange {
  final String? before;
  final String after;
  const ProductNoteChange(this.before, this.after);
  Map<String, dynamic> toJson() => {'before': before, 'after': after};
  factory ProductNoteChange.fromJson(Map<String, dynamic> value) =>
      ProductNoteChange(value['before'] as String?, value['after'] as String);
}

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

  /// Strict, exact snapshots: a failed or interrupted rename may only undo
  /// its own write, never a later note edit (including unrelated annotations).
  ProductNoteChange? prepareProductNoteRename(String oldName, String newName,
      {required bool officialSource}) {
    final prefs = _prefs ?? (throw StateError('备注存储尚未初始化，未更名'));
    final before = prefs.getString(_productNotesKey);
    final notes = before == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(before) as Map);
    if (notes.entries.any((e) => e.key.trim() != e.key || e.value is! String)) {
      throw StateError('备注格式异常，未更名；请先备份并检查备注');
    }
    if ((notes[newName] as String? ?? '').isNotEmpty) {
      throw StateError('目标名称已有备注，未更名；请先备份并处理目标备注');
    }
    final note = notes[oldName] as String? ?? '';
    if (note.isEmpty) return null;
    if (officialSource) {
      throw StateError('原名称与官方产品共用备注，归属不明确，未更名；请先备份并处理备注');
    }
    notes.remove(oldName);
    notes[newName] = note;
    return ProductNoteChange(before, jsonEncode(notes));
  }

  void checkProductNoteChange(ProductNoteChange change) {
    final current = (_prefs ?? (throw StateError('备注存储尚未初始化')))
        .getString(_productNotesKey);
    if (current != change.before && current != change.after) {
      throw StateError('备注已变化，暂停更名恢复；请保留备份并处理冲突');
    }
  }

  Future<void> applyProductNoteChange(ProductNoteChange change,
      {required bool rollback}) async {
    checkProductNoteChange(change);
    final prefs = _prefs!;
    final target = rollback ? change.before : change.after;
    if (prefs.getString(_productNotesKey) == target) return;
    final ok = target == null
        ? await prefs.remove(_productNotesKey)
        : await prefs.setString(_productNotesKey, target);
    if (!ok) throw StateError('备注保存失败，更名未完成');
  }

  /// 清除所有产品笔记。
  Future<void> clearAllProductNotes() async {
    await _prefs?.remove(_productNotesKey);
  }
}
