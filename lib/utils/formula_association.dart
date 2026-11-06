import 'package:yaml/yaml.dart';

import '../models/product_item.dart';
import 'grade_lookup.dart';

final _completeGrade = RegExp(
  r'^(?:RS|RD)\d[A-Z0-9]*(?:[-.][A-Z0-9]+)*$',
  caseSensitive: false,
);
final _legacyFinish = RegExp(r'-(?:亮|哑|银|黑|底)$');
// Official recipes resolve only official records. Personal recipes resolve the
// current explicit catalog target, including an official target.
bool _sourceMatches(ProductItem product, ProductItem formula) =>
    (product.origin != DataOrigin.user ||
        product.filePath.startsWith('user/产品列表/')) &&
    (formula.origin != DataOrigin.user ||
        formula.filePath.startsWith('user/产品配方/')) &&
    (formula.origin == DataOrigin.user || product.origin != DataOrigin.user) &&
    (formula.formulaProductRecords == null ||
        formula.formulaProductRecords![product.fileName] ==
            '${product.origin.name}:${product.filePath}');
const _materialHeaders = {'原料编号', '原料名称', '原料', '组分'};

Set<String> _wikiGradeKeys(String value) {
  final grades = <String>{};
  for (final match in RegExp(r'\[\[([^\]]+)\]\]').allMatches(value)) {
    final grade = match
        .group(1)!
        .replaceAll(r'\|', '|')
        .split('|')
        .first
        .trim()
        .replaceFirst(RegExp(r'^产品列表/'), '')
        .replaceFirst(RegExp(r'\.md$', caseSensitive: false), '');
    if (_completeGrade.hasMatch(grade)) grades.add(gradeLookupKey(grade));
  }
  return grades;
}

Set<String> _declaredGradeKeys(String content) {
  final frontmatter =
      RegExp(r'^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)').firstMatch(content);
  if (frontmatter == null) return const {};
  try {
    final metadata = loadYaml(frontmatter.group(1)!);
    final value = metadata is YamlMap ? metadata['关联产品'] : null;
    return value is String ? _wikiGradeKeys(value) : const {};
  } on YamlException {
    return const {};
  }
}

List<String> _tableCells(String line) {
  final cells = <String>[];
  final cell = StringBuffer();
  var inWiki = false;
  for (var i = 1; i < line.length; i++) {
    if (line[i] == r'\' && i + 1 < line.length && line[i + 1] == '|') {
      cell.write('|');
      i++;
    } else if (line.startsWith('[[', i)) {
      inWiki = true;
      cell.write('[[');
      i++;
    } else if (line.startsWith(']]', i)) {
      inWiki = false;
      cell.write(']]');
      i++;
    } else if (line[i] == '|' && !inWiki) {
      cells.add(cell.toString().trim());
      cell.clear();
    } else {
      cell.write(line[i]);
    }
  }
  cells.add(cell.toString().trim());
  return cells;
}

Set<String> _ingredientGradeKeys(String content) {
  final grades = <String>{};
  int? materialColumn;
  var awaitingDelimiter = false;
  String? fence;
  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    final marker = RegExp(r'^(`{3,}|~{3,})').firstMatch(trimmed)?.group(1);
    if (fence != null) {
      if (marker != null &&
          marker[0] == fence[0] &&
          marker.length >= fence.length) {
        fence = null;
      }
      continue;
    }
    if (marker != null) {
      fence = marker;
      materialColumn = null;
      continue;
    }
    if (!trimmed.startsWith('|')) {
      materialColumn = null;
      continue;
    }
    final cells = _tableCells(trimmed);
    final header = cells.indexWhere(_materialHeaders.contains);
    if (header != -1) {
      materialColumn = header;
      awaitingDelimiter = true;
      continue;
    }
    if (materialColumn == null) continue;
    if (awaitingDelimiter) {
      if (cells.last.isEmpty) cells.removeLast();
      if (cells.isEmpty ||
          !cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell))) {
        materialColumn = null;
      }
      awaitingDelimiter = false;
      continue;
    }
    if (materialColumn >= cells.length) continue;
    grades.addAll(_wikiGradeKeys(cells[materialColumn]));
  }
  return grades;
}

/// 按完整牌号或明确实验牌号关联配方，供列表与详情共用。
///
/// 参与产品取“关联产品”标量双链与原料列双链的并集，不扫描任意正文。
/// 无有效显式关联时才兼容旧标题，只移除最后的亮/哑/银/黑/底后缀。
/// 同一配方多次命中时保留首次出现，不做数字前缀或 RD/RS 推断。
/// [productCatalog] 必须是完整、未筛选的产品目录；独立产品本号优先于他品实验别名。
List<ProductItem> linkedFormulasForProduct(
  ProductItem product,
  Iterable<ProductItem> formulas, {
  required Iterable<ProductItem> productCatalog,
}) {
  if (product.folder != '产品列表') return const [];
  final canonicalGrades = {
    for (final item in productCatalog)
      if (item.folder == '产品列表') gradeLookupKey(item.fileName),
  };
  final experimental = product.experimentalCode;
  final identities = {
    gradeLookupKey(product.fileName),
    if (experimental?.isNotEmpty == true &&
        !canonicalGrades.contains(gradeLookupKey(experimental!)))
      gradeLookupKey(experimental),
  };
  final matched = <String, ProductItem>{};
  for (final formula in formulas) {
    if (formula.folder != '产品配方' || !_sourceMatches(product, formula)) continue;
    final structured = formula.formulaDocument;
    if (structured != null) {
      if (structured.associatedProducts.contains(product.fileName)) {
        matched.putIfAbsent(formula.fileName, () => formula);
      }
      continue;
    }
    final stem = formula.fileName.replaceFirst(RegExp(r'\.md$'), '');
    final grade = stem.replaceFirst(_legacyFinish, '');
    final participants = {
      ..._declaredGradeKeys(formula.rawContent),
      ..._ingredientGradeKeys(formula.rawContent),
    };
    if (participants.isEmpty && _completeGrade.hasMatch(grade)) {
      participants.add(gradeLookupKey(grade));
    }
    if (participants.any(identities.contains)) {
      matched.putIfAbsent(formula.fileName, () => formula);
    }
  }
  return matched.values.toList();
}

/// Immutable associations for one complete catalog snapshot. No global cache.
/// Legacy documents are parsed once per snapshot, not once per visible row.
class FormulaAssociationIndex {
  final Map<ProductItem, List<ProductItem>> _byProduct;

  FormulaAssociationIndex._(this._byProduct);

  factory FormulaAssociationIndex({
    required Iterable<ProductItem> productCatalog,
    required Iterable<ProductItem> formulas,
  }) {
    final products =
        productCatalog.where((item) => item.folder == '产品列表').toList();
    final canonical = {for (final p in products) gradeLookupKey(p.fileName)};
    final exact = <String, Set<ProductItem>>{};
    final legacy = <String, Set<ProductItem>>{};
    final matches = <ProductItem, Map<String, ProductItem>>{};
    for (final product in products) {
      matches[product] = {};
      exact.putIfAbsent(product.fileName, () => {}).add(product);
      final identities = {gradeLookupKey(product.fileName)};
      final experimental = product.experimentalCode;
      if (experimental?.isNotEmpty == true &&
          !canonical.contains(gradeLookupKey(experimental!))) {
        identities.add(gradeLookupKey(experimental));
      }
      for (final key in identities) {
        legacy.putIfAbsent(key, () => {}).add(product);
      }
    }
    for (final formula in formulas) {
      if (formula.folder != '产品配方') continue;
      final targets = <ProductItem>{};
      final document = formula.formulaDocument;
      if (document != null) {
        for (final grade in document.associatedProducts) {
          targets.addAll(exact[grade] ?? const <ProductItem>{});
        }
      } else {
        final participants = {
          ..._declaredGradeKeys(formula.rawContent),
          ..._ingredientGradeKeys(formula.rawContent),
        };
        final grade = formula.fileName
            .replaceFirst(RegExp(r'\.md$'), '')
            .replaceFirst(_legacyFinish, '');
        if (participants.isEmpty && _completeGrade.hasMatch(grade)) {
          participants.add(gradeLookupKey(grade));
        }
        for (final key in participants) {
          targets.addAll(legacy[key] ?? const <ProductItem>{});
        }
      }
      for (final product in targets) {
        if (!_sourceMatches(product, formula)) continue;
        matches[product]!.putIfAbsent(formula.fileName, () => formula);
      }
    }
    return FormulaAssociationIndex._(Map.unmodifiable({
      for (final entry in matches.entries)
        entry.key: List<ProductItem>.unmodifiable(entry.value.values),
    }));
  }

  List<ProductItem> forProduct(ProductItem product) =>
      _byProduct[product] ?? const [];
}
