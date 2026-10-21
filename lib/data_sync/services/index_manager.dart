import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';
import '../../models/product_item.dart';
import '../../utils/natural_sort.dart';

const officialRulesPath = '产品列表/标签同义词规则.md';

class DataSnapshot {
  final List<ProductItem> products, applications, formulas;
  final Map<String, String> tds;
  final String? rules;
  const DataSnapshot(
      {this.products = const [],
      this.applications = const [],
      this.formulas = const [],
      this.tds = const {},
      this.rules});
}

/// Reuse the existing business parser. Validation and bulk parsing run off the
/// UI isolate on native platforms; Web yields while reading each object.
class IndexManager {
  Future<DataSnapshot> prepare(Map<String, String> files) async {
    if (!kIsWeb) return compute(parseOfficialFiles, files);
    final products = <ProductItem>[],
        applications = <ProductItem>[],
        formulas = <ProductItem>[];
    final tds = <String, String>{};
    String? rules;
    final entries = files.entries.toList();
    for (var offset = 0; offset < entries.length; offset += 32) {
      final batch =
          parseOfficialFiles(Map.fromEntries(entries.skip(offset).take(32)));
      products.addAll(batch.products);
      applications.addAll(batch.applications);
      formulas.addAll(batch.formulas);
      tds.addAll(batch.tds);
      rules = batch.rules ?? rules;
      await Future<void>.delayed(Duration.zero);
    }
    return DataSnapshot(
        products: List.unmodifiable(products),
        applications: List.unmodifiable(applications),
        formulas: List.unmodifiable(formulas),
        tds: Map.unmodifiable(tds),
        rules: rules);
  }
}

DataSnapshot parseOfficialFiles(Map<String, String> files) {
  final products = <ProductItem>[],
      applications = <ProductItem>[],
      formulas = <ProductItem>[];
  final tds = <String, String>{};
  String? rules;
  for (final entry in files.entries) {
    final path = entry.key;
    final content = entry.value.startsWith('\uFEFF')
        ? entry.value.substring(1)
        : entry.value;
    if (content.trim().isEmpty) throw FormatException('空白资料: $path');
    if (content.startsWith('---\n') || content.startsWith('---\r\n')) {
      final lines = const LineSplitter().convert(content);
      final end = lines.indexWhere((l) => l.trim() == '---', 1);
      if (end < 0) throw FormatException('资料前置字段未结束: $path');
      final yaml = loadYaml(lines.sublist(1, end).join('\n'));
      if (yaml != null && yaml is! YamlMap) {
        throw FormatException('资料前置字段格式无效: $path');
      }
    }
    if (path == officialRulesPath) {
      rules = content;
      continue;
    }
    if (path.startsWith('产品TDS/')) {
      // Retain full relative names; ambiguous basenames are handled by lookup.
      tds[path.substring('产品TDS/'.length, path.length - '.TDS.md'.length)] =
          content;
      continue;
    }
    final item =
        ProductItem.fromMdContent(path, content, origin: DataOrigin.official);
    switch (path.split('/').first) {
      case '产品列表':
        products.add(item);
      case '产品应用':
        applications.add(item);
      case '产品配方':
        formulas.add(item);
    }
  }
  for (final items in [products, applications, formulas]) {
    items.sort((a, b) => compareNaturalText(a.filePath, b.filePath));
  }
  return DataSnapshot(
      products: List.unmodifiable(products),
      applications: List.unmodifiable(applications),
      formulas: List.unmodifiable(formulas),
      tds: Map.unmodifiable(tds),
      rules: rules);
}
